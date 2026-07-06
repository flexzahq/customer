-- Patient session dashboard, full queue, doctor queue settings, daily token limits
-- Run in: Supabase Dashboard → SQL Editor

-- ---------------------------------------------------------------------------
-- Doctor queue settings
-- ---------------------------------------------------------------------------
ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS minutes_per_patient int NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS max_tokens_per_day int NOT NULL DEFAULT 3;

DO $$ BEGIN
  ALTER TABLE public.doctors
    ADD CONSTRAINT doctors_minutes_per_patient_range
    CHECK (minutes_per_patient BETWEEN 1 AND 120);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.doctors
    ADD CONSTRAINT doctors_max_tokens_per_day_range
    CHECK (max_tokens_per_day BETWEEN 1 AND 20);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

INSERT INTO public.flexza_app_settings (key, value)
VALUES
  ('default_minutes_per_patient', '10'::jsonb),
  ('default_max_tokens_per_day', '3'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- resolve_doctor_code — include queue settings
-- ---------------------------------------------------------------------------
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
    'clinic_subtitle', v_clinic.subtitle,
    'clinic_phone', v_clinic.phone,
    'clinic_email', v_clinic.email,
    'clinic_address', v_clinic.address,
    'clinic_about', v_clinic.about,
    'morning_start', v_clinic.morning_start,
    'morning_end', v_clinic.morning_end,
    'evening_start', v_clinic.evening_start,
    'evening_end', v_clinic.evening_end,
    'minutes_per_patient', v_doctor.minutes_per_patient,
    'max_tokens_per_day', v_doctor.max_tokens_per_day
  );
EXCEPTION
  WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

-- ---------------------------------------------------------------------------
-- Public queue snapshot (full waiting list)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_public_queue(p_doctor_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_session public.queue_sessions;
  v_serving int;
  v_waiting jsonb;
  v_waiting_count int;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_session
  FROM public.queue_sessions
  WHERE doctor_id = v_doctor.id
    AND session_date = public.flexza_today();

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'session_id', null,
      'session_status', null,
      'current_token', null,
      'waiting_tokens', '[]'::jsonb,
      'waiting_count', 0,
      'minutes_per_patient', v_doctor.minutes_per_patient,
      'max_tokens_per_day', v_doctor.max_tokens_per_day
    );
  END IF;

  SELECT t.number INTO v_serving
  FROM public.tokens t
  WHERE t.session_id = v_session.id AND t.status = 'serving'
  LIMIT 1;

  SELECT
    coalesce(jsonb_agg(t.number ORDER BY t.number), '[]'::jsonb),
    count(*)::int
  INTO v_waiting, v_waiting_count
  FROM public.tokens t
  WHERE t.session_id = v_session.id AND t.status = 'waiting';

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', v_session.id,
    'session_status', v_session.status,
    'current_token', v_serving,
    'waiting_tokens', v_waiting,
    'waiting_count', v_waiting_count,
    'minutes_per_patient', v_doctor.minutes_per_patient,
    'max_tokens_per_day', v_doctor.max_tokens_per_day
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Patient dashboard (active token + history for logged-in mobile)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_patient_dashboard(
  p_doctor_code text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text;
  v_doctor public.doctors;
  v_patient public.patients;
  v_active jsonb;
  v_history jsonb;
  v_tokens_today int;
  v_max_per_day int;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);
  v_max_per_day := v_doctor.max_tokens_per_day;

  SELECT * INTO v_patient FROM public.patients WHERE mobile = v_mobile;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'logged_in', false,
      'patient_name', null,
      'active_token', null,
      'tokens_booked_today', 0,
      'max_tokens_per_day', v_max_per_day,
      'can_book', true,
      'history', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.booked_at DESC), '[]'::jsonb)
  INTO v_history
  FROM (
    SELECT
      t.id AS token_id,
      t.number AS token_number,
      t.status,
      t.booked_at,
      t.completed_at,
      qs.session_date
    FROM public.tokens t
    JOIN public.queue_sessions qs ON qs.id = t.session_id
    WHERE t.doctor_id = v_doctor.id
      AND t.patient_id = v_patient.id
      AND t.status <> 'cancelled'
    ORDER BY t.booked_at DESC
    LIMIT 20
  ) row;

  SELECT to_jsonb(row) INTO v_active
  FROM (
    SELECT
      t.id AS token_id,
      t.number AS token_number,
      t.status,
      t.booked_at,
      qs.session_date
    FROM public.tokens t
    JOIN public.queue_sessions qs ON qs.id = t.session_id
    WHERE t.doctor_id = v_doctor.id
      AND t.patient_id = v_patient.id
      AND qs.session_date = public.flexza_today()
      AND t.status IN ('waiting', 'serving')
    ORDER BY t.booked_at DESC
    LIMIT 1
  ) row;

  SELECT count(*)::int INTO v_tokens_today
  FROM public.tokens t
  JOIN public.queue_sessions qs ON qs.id = t.session_id
  WHERE t.doctor_id = v_doctor.id
    AND t.patient_id = v_patient.id
    AND qs.session_date = public.flexza_today()
    AND t.status <> 'cancelled';

  RETURN jsonb_build_object(
    'ok', true,
    'logged_in', true,
    'patient_name', v_patient.name,
    'active_token', v_active,
    'tokens_booked_today', v_tokens_today,
    'max_tokens_per_day', v_max_per_day,
    'can_book', v_tokens_today < v_max_per_day AND v_active IS NULL,
    'history', v_history
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- book_token — name required, daily limit, one active at a time
-- ---------------------------------------------------------------------------
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
  v_today_count int;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;
  v_name := nullif(trim(coalesce(p_name, '')), '');

  IF v_name IS NULL OR length(v_name) < 2 THEN
    RAISE EXCEPTION 'patient_name_required' USING ERRCODE = '22023';
  END IF;

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

  INSERT INTO public.patients (mobile, name)
  VALUES (v_mobile, v_name)
  ON CONFLICT (mobile) DO UPDATE
    SET name = EXCLUDED.name,
        updated_at = now()
  RETURNING * INTO v_patient;

  SELECT count(*)::int INTO v_today_count
  FROM public.tokens t
  JOIN public.queue_sessions qs ON qs.id = t.session_id
  WHERE t.doctor_id = v_doctor.id
    AND t.patient_id = v_patient.id
    AND qs.session_date = public.flexza_today()
    AND t.status <> 'cancelled';

  IF v_today_count >= v_doctor.max_tokens_per_day THEN
    RAISE EXCEPTION 'token_daily_limit_reached' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tokens t
    JOIN public.queue_sessions qs ON qs.id = t.session_id
    WHERE t.doctor_id = v_doctor.id
      AND t.patient_id = v_patient.id
      AND qs.session_date = public.flexza_today()
      AND t.status IN ('waiting', 'serving')
  ) THEN
    RAISE EXCEPTION 'already_in_queue' USING ERRCODE = 'P0001';
  END IF;

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
    'patient_name', v_patient.name,
    'tokens_booked_today', v_today_count + 1,
    'max_tokens_per_day', v_doctor.max_tokens_per_day
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Vendor: update doctor queue settings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vendor_update_doctor_settings(
  p_session_token text,
  p_minutes_per_patient int,
  p_max_tokens_per_day int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_minutes int;
  v_max int;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);

  v_minutes := coalesce(p_minutes_per_patient, 10);
  v_max := coalesce(p_max_tokens_per_day, 3);

  IF v_minutes < 1 OR v_minutes > 120 THEN
    RAISE EXCEPTION 'invalid_minutes_per_patient' USING ERRCODE = '22023';
  END IF;

  IF v_max < 1 OR v_max > 20 THEN
    RAISE EXCEPTION 'invalid_max_tokens_per_day' USING ERRCODE = '22023';
  END IF;

  UPDATE public.doctors
  SET
    minutes_per_patient = v_minutes,
    max_tokens_per_day = v_max,
    updated_at = now()
  WHERE id = v_session.doctor_id;

  RETURN jsonb_build_object(
    'ok', true,
    'minutes_per_patient', v_minutes,
    'max_tokens_per_day', v_max
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.vendor_get_doctor_settings(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_doctor public.doctors;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);
  SELECT * INTO v_doctor FROM public.doctors WHERE id = v_session.doctor_id;

  RETURN jsonb_build_object(
    'ok', true,
    'minutes_per_patient', v_doctor.minutes_per_patient,
    'max_tokens_per_day', v_doctor.max_tokens_per_day,
    'default_minutes_per_patient', public.flexza_setting_int('default_minutes_per_patient', 10),
    'default_max_tokens_per_day', public.flexza_setting_int('default_max_tokens_per_day', 3)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin: platform queue defaults
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_queue_defaults(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  RETURN jsonb_build_object(
    'ok', true,
    'default_minutes_per_patient', public.flexza_setting_int('default_minutes_per_patient', 10),
    'default_max_tokens_per_day', public.flexza_setting_int('default_max_tokens_per_day', 3)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_queue_defaults(
  p_session_token text,
  p_minutes_per_patient int,
  p_max_tokens_per_day int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_minutes_per_patient < 1 OR p_minutes_per_patient > 120 THEN
    RAISE EXCEPTION 'invalid_minutes_per_patient' USING ERRCODE = '22023';
  END IF;

  IF p_max_tokens_per_day < 1 OR p_max_tokens_per_day > 20 THEN
    RAISE EXCEPTION 'invalid_max_tokens_per_day' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.flexza_app_settings (key, value)
  VALUES ('default_minutes_per_patient', to_jsonb(p_minutes_per_patient))
  ON CONFLICT (key) DO UPDATE SET value = to_jsonb(p_minutes_per_patient), updated_at = now();

  INSERT INTO public.flexza_app_settings (key, value)
  VALUES ('default_max_tokens_per_day', to_jsonb(p_max_tokens_per_day))
  ON CONFLICT (key) DO UPDATE SET value = to_jsonb(p_max_tokens_per_day), updated_at = now();

  RETURN jsonb_build_object(
    'ok', true,
    'default_minutes_per_patient', p_minutes_per_patient,
    'default_max_tokens_per_day', p_max_tokens_per_day
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_apply_queue_defaults_to_doctors(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_minutes int;
  v_max int;
  v_updated int;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  v_minutes := public.flexza_setting_int('default_minutes_per_patient', 10);
  v_max := public.flexza_setting_int('default_max_tokens_per_day', 3);

  UPDATE public.doctors
  SET
    minutes_per_patient = v_minutes,
    max_tokens_per_day = v_max,
    updated_at = now();

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'doctors_updated', v_updated);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_queue(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_dashboard(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_update_doctor_settings(text, int, int) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_get_doctor_settings(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_queue_defaults(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_queue_defaults(text, int, int) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_apply_queue_defaults_to_doctors(text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
