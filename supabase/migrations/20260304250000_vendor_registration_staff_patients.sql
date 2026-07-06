-- Vendor: self-registration, staff OTP login, patient visit history
-- Run after prior Flexza migrations

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- pending = self-registered, awaiting admin approval
DO $$ BEGIN
  ALTER TYPE public.clinic_status ADD VALUE IF NOT EXISTS 'pending';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Staff sessions (vendor portal)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_sessions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id     uuid NOT NULL REFERENCES public.staff_users (id) ON DELETE CASCADE,
  clinic_id    uuid NOT NULL REFERENCES public.clinics (id) ON DELETE CASCADE,
  doctor_id    uuid NOT NULL REFERENCES public.doctors (id) ON DELETE CASCADE,
  token        text NOT NULL,
  expires_at   timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS staff_sessions_token_key
  ON public.staff_sessions (token);
CREATE INDEX IF NOT EXISTS staff_sessions_staff_id_idx
  ON public.staff_sessions (staff_id);

ALTER TABLE public.staff_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.staff_sessions FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_slugify(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT trim(both '-' from regexp_replace(
    lower(regexp_replace(coalesce(p_text, ''), '[^a-zA-Z0-9]+', '-', 'g')),
    '-+', '-', 'g'
  ));
$$;

CREATE OR REPLACE FUNCTION public.flexza_unique_clinic_slug(p_base text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_base text := public.flexza_slugify(p_base);
  v_slug text;
  v_i int := 0;
BEGIN
  IF v_base IS NULL OR length(v_base) < 2 THEN
    v_base := 'clinic';
  END IF;
  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM public.clinics WHERE slug = v_slug) LOOP
    v_i := v_i + 1;
    v_slug := v_base || '-' || v_i::text;
  END LOOP;
  RETURN v_slug;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_get_staff_by_mobile(p_mobile text)
RETURNS public.staff_users
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_mobile);
  v_staff public.staff_users;
BEGIN
  SELECT su.* INTO v_staff
  FROM public.staff_users su
  JOIN public.clinics c ON c.id = su.clinic_id
  WHERE su.mobile = v_mobile
    AND su.is_active = true
    AND c.status IN ('active', 'pending')
  ORDER BY su.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'staff_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_staff;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_primary_doctor_for_clinic(p_clinic_id uuid)
RETURNS public.doctors
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  SELECT d.* INTO v_doctor
  FROM public.doctors d
  WHERE d.clinic_id = p_clinic_id
    AND d.is_active = true
  ORDER BY d.sort_order, d.created_at
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_doctor;
END;
$$;

-- ---------------------------------------------------------------------------
-- Self clinic registration (status = pending until admin activates)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vendor_register_clinic(
  p_clinic_name text,
  p_owner_name text,
  p_owner_mobile text,
  p_doctor_name text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text := public.flexza_assert_mobile(p_owner_mobile);
  v_clinic_name text := trim(coalesce(p_clinic_name, ''));
  v_owner_name text := trim(coalesce(p_owner_name, ''));
  v_doctor_name text := trim(coalesce(p_doctor_name, p_owner_name, ''));
  v_slug text;
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_staff public.staff_users;
  v_code text;
BEGIN
  IF length(v_clinic_name) < 2 THEN
    RAISE EXCEPTION 'invalid_clinic_name' USING ERRCODE = '22023';
  END IF;

  IF length(v_owner_name) < 2 THEN
    RAISE EXCEPTION 'invalid_owner_name' USING ERRCODE = '22023';
  END IF;

  IF length(v_doctor_name) < 2 THEN
    RAISE EXCEPTION 'invalid_doctor_name' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.staff_users su
    JOIN public.clinics c ON c.id = su.clinic_id
    WHERE su.mobile = v_mobile
      AND c.status IN ('active', 'pending')
  ) THEN
    RAISE EXCEPTION 'mobile_already_registered' USING ERRCODE = '23505';
  END IF;

  v_slug := public.flexza_unique_clinic_slug(v_clinic_name);
  v_code := public.flexza_generate_doctor_code();

  INSERT INTO public.clinics (
    name, slug, subtitle, status, plan, email, address
  )
  VALUES (
    v_clinic_name,
    v_slug,
    nullif(trim(coalesce(p_doctor_name, '')), ''),
    'pending',
    'free',
    nullif(lower(trim(coalesce(p_email, ''))), ''),
    nullif(trim(coalesce(p_address, '')), '')
  )
  RETURNING * INTO v_clinic;

  INSERT INTO public.doctors (clinic_id, name, code)
  VALUES (v_clinic.id, v_doctor_name, v_code)
  RETURNING * INTO v_doctor;

  INSERT INTO public.staff_users (clinic_id, mobile, name, role)
  VALUES (v_clinic.id, v_mobile, v_owner_name, 'owner')
  RETURNING * INTO v_staff;

  RETURN jsonb_build_object(
    'ok', true,
    'clinic_id', v_clinic.id,
    'clinic_name', v_clinic.name,
    'clinic_status', v_clinic.status,
    'clinic_slug', v_clinic.slug,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'owner_mobile', v_staff.mobile
  );
END;
$$;

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
    'owner_name', v_staff.name
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Staff OTP login
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

  IF v_clinic.status <> 'active' THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

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

  UPDATE public.otp_challenges
  SET verified_at = now()
  WHERE id = v_challenge.id;

  v_doctor := public.flexza_primary_doctor_for_clinic(v_clinic.id);

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
    'doctor_name', v_doctor.name
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
  v_token text := trim(coalesce(p_session_token, ''));
  v_session public.staff_sessions;
  v_staff public.staff_users;
  v_clinic public.clinics;
  v_doctor public.doctors;
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
    'doctor_name', v_doctor.name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_logout(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.staff_sessions
  WHERE token = trim(coalesce(p_session_token, ''));
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Patients list + visit history (per doctor)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_doctor_patients(p_doctor_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_rows jsonb;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.last_visit_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id AS patient_id,
      p.mobile,
      coalesce(p.name, 'Patient') AS name,
      count(t.id)::int AS visit_count,
      max(t.booked_at) AS last_visit_at
    FROM public.tokens t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE t.doctor_id = v_doctor.id
    GROUP BY p.id, p.mobile, p.name
  ) row;

  RETURN jsonb_build_object('ok', true, 'patients', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_visit_history(
  p_doctor_code text,
  p_patient_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_patient public.patients;
  v_rows jsonb;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_patient FROM public.patients WHERE id = p_patient_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'patient_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.booked_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      t.id AS token_id,
      t.number,
      t.status,
      t.booked_at,
      t.completed_at,
      qs.session_date,
      d.name AS doctor_name
    FROM public.tokens t
    JOIN public.queue_sessions qs ON qs.id = t.session_id
    JOIN public.doctors d ON d.id = t.doctor_id
    WHERE t.doctor_id = v_doctor.id
      AND t.patient_id = p_patient_id
  ) row;

  RETURN jsonb_build_object(
    'ok', true,
    'patient_id', v_patient.id,
    'patient_name', v_patient.name,
    'patient_mobile', v_patient.mobile,
    'visits', v_rows
  );
END;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION public.vendor_register_clinic(text, text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.vendor_registration_status(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_staff_otp(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_staff_login(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_get_session(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.staff_logout(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_doctor_patients(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_visit_history(text, uuid) TO anon, authenticated;
