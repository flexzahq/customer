-- Flexza RPCs (Step 4)
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
--
-- Patient: request_book_otp → book_token (OTP required every book)
-- Clinic:  open_today_session, set_session_status, complete_token, skip_token
--
-- All SECURITY DEFINER (bypass RLS for controlled writes).
-- Staff auth lock-down comes in later steps; do not expose service_role in frontend.

-- Supabase: pgcrypto lives in `extensions` schema
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- Ensure ON CONFLICT targets exist (safe if Step 2 already applied)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  ALTER TABLE public.patients ADD CONSTRAINT patients_mobile_unique UNIQUE (mobile);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.queue_sessions
    ADD CONSTRAINT queue_sessions_doctor_date_unique UNIQUE (doctor_id, session_date);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_today()
RETURNS date
LANGUAGE sql
STABLE
AS $$
  SELECT (timezone('Asia/Kolkata', now()))::date;
$$;

CREATE OR REPLACE FUNCTION public.flexza_normalize_mobile(p_mobile text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(coalesce(p_mobile, ''), '\D', '', 'g');
$$;

CREATE OR REPLACE FUNCTION public.flexza_assert_mobile(p_mobile text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_mobile text := public.flexza_normalize_mobile(p_mobile);
BEGIN
  IF v_mobile !~ '^[0-9]{10}$' THEN
    RAISE EXCEPTION 'invalid_mobile' USING ERRCODE = '22023';
  END IF;
  RETURN v_mobile;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_get_active_clinic(p_slug text)
RETURNS public.clinics
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
BEGIN
  SELECT * INTO v_clinic
  FROM public.clinics
  WHERE slug = lower(trim(p_slug))
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_clinic;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_primary_doctor(p_clinic_id uuid)
RETURNS public.doctors
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  SELECT * INTO v_doctor
  FROM public.doctors
  WHERE clinic_id = p_clinic_id
    AND is_active = true
  ORDER BY sort_order ASC, created_at ASC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_doctor;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_promote_next_waiting(p_session_id uuid)
RETURNS public.tokens
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next public.tokens;
BEGIN
  -- Only promote if nothing is currently serving
  IF EXISTS (
    SELECT 1 FROM public.tokens
    WHERE session_id = p_session_id AND status = 'serving'
  ) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_next
  FROM public.tokens
  WHERE session_id = p_session_id
    AND status = 'waiting'
  ORDER BY number ASC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.tokens
  SET status = 'serving',
      called_at = now()
  WHERE id = v_next.id
  RETURNING * INTO v_next;

  RETURN v_next;
END;
$$;

-- ---------------------------------------------------------------------------
-- request_book_otp
-- OTP required on every book. dev_otp returned for testing until SMS (Step 5).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_book_otp(
  p_clinic_slug text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text;
  v_clinic public.clinics;
  v_code text;
  v_hash text;
  v_id uuid;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_clinic := public.flexza_get_active_clinic(p_clinic_slug);

  -- Invalidate previous unused challenges for this mobile + purpose + clinic
  UPDATE public.otp_challenges
  SET expires_at = now()
  WHERE mobile = v_mobile
    AND purpose = 'book_token'
    AND clinic_id = v_clinic.id
    AND verified_at IS NULL
    AND expires_at > now();

  -- OTP generation body replaced/hardened in 20260304150000_flexza_otp_hardening.sql
  v_code := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_hash := extensions.crypt(v_code, extensions.gen_salt('bf'));

  INSERT INTO public.otp_challenges (mobile, code_hash, purpose, clinic_id, expires_at)
  VALUES (
    v_mobile,
    v_hash,
    'book_token',
    v_clinic.id,
    now() + interval '10 minutes'
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'ok', true,
    'challenge_id', v_id,
    'expires_in_seconds', 600,
    'dev_otp', v_code
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- book_token — OTP required every time; sequential number; pause/closed block
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.book_token(
  p_clinic_slug text,
  p_mobile text,
  p_name text,
  p_otp_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text;
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_session public.queue_sessions;
  v_patient public.patients;
  v_challenge public.otp_challenges;
  v_token public.tokens;
  v_next_number int;
  v_has_serving boolean;
  v_name text;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_clinic := public.flexza_get_active_clinic(p_clinic_slug);
  v_doctor := public.flexza_primary_doctor(v_clinic.id);
  v_name := nullif(trim(coalesce(p_name, '')), '');

  IF p_otp_code IS NULL OR length(trim(p_otp_code)) <> 4 OR trim(p_otp_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'invalid_otp' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_challenge
  FROM public.otp_challenges
  WHERE mobile = v_mobile
    AND purpose = 'book_token'
    AND clinic_id = v_clinic.id
    AND verified_at IS NULL
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'otp_not_found_or_expired' USING ERRCODE = 'P0002';
  END IF;

  IF v_challenge.attempts >= 5 THEN
    RAISE EXCEPTION 'otp_too_many_attempts' USING ERRCODE = '22023';
  END IF;

  IF v_challenge.code_hash IS DISTINCT FROM extensions.crypt(trim(p_otp_code), v_challenge.code_hash) THEN
    UPDATE public.otp_challenges
    SET attempts = attempts + 1
    WHERE id = v_challenge.id;
    RAISE EXCEPTION 'otp_invalid' USING ERRCODE = '22023';
  END IF;

  UPDATE public.otp_challenges
  SET verified_at = now()
  WHERE id = v_challenge.id;

  -- Session for today
  SELECT * INTO v_session
  FROM public.queue_sessions
  WHERE doctor_id = v_doctor.id
    AND session_date = public.flexza_today()
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.queue_sessions (doctor_id, clinic_id, session_date, status)
    VALUES (v_doctor.id, v_clinic.id, public.flexza_today(), 'open')
    RETURNING * INTO v_session;
  END IF;

  IF v_session.status = 'paused' THEN
    RAISE EXCEPTION 'booking_paused' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.status = 'closed' THEN
    RAISE EXCEPTION 'booking_closed' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.patients (mobile, name)
  VALUES (v_mobile, v_name)
  ON CONFLICT (mobile) DO UPDATE
    SET name = COALESCE(EXCLUDED.name, public.patients.name),
        updated_at = now()
  RETURNING * INTO v_patient;

  -- ON CONFLICT requires unique constraint name - we have unique index on mobile
  -- PostgreSQL ON CONFLICT (mobile) works with unique index on mobile

  IF EXISTS (
    SELECT 1 FROM public.tokens
    WHERE session_id = v_session.id
      AND patient_id = v_patient.id
      AND status IN ('waiting', 'serving')
  ) THEN
    RAISE EXCEPTION 'already_in_queue' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(max(number), 0) + 1 INTO v_next_number
  FROM public.tokens
  WHERE session_id = v_session.id;

  SELECT EXISTS (
    SELECT 1 FROM public.tokens
    WHERE session_id = v_session.id AND status = 'serving'
  ) INTO v_has_serving;

  INSERT INTO public.tokens (
    session_id, clinic_id, doctor_id, patient_id, number, status, called_at
  )
  VALUES (
    v_session.id,
    v_clinic.id,
    v_doctor.id,
    v_patient.id,
    v_next_number,
    CASE WHEN v_has_serving THEN 'waiting'::public.token_status ELSE 'serving'::public.token_status END,
    CASE WHEN v_has_serving THEN NULL ELSE now() END
  )
  RETURNING * INTO v_token;

  RETURN jsonb_build_object(
    'ok', true,
    'token_id', v_token.id,
    'token_number', v_token.number,
    'status', v_token.status,
    'session_id', v_session.id,
    'clinic_slug', v_clinic.slug,
    'doctor_name', v_doctor.name,
    'patient_mobile', v_mobile,
    'patient_name', v_patient.name
  );
END;
$$;

-- Fix patients upsert: unique index is on mobile but ON CONFLICT needs constraint.
-- Ensure conflict target works — unique index patients_mobile_key on (mobile) allows ON CONFLICT (mobile).

-- ---------------------------------------------------------------------------
-- open_today_session — staff opens OPD for a doctor
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_today_session(p_doctor_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_session public.queue_sessions;
BEGIN
  SELECT * INTO v_doctor FROM public.doctors WHERE id = p_doctor_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.queue_sessions (doctor_id, clinic_id, session_date, status)
  VALUES (v_doctor.id, v_doctor.clinic_id, public.flexza_today(), 'open')
  ON CONFLICT (doctor_id, session_date) DO UPDATE
    SET status = 'open',
        updated_at = now()
  RETURNING * INTO v_session;

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'status', v_session.status,
    'session_date', v_session.session_date
  );
END;
$$;

-- queue_sessions unique is via unique INDEX queue_sessions_doctor_date_key
-- ON CONFLICT (doctor_id, session_date) requires a unique constraint/index on those columns — we have it.

-- ---------------------------------------------------------------------------
-- set_session_status — open | paused | closed
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_session_status(
  p_session_id uuid,
  p_status public.session_status
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.queue_sessions;
BEGIN
  UPDATE public.queue_sessions
  SET status = p_status
  WHERE id = p_session_id
  RETURNING * INTO v_session;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'status', v_session.status
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- complete_token — finish current serving, promote next waiting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_token(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current public.tokens;
  v_next public.tokens;
BEGIN
  SELECT * INTO v_current
  FROM public.tokens
  WHERE session_id = p_session_id
    AND status = 'serving'
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Try promote waiting then complete is wrong; just promote if nothing serving
    v_next := public.flexza_promote_next_waiting(p_session_id);
    IF v_next.id IS NULL THEN
      RAISE EXCEPTION 'no_serving_token' USING ERRCODE = 'P0002';
    END IF;
    RETURN jsonb_build_object(
      'ok', true,
      'action', 'promoted_only',
      'serving_token_number', v_next.number,
      'serving_token_id', v_next.id
    );
  END IF;

  UPDATE public.tokens
  SET status = 'completed',
      completed_at = now()
  WHERE id = v_current.id
  RETURNING * INTO v_current;

  v_next := public.flexza_promote_next_waiting(p_session_id);

  RETURN jsonb_build_object(
    'ok', true,
    'action', 'completed',
    'completed_token_number', v_current.number,
    'completed_token_id', v_current.id,
    'serving_token_number', v_next.number,
    'serving_token_id', v_next.id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- skip_token — skip current serving, promote next waiting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.skip_token(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current public.tokens;
  v_next public.tokens;
BEGIN
  SELECT * INTO v_current
  FROM public.tokens
  WHERE session_id = p_session_id
    AND status = 'serving'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_serving_token' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.tokens
  SET status = 'skipped'
  WHERE id = v_current.id
  RETURNING * INTO v_current;

  v_next := public.flexza_promote_next_waiting(p_session_id);

  RETURN jsonb_build_object(
    'ok', true,
    'action', 'skipped',
    'skipped_token_number', v_current.number,
    'skipped_token_id', v_current.id,
    'serving_token_number', v_next.number,
    'serving_token_id', v_next.id
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants (callable from app with anon key; staff auth later)
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.request_book_otp(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.book_token(text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_today_session(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_session_status(uuid, public.session_status) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_token(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.skip_token(uuid) TO anon, authenticated;
