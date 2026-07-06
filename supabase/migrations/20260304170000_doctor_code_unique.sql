-- Unique doctor code (entry / QR). Names can duplicate; codes cannot.
-- Run in: Supabase Dashboard → SQL Editor → Run

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS code text;

-- Backfill any existing rows with a stable unique code from id
UPDATE public.doctors
SET code = upper(substr(replace(id::text, '-', ''), 1, 8))
WHERE code IS NULL OR btrim(code) = '';

ALTER TABLE public.doctors
  ALTER COLUMN code SET NOT NULL;

DO $$ BEGIN
  ALTER TABLE public.doctors
    ADD CONSTRAINT doctors_code_format CHECK (code ~ '^[A-Z0-9]{4,12}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS doctors_code_key ON public.doctors (code);

COMMENT ON COLUMN public.doctors.code IS
  'Globally unique doctor code for QR and entry screen. Not the display name.';

-- ---------------------------------------------------------------------------
-- Resolve active doctor by unique code
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_get_doctor_by_code(p_code text)
RETURNS public.doctors
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_doctor public.doctors;
BEGIN
  IF v_code IS NULL OR length(v_code) < 4 OR length(v_code) > 12 THEN
    RAISE EXCEPTION 'invalid_doctor_code' USING ERRCODE = '22023';
  END IF;

  SELECT d.* INTO v_doctor
  FROM public.doctors d
  JOIN public.clinics c ON c.id = d.clinic_id
  WHERE d.code = v_code
    AND d.is_active = true
    AND c.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_doctor;
END;
$$;

-- Public lookup for entry screen (no sensitive fields)
CREATE OR REPLACE FUNCTION public.resolve_doctor_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_clinic public.clinics;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_code);

  SELECT * INTO v_clinic
  FROM public.clinics
  WHERE id = v_doctor.clinic_id;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'clinic_id', v_clinic.id,
    'clinic_name', v_clinic.name,
    'clinic_slug', v_clinic.slug,
    'clinic_subtitle', v_clinic.subtitle
  );
EXCEPTION
  WHEN others THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_doctor_code(text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- OTP + book by doctor_code (unique), not clinic name/slug
-- Must DROP first: Postgres cannot rename input params via CREATE OR REPLACE
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.request_book_otp(text, text);
DROP FUNCTION IF EXISTS public.book_token(text, text, text, text);

CREATE OR REPLACE FUNCTION public.request_book_otp(
  p_doctor_code text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text;
  v_doctor public.doctors;
  v_clinic public.clinics;
  v_code text;
  v_hash text;
  v_id uuid;
  v_cooldown int;
  v_max_per_hour int;
  v_recent_count int;
  v_last_created timestamptz;
  v_expose_dev boolean;
  v_result jsonb;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;

  v_cooldown := public.flexza_setting_int('otp_cooldown_seconds', 30);
  v_max_per_hour := public.flexza_setting_int('otp_max_per_hour', 5);
  v_expose_dev := public.flexza_setting_bool('expose_dev_otp', true);

  SELECT count(*)::int, max(created_at)
  INTO v_recent_count, v_last_created
  FROM public.otp_challenges
  WHERE mobile = v_mobile
    AND purpose = 'book_token'
    AND clinic_id = v_clinic.id
    AND created_at > now() - interval '1 hour';

  IF v_recent_count >= v_max_per_hour THEN
    RAISE EXCEPTION 'otp_rate_limited' USING ERRCODE = 'P0001';
  END IF;

  IF v_last_created IS NOT NULL
     AND v_last_created > now() - make_interval(secs => v_cooldown) THEN
    RAISE EXCEPTION 'otp_cooldown' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.otp_challenges
  SET expires_at = now()
  WHERE mobile = v_mobile
    AND purpose = 'book_token'
    AND clinic_id = v_clinic.id
    AND verified_at IS NULL
    AND expires_at > now();

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

  v_result := jsonb_build_object(
    'ok', true,
    'challenge_id', v_id,
    'expires_in_seconds', 600,
    'message', 'OTP sent',
    'doctor_code', v_doctor.code
  );

  IF v_expose_dev THEN
    v_result := v_result || jsonb_build_object('dev_otp', v_code);
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.book_token(
  p_doctor_code text,
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
  v_doctor public.doctors;
  v_clinic public.clinics;
  v_session public.queue_sessions;
  v_patient public.patients;
  v_challenge public.otp_challenges;
  v_token public.tokens;
  v_next_number int;
  v_has_serving boolean;
  v_name text;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;
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
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'clinic_slug', v_clinic.slug,
    'patient_mobile', v_mobile,
    'patient_name', v_patient.name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_book_otp(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.book_token(text, text, text, text) TO anon, authenticated;
