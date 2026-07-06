-- Admin email/password auth + doctor code autogen (Step 11+)
-- ONLY flexzahq@gmail.com / Flexzahq#2026 (seeded below)
-- Run in: Supabase Dashboard → SQL Editor → Run

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- Admin accounts + sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_accounts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL,
  password_hash text NOT NULL,
  name          text,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_accounts_email_format CHECK (email = lower(email))
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_accounts_email_key
  ON public.admin_accounts (email);

CREATE TABLE IF NOT EXISTS public.admin_sessions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id   uuid NOT NULL REFERENCES public.admin_accounts (id) ON DELETE CASCADE,
  token      text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_sessions_token_key
  ON public.admin_sessions (token);

CREATE INDEX IF NOT EXISTS admin_sessions_admin_id_idx
  ON public.admin_sessions (admin_id);

ALTER TABLE public.admin_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_accounts FROM anon, authenticated;
REVOKE ALL ON public.admin_sessions FROM anon, authenticated;

DROP TRIGGER IF EXISTS admin_accounts_set_updated_at ON public.admin_accounts;
CREATE TRIGGER admin_accounts_set_updated_at
  BEFORE UPDATE ON public.admin_accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Seed Flexza HQ admin (only allowed login)
INSERT INTO public.admin_accounts (email, password_hash, name)
VALUES (
  'flexzahq@gmail.com',
  extensions.crypt('Flexzahq#2026', extensions.gen_salt('bf')),
  'Flexza HQ'
)
ON CONFLICT (email) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    name = EXCLUDED.name,
    is_active = true,
    updated_at = now();

-- Remove shared key auth
DELETE FROM public.flexza_app_settings WHERE key = 'admin_api_key';

-- ---------------------------------------------------------------------------
-- Auth helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_login(p_email text, p_password text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text := lower(trim(coalesce(p_email, '')));
  v_admin public.admin_accounts;
  v_token text;
BEGIN
  IF v_email IS DISTINCT FROM 'flexzahq@gmail.com' THEN
    RAISE EXCEPTION 'admin_unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_admin
  FROM public.admin_accounts
  WHERE email = v_email
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_unauthorized' USING ERRCODE = '42501';
  END IF;

  IF v_admin.password_hash IS DISTINCT FROM extensions.crypt(p_password, v_admin.password_hash) THEN
    RAISE EXCEPTION 'admin_unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Invalidate old sessions for this admin
  DELETE FROM public.admin_sessions
  WHERE admin_id = v_admin.id
     OR expires_at < now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.admin_sessions (admin_id, token, expires_at)
  VALUES (v_admin.id, v_token, now() + interval '7 days');

  RETURN jsonb_build_object(
    'ok', true,
    'token', v_token,
    'email', v_admin.email,
    'name', v_admin.name,
    'expires_at', (now() + interval '7 days')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_logout(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.admin_sessions WHERE token = p_session_token;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Unique doctor code generator
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_generate_doctor_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_i int;
BEGIN
  FOR v_i IN 1..30 LOOP
    v_code := '';
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);

    IF NOT EXISTS (SELECT 1 FROM public.doctors WHERE code = v_code) THEN
      RETURN v_code;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'doctor_code_generate_failed' USING ERRCODE = 'P0001';
END;
$$;

-- ---------------------------------------------------------------------------
-- Recreate admin RPCs with session token (drop old key-based signatures)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_list_clinics(text);
DROP FUNCTION IF EXISTS public.admin_list_doctors(text, uuid);
DROP FUNCTION IF EXISTS public.admin_create_clinic(text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.admin_add_doctor(text, uuid, text, text);
DROP FUNCTION IF EXISTS public.admin_set_clinic_status(text, uuid, public.clinic_status);
DROP FUNCTION IF EXISTS public.admin_set_clinic_plan(text, uuid, public.clinic_plan);
DROP FUNCTION IF EXISTS public.admin_platform_stats(text);
DROP FUNCTION IF EXISTS public.flexza_assert_admin(text);

CREATE OR REPLACE FUNCTION public.flexza_assert_admin(p_session_token text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
BEGIN
  SELECT s.admin_id INTO v_admin_id
  FROM public.admin_sessions s
  JOIN public.admin_accounts a ON a.id = s.admin_id
  WHERE s.token = p_session_token
    AND s.expires_at > now()
    AND a.is_active = true
    AND a.email = 'flexzahq@gmail.com';

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'admin_unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN v_admin_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_generate_doctor_code(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  RETURN jsonb_build_object(
    'ok', true,
    'doctor_code', public.flexza_generate_doctor_code()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_clinics(p_session_token text)
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

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      c.id,
      c.name,
      c.slug,
      c.subtitle,
      c.status,
      c.plan,
      c.created_at,
      (SELECT count(*)::int FROM public.doctors d WHERE d.clinic_id = c.id) AS doctor_count
    FROM public.clinics c
  ) row;

  RETURN jsonb_build_object('ok', true, 'clinics', v_rows);
END;
$$;

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
    SELECT d.id, d.name, d.code, d.is_active, d.sort_order, d.created_at
    FROM public.doctors d
    WHERE d.clinic_id = p_clinic_id
  ) row;

  RETURN jsonb_build_object('ok', true, 'doctors', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_clinic(
  p_session_token text,
  p_name text,
  p_slug text,
  p_subtitle text DEFAULT NULL,
  p_doctor_name text DEFAULT NULL,
  p_doctor_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug text := lower(trim(p_slug));
  v_clinic public.clinics;
  v_doctor public.doctors;
  v_code text;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_clinic_name' USING ERRCODE = '22023';
  END IF;

  IF v_slug IS NULL OR v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'invalid_clinic_slug' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.clinics (name, slug, subtitle, status, plan)
  VALUES (trim(p_name), v_slug, nullif(trim(coalesce(p_subtitle, '')), ''), 'active', 'free')
  RETURNING * INTO v_clinic;

  IF p_doctor_name IS NOT NULL AND length(trim(p_doctor_name)) > 0 THEN
    v_code := upper(regexp_replace(coalesce(p_doctor_code, ''), '[^A-Za-z0-9]', '', 'g'));
    IF v_code IS NULL OR length(v_code) < 4 THEN
      v_code := public.flexza_generate_doctor_code();
    END IF;

    INSERT INTO public.doctors (clinic_id, name, code)
    VALUES (v_clinic.id, trim(p_doctor_name), v_code)
    RETURNING * INTO v_doctor;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'clinic_id', v_clinic.id,
    'clinic_slug', v_clinic.slug,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_slug_or_code' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_add_doctor(
  p_session_token text,
  p_clinic_id uuid,
  p_doctor_name text,
  p_doctor_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(regexp_replace(coalesce(p_doctor_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_doctor public.doctors;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF NOT EXISTS (SELECT 1 FROM public.clinics WHERE id = p_clinic_id) THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_doctor_name IS NULL OR length(trim(p_doctor_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_doctor_name' USING ERRCODE = '22023';
  END IF;

  IF v_code IS NULL OR length(v_code) < 4 THEN
    v_code := public.flexza_generate_doctor_code();
  END IF;

  INSERT INTO public.doctors (clinic_id, name, code)
  VALUES (p_clinic_id, trim(p_doctor_name), v_code)
  RETURNING * INTO v_doctor;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_doctor_code' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_clinic_status(
  p_session_token text,
  p_clinic_id uuid,
  p_status public.clinic_status
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  UPDATE public.clinics
  SET status = p_status
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object('ok', true, 'clinic_id', v_clinic.id, 'status', v_clinic.status);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_clinic_plan(
  p_session_token text,
  p_clinic_id uuid,
  p_plan public.clinic_plan
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  UPDATE public.clinics
  SET plan = p_plan
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object('ok', true, 'clinic_id', v_clinic.id, 'plan', v_clinic.plan);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_doctor_active(
  p_session_token text,
  p_doctor_id uuid,
  p_is_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  UPDATE public.doctors
  SET is_active = p_is_active
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'is_active', v_doctor.is_active
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_platform_stats(p_session_token text)
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
    'clinics_total', (SELECT count(*)::int FROM public.clinics),
    'clinics_active', (SELECT count(*)::int FROM public.clinics WHERE status = 'active'),
    'doctors_total', (SELECT count(*)::int FROM public.doctors),
    'patients_total', (SELECT count(*)::int FROM public.patients),
    'tokens_today', (
      SELECT count(*)::int
      FROM public.tokens t
      JOIN public.queue_sessions s ON s.id = t.session_id
      WHERE s.session_date = public.flexza_today()
    ),
    'expose_dev_otp', public.flexza_setting_bool('expose_dev_otp', true)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_expose_dev_otp(
  p_session_token text,
  p_enabled boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  INSERT INTO public.flexza_app_settings (key, value)
  VALUES ('expose_dev_otp', to_jsonb(p_enabled))
  ON CONFLICT (key) DO UPDATE
  SET value = to_jsonb(p_enabled), updated_at = now();

  RETURN jsonb_build_object('ok', true, 'expose_dev_otp', p_enabled);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_login(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_logout(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_doctor_code(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_clinics(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_doctors(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_clinic(text, text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_doctor(text, uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_clinic_status(text, uuid, public.clinic_status) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_clinic_plan(text, uuid, public.clinic_plan) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_doctor_active(text, uuid, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_platform_stats(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_expose_dev_otp(text, boolean) TO anon, authenticated;
