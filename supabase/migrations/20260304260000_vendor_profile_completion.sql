-- Vendor clinic profile completion (editable by staff + onboarding after register)
-- Run after 20260304250000_vendor_registration_staff_patients.sql

ALTER TABLE public.clinics
  ADD COLUMN IF NOT EXISTS profile_completed_at timestamptz;

COMMENT ON COLUMN public.clinics.profile_completed_at IS
  'Set when vendor fills required patient-facing profile fields';

-- ---------------------------------------------------------------------------
-- Staff session helper
-- ---------------------------------------------------------------------------
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

  RETURN v_session;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_parse_time_or_null(p_value text)
RETURNS time
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text := trim(coalesce(p_value, ''));
BEGIN
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF v ~ '^\d{1,2}:\d{2}$' THEN
    RETURN (v || ':00')::time;
  END IF;
  IF v ~ '^\d{1,2}:\d{2}:\d{2}$' THEN
    RETURN v::time;
  END IF;
  RAISE EXCEPTION 'invalid_time' USING ERRCODE = '22023';
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_profile_is_complete(p_clinic public.clinics)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_clinic.phone IS NULL OR length(trim(p_clinic.phone)) < 10 THEN
    RETURN false;
  END IF;

  IF p_clinic.address IS NULL OR length(trim(p_clinic.address)) < 5 THEN
    RETURN false;
  END IF;

  IF p_clinic.about IS NULL OR length(trim(p_clinic.about)) < 20 THEN
    RETURN false;
  END IF;

  IF NOT (
    (p_clinic.morning_start IS NOT NULL AND p_clinic.morning_end IS NOT NULL)
    OR (p_clinic.evening_start IS NOT NULL AND p_clinic.evening_end IS NOT NULL)
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_touch_profile_completed(p_clinic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
BEGIN
  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF public.flexza_profile_is_complete(v_clinic) THEN
    UPDATE public.clinics
    SET profile_completed_at = coalesce(profile_completed_at, now()),
        updated_at = now()
    WHERE id = p_clinic_id;
  ELSE
    UPDATE public.clinics
    SET profile_completed_at = NULL,
        updated_at = now()
    WHERE id = p_clinic_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_clinic_profile_json(
  p_clinic public.clinics,
  p_doctor public.doctors,
  p_staff public.staff_users
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'ok', true,
    'clinic_id', p_clinic.id,
    'clinic_name', p_clinic.name,
    'clinic_slug', p_clinic.slug,
    'clinic_status', p_clinic.status,
    'clinic_subtitle', p_clinic.subtitle,
    'phone', p_clinic.phone,
    'email', p_clinic.email,
    'address', p_clinic.address,
    'about', p_clinic.about,
    'morning_start', p_clinic.morning_start,
    'morning_end', p_clinic.morning_end,
    'evening_start', p_clinic.evening_start,
    'evening_end', p_clinic.evening_end,
    'profile_complete', public.flexza_profile_is_complete(p_clinic),
    'profile_completed_at', p_clinic.profile_completed_at,
    'doctor_id', p_doctor.id,
    'doctor_code', p_doctor.code,
    'doctor_name', p_doctor.name,
    'staff_name', p_staff.name,
    'staff_mobile', p_staff.mobile
  );
$$;

-- ---------------------------------------------------------------------------
-- Authenticated vendor profile (active or pending clinic via session)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vendor_get_profile(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);

  SELECT * INTO v_staff FROM public.staff_users WHERE id = v_session.staff_id;
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_session.clinic_id;
  SELECT * INTO v_doctor FROM public.doctors WHERE id = v_session.doctor_id;

  RETURN public.flexza_clinic_profile_json(v_clinic, v_doctor, v_staff);
END;
$$;

CREATE OR REPLACE FUNCTION public.vendor_update_clinic_profile(
  p_session_token text,
  p_subtitle text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_about text DEFAULT NULL,
  p_morning_start text DEFAULT NULL,
  p_morning_end text DEFAULT NULL,
  p_evening_start text DEFAULT NULL,
  p_evening_end text DEFAULT NULL,
  p_doctor_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_phone text;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);

  SELECT * INTO v_staff FROM public.staff_users WHERE id = v_session.staff_id;
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_session.clinic_id;
  SELECT * INTO v_doctor FROM public.doctors WHERE id = v_session.doctor_id;

  IF v_clinic.status = 'disabled' THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

  v_phone := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
  IF v_phone IS NOT NULL AND length(v_phone) <> 10 THEN
    RAISE EXCEPTION 'invalid_phone' USING ERRCODE = '22023';
  END IF;

  UPDATE public.clinics
  SET
    subtitle = nullif(trim(coalesce(p_subtitle, '')), ''),
    phone = v_phone,
    email = nullif(lower(trim(coalesce(p_email, ''))), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    about = nullif(trim(coalesce(p_about, '')), ''),
    morning_start = public.flexza_parse_time_or_null(p_morning_start),
    morning_end = public.flexza_parse_time_or_null(p_morning_end),
    evening_start = public.flexza_parse_time_or_null(p_evening_start),
    evening_end = public.flexza_parse_time_or_null(p_evening_end),
    updated_at = now()
  WHERE id = v_clinic.id
  RETURNING * INTO v_clinic;

  IF p_doctor_name IS NOT NULL AND length(trim(p_doctor_name)) >= 2 THEN
    UPDATE public.doctors
    SET name = trim(p_doctor_name), updated_at = now()
    WHERE id = v_doctor.id
    RETURNING * INTO v_doctor;
  END IF;

  PERFORM public.flexza_touch_profile_completed(v_clinic.id);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_clinic.id;

  RETURN public.flexza_clinic_profile_json(v_clinic, v_doctor, v_staff);
END;
$$;

CREATE OR REPLACE FUNCTION public.vendor_update_staff_profile(
  p_session_token text,
  p_staff_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);

  IF p_staff_name IS NULL OR length(trim(p_staff_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_staff_name' USING ERRCODE = '22023';
  END IF;

  UPDATE public.staff_users
  SET name = trim(p_staff_name), updated_at = now()
  WHERE id = v_session.staff_id
  RETURNING * INTO v_staff;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_session.clinic_id;
  SELECT * INTO v_doctor FROM public.doctors WHERE id = v_session.doctor_id;

  RETURN public.flexza_clinic_profile_json(v_clinic, v_doctor, v_staff);
END;
$$;

-- ---------------------------------------------------------------------------
-- Post-registration onboarding (no login yet — clinic pending)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vendor_onboarding_get_profile(
  p_clinic_id uuid,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_mobile);
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
BEGIN
  SELECT su.* INTO v_staff
  FROM public.staff_users su
  WHERE su.clinic_id = p_clinic_id
    AND su.mobile = v_mobile
    AND su.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;
  v_doctor := public.flexza_primary_doctor_for_clinic(p_clinic_id);

  RETURN public.flexza_clinic_profile_json(v_clinic, v_doctor, v_staff);
END;
$$;

CREATE OR REPLACE FUNCTION public.vendor_onboarding_update_profile(
  p_clinic_id uuid,
  p_mobile text,
  p_subtitle text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_about text DEFAULT NULL,
  p_morning_start text DEFAULT NULL,
  p_morning_end text DEFAULT NULL,
  p_evening_start text DEFAULT NULL,
  p_evening_end text DEFAULT NULL,
  p_doctor_name text DEFAULT NULL
)
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
  v_phone text;
BEGIN
  SELECT su.* INTO v_staff
  FROM public.staff_users su
  WHERE su.clinic_id = p_clinic_id
    AND su.mobile = v_mobile
    AND su.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;

  IF v_clinic.status NOT IN ('pending', 'active') THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

  v_doctor := public.flexza_primary_doctor_for_clinic(p_clinic_id);

  v_phone := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
  IF v_phone IS NOT NULL AND length(v_phone) <> 10 THEN
    RAISE EXCEPTION 'invalid_phone' USING ERRCODE = '22023';
  END IF;

  UPDATE public.clinics
  SET
    subtitle = nullif(trim(coalesce(p_subtitle, '')), ''),
    phone = v_phone,
    email = nullif(lower(trim(coalesce(p_email, ''))), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    about = nullif(trim(coalesce(p_about, '')), ''),
    morning_start = public.flexza_parse_time_or_null(p_morning_start),
    morning_end = public.flexza_parse_time_or_null(p_morning_end),
    evening_start = public.flexza_parse_time_or_null(p_evening_start),
    evening_end = public.flexza_parse_time_or_null(p_evening_end),
    updated_at = now()
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF p_doctor_name IS NOT NULL AND length(trim(p_doctor_name)) >= 2 THEN
    UPDATE public.doctors
    SET name = trim(p_doctor_name), updated_at = now()
    WHERE id = v_doctor.id
    RETURNING * INTO v_doctor;
  END IF;

  PERFORM public.flexza_touch_profile_completed(v_clinic.id);
  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;

  RETURN public.flexza_clinic_profile_json(v_clinic, v_doctor, v_staff);
END;
$$;

-- Extend staff session payloads with profile_complete
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

  IF v_clinic.status <> 'active' THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

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

  UPDATE public.otp_challenges SET verified_at = now() WHERE id = v_challenge.id;

  v_doctor := public.flexza_primary_doctor_for_clinic(v_clinic.id);

  DELETE FROM public.staff_sessions
  WHERE staff_id = v_staff.id OR expires_at < now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.staff_sessions (staff_id, clinic_id, doctor_id, token, expires_at)
  VALUES (v_staff.id, v_clinic.id, v_doctor.id, v_token, now() + interval '7 days');

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_clinic.id;

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
    'profile_complete', public.flexza_profile_is_complete(v_clinic)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_get_session(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.staff_sessions;
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
BEGIN
  v_session := public.flexza_assert_staff_session(p_session_token);

  SELECT * INTO v_staff FROM public.staff_users WHERE id = v_session.staff_id;
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_session.clinic_id;
  SELECT * INTO v_doctor FROM public.doctors WHERE id = v_session.doctor_id;

  RETURN jsonb_build_object(
    'ok', true,
    'staff_name', v_staff.name,
    'staff_mobile', v_staff.mobile,
    'clinic_id', v_clinic.id,
    'clinic_name', v_clinic.name,
    'clinic_status', v_clinic.status,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'profile_complete', public.flexza_profile_is_complete(v_clinic)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.vendor_get_profile(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_update_clinic_profile(text, text, text, text, text, text, text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_update_staff_profile(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_onboarding_get_profile(uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_onboarding_update_profile(uuid, text, text, text, text, text, text, text, text, text, text, text) TO anon, authenticated;

-- Include profile status in registration lookup
CREATE OR REPLACE FUNCTION public.vendor_registration_status(p_mobile text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_mobile);
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
BEGIN
  SELECT su.* INTO v_staff
  FROM public.staff_users su
  WHERE su.mobile = v_mobile
    AND su.is_active = true
  ORDER BY su.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'found', false);
  END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_staff.clinic_id;
  v_doctor := public.flexza_primary_doctor_for_clinic(v_clinic.id);

  RETURN jsonb_build_object(
    'ok', true,
    'found', true,
    'clinic_id', v_clinic.id,
    'clinic_name', v_clinic.name,
    'clinic_status', v_clinic.status,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'owner_name', v_staff.name,
    'profile_complete', public.flexza_profile_is_complete(v_clinic)
  );
END;
$$;
