-- Per-doctor access validity (admin override). NULL validity_days = inherit clinic plan.

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS validity_days int,
  ADD COLUMN IF NOT EXISTS access_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS access_expires_at timestamptz;

COMMENT ON COLUMN public.doctors.validity_days IS 'Custom access days; NULL = use clinic plan validity';
COMMENT ON COLUMN public.doctors.access_expires_at IS 'Doctor access end; only when validity_days is set';

-- ---------------------------------------------------------------------------
-- Doctor access helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_apply_doctor_access_period(
  p_doctor_id uuid,
  p_validity_days int
)
RETURNS public.doctors
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days int := greatest(coalesce(p_validity_days, 1), 1);
  v_doctor public.doctors;
BEGIN
  UPDATE public.doctors
  SET
    validity_days = v_days,
    access_started_at = now(),
    access_expires_at = now() + make_interval(days => v_days),
    updated_at = now()
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_doctor;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_clear_doctor_access_period(p_doctor_id uuid)
RETURNS public.doctors
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  UPDATE public.doctors
  SET
    validity_days = NULL,
    access_started_at = NULL,
    access_expires_at = NULL,
    updated_at = now()
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_doctor;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_assert_doctor_access(p_doctor_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_clinic public.clinics;
BEGIN
  SELECT * INTO v_doctor FROM public.doctors WHERE id = p_doctor_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_doctor.is_active THEN
    RAISE EXCEPTION 'doctor_inactive' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_clinic.status = 'pending' THEN
    RAISE EXCEPTION 'clinic_pending_approval' USING ERRCODE = 'P0001';
  END IF;

  IF v_clinic.status <> 'active' THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

  IF v_doctor.validity_days IS NOT NULL AND v_doctor.access_expires_at IS NOT NULL THEN
    IF v_doctor.access_expires_at <= now() THEN
      RAISE EXCEPTION 'doctor_access_expired' USING ERRCODE = 'P0001';
    END IF;
    RETURN;
  END IF;

  IF v_clinic.plan_expires_at IS NOT NULL AND v_clinic.plan_expires_at <= now() THEN
    RAISE EXCEPTION 'clinic_plan_expired' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- Staff session — check logged-in doctor access
CREATE OR REPLACE FUNCTION public.flexza_assert_staff_session(p_session_token text)
RETURNS public.staff_sessions
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token text := trim(coalesce(p_session_token, ''));
  v_session public.staff_sessions;
BEGIN
  IF v_token = '' THEN
    RAISE EXCEPTION 'staff_unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM public.staff_sessions
  WHERE token = v_token
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_unauthorized' USING ERRCODE = '42501';
  END IF;

  PERFORM public.flexza_assert_doctor_access(v_session.doctor_id);

  RETURN v_session;
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin doctor RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_doctors(
  p_session_token text,
  p_clinic_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.sort_order, row.created_at), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      d.id,
      d.name,
      d.code,
      d.is_active,
      d.sort_order,
      d.created_at,
      d.minutes_per_patient,
      d.max_tokens_per_day,
      d.validity_days,
      d.access_started_at,
      d.access_expires_at,
      (d.validity_days IS NOT NULL) AS uses_custom_validity,
      CASE
        WHEN d.validity_days IS NOT NULL AND d.access_expires_at IS NOT NULL THEN
          greatest(0, ceil(extract(epoch FROM (d.access_expires_at - now())) / 86400)::int)
        ELSE NULL
      END AS access_days_remaining,
      (
        d.validity_days IS NOT NULL
        AND d.access_expires_at IS NOT NULL
        AND d.access_expires_at <= now()
      ) AS access_expired
    FROM public.doctors d
    WHERE d.clinic_id = p_clinic_id
  ) row;

  RETURN jsonb_build_object('ok', true, 'doctors', v_rows);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_update_doctor(text, uuid, text, text, boolean, int, int);

CREATE OR REPLACE FUNCTION public.admin_update_doctor(
  p_session_token text,
  p_doctor_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL,
  p_minutes_per_patient int DEFAULT NULL,
  p_max_tokens_per_day int DEFAULT NULL,
  p_validity_days int DEFAULT NULL,
  p_use_clinic_plan_validity boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_doctor public.doctors;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_doctor_name' USING ERRCODE = '22023';
  END IF;

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  IF p_code IS NOT NULL AND length(trim(p_code)) > 0 THEN
    IF length(v_code) < 4 OR length(v_code) > 12 THEN
      RAISE EXCEPTION 'invalid_doctor_code' USING ERRCODE = '22023';
    END IF;
  ELSE
    v_code := NULL;
  END IF;

  IF p_minutes_per_patient IS NOT NULL
     AND (p_minutes_per_patient < 1 OR p_minutes_per_patient > 120) THEN
    RAISE EXCEPTION 'invalid_minutes_per_patient' USING ERRCODE = '22023';
  END IF;

  IF p_max_tokens_per_day IS NOT NULL
     AND (p_max_tokens_per_day < 1 OR p_max_tokens_per_day > 20) THEN
    RAISE EXCEPTION 'invalid_max_tokens_per_day' USING ERRCODE = '22023';
  END IF;

  IF p_validity_days IS NOT NULL
     AND (p_validity_days < 1 OR p_validity_days > 3650) THEN
    RAISE EXCEPTION 'invalid_validity_days' USING ERRCODE = '22023';
  END IF;

  UPDATE public.doctors
  SET
    name = trim(p_name),
    code = coalesce(v_code, code),
    is_active = coalesce(p_is_active, is_active),
    minutes_per_patient = coalesce(p_minutes_per_patient, minutes_per_patient),
    max_tokens_per_day = coalesce(p_max_tokens_per_day, max_tokens_per_day),
    updated_at = now()
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_use_clinic_plan_validity IS TRUE THEN
    v_doctor := public.flexza_clear_doctor_access_period(p_doctor_id);
  ELSIF p_use_clinic_plan_validity IS FALSE AND p_validity_days IS NOT NULL THEN
    v_doctor := public.flexza_apply_doctor_access_period(p_doctor_id, p_validity_days);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'is_active', v_doctor.is_active,
    'minutes_per_patient', v_doctor.minutes_per_patient,
    'max_tokens_per_day', v_doctor.max_tokens_per_day,
    'validity_days', v_doctor.validity_days,
    'access_started_at', v_doctor.access_started_at,
    'access_expires_at', v_doctor.access_expires_at
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_doctor_code' USING ERRCODE = '23505';
END;
$$;

-- ---------------------------------------------------------------------------
-- Enforce doctor access on login + patient booking
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_staff_otp(p_mobile text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_mobile);
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_code text;
  v_hash text;
  v_id uuid;
  v_cooldown int;
  v_max_per_hour int;
  v_recent_count int;
  v_last_created timestamptz;
  v_expose_dev boolean;
BEGIN
  v_staff := public.flexza_get_staff_by_mobile(v_mobile);
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_staff.clinic_id;

  IF v_clinic.status = 'pending' THEN
    RAISE EXCEPTION 'clinic_pending_approval' USING ERRCODE = 'P0001';
  END IF;

  v_doctor := public.flexza_primary_doctor_for_clinic(v_clinic.id);
  PERFORM public.flexza_assert_doctor_access(v_doctor.id);

  v_cooldown := public.flexza_setting_int('otp_cooldown_seconds', 30);
  v_max_per_hour := public.flexza_setting_int('otp_max_per_hour', 5);
  v_expose_dev := public.flexza_setting_bool('expose_dev_otp', true);

  SELECT count(*)::int, max(created_at)
  INTO v_recent_count, v_last_created
  FROM public.otp_challenges
  WHERE mobile = v_mobile
    AND purpose = 'staff_login'
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
    AND purpose = 'staff_login'
    AND clinic_id = v_clinic.id
    AND verified_at IS NULL
    AND expires_at > now();

  v_code := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_hash := extensions.crypt(v_code, extensions.gen_salt('bf'));

  INSERT INTO public.otp_challenges (mobile, code_hash, purpose, clinic_id, expires_at)
  VALUES (
    v_mobile,
    v_hash,
    'staff_login',
    v_clinic.id,
    now() + interval '10 minutes'
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'ok', true,
    'challenge_id', v_id,
    'dev_otp', CASE WHEN v_expose_dev THEN v_code ELSE null END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_staff_login(
  p_mobile text,
  p_otp_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_mobile);
  v_otp text := trim(coalesce(p_otp_code, ''));
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_challenge public.otp_challenges;
  v_token text;
BEGIN
  IF length(v_otp) < 4 THEN
    RAISE EXCEPTION 'otp_invalid' USING ERRCODE = 'P0001';
  END IF;

  v_staff := public.flexza_get_staff_by_mobile(v_mobile);
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_staff.clinic_id;

  IF v_clinic.status = 'pending' THEN
    RAISE EXCEPTION 'clinic_pending_approval' USING ERRCODE = 'P0001';
  END IF;

  v_doctor := public.flexza_primary_doctor_for_clinic(v_clinic.id);
  PERFORM public.flexza_assert_doctor_access(v_doctor.id);

  SELECT * INTO v_challenge
  FROM public.otp_challenges
  WHERE mobile = v_mobile
    AND purpose = 'staff_login'
    AND clinic_id = v_clinic.id
    AND verified_at IS NULL
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'otp_not_found_or_expired' USING ERRCODE = 'P0001';
  END IF;

  IF v_challenge.code_hash IS DISTINCT FROM extensions.crypt(v_otp, v_challenge.code_hash) THEN
    RAISE EXCEPTION 'otp_invalid' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.otp_challenges
  SET verified_at = now()
  WHERE id = v_challenge.id;

  DELETE FROM public.staff_sessions
  WHERE staff_id = v_staff.id
     OR expires_at < now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.staff_sessions (staff_id, clinic_id, doctor_id, token, expires_at)
  VALUES (v_staff.id, v_clinic.id, v_doctor.id, v_token, now() + interval '7 days');

  RETURN jsonb_build_object(
    'ok', true,
    'token', v_token,
    'expires_at', (now() + interval '7 days'),
    'staff_name', v_staff.name,
    'staff_mobile', v_staff.mobile,
    'clinic_id', v_clinic.id,
    'clinic_name', v_clinic.name,
    'clinic_status', v_clinic.status,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'plan_expires_at', v_clinic.plan_expires_at,
    'doctor_access_expires_at', v_doctor.access_expires_at
  );
END;
$$;

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
  PERFORM public.flexza_assert_doctor_access(v_doctor.id);

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
  v_today_count int;
BEGIN
  v_mobile := public.flexza_assert_mobile(p_mobile);
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;
  PERFORM public.flexza_assert_doctor_access(v_doctor.id);

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

GRANT EXECUTE ON FUNCTION public.admin_update_doctor(
  text, uuid, text, text, boolean, int, int, int, boolean
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
