-- Admin RPCs (Step 11)
-- Run in: Supabase Dashboard → SQL Editor → Run
-- Auth: shared admin_api_key in flexza_app_settings (change in production)

INSERT INTO public.flexza_app_settings (key, value)
VALUES ('admin_api_key', '"flexza-admin-dev"'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.flexza_assert_admin(p_admin_key text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected text;
BEGIN
  SELECT trim(both '"' from value::text) INTO v_expected
  FROM public.flexza_app_settings
  WHERE key = 'admin_api_key';

  IF v_expected IS NULL OR v_expected = '' OR p_admin_key IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'admin_unauthorized' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_clinics(p_admin_key text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  PERFORM public.flexza_assert_admin(p_admin_key);

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
      (
        SELECT count(*)::int FROM public.doctors d WHERE d.clinic_id = c.id
      ) AS doctor_count
    FROM public.clinics c
  ) row;

  RETURN jsonb_build_object('ok', true, 'clinics', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_doctors(
  p_admin_key text,
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
  PERFORM public.flexza_assert_admin(p_admin_key);

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
  p_admin_key text,
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
  PERFORM public.flexza_assert_admin(p_admin_key);

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
    IF v_code IS NULL OR length(v_code) < 4 OR length(v_code) > 12 THEN
      RAISE EXCEPTION 'invalid_doctor_code' USING ERRCODE = '22023';
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
  p_admin_key text,
  p_clinic_id uuid,
  p_doctor_name text,
  p_doctor_code text
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
  PERFORM public.flexza_assert_admin(p_admin_key);

  IF NOT EXISTS (SELECT 1 FROM public.clinics WHERE id = p_clinic_id) THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_doctor_name IS NULL OR length(trim(p_doctor_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_doctor_name' USING ERRCODE = '22023';
  END IF;

  IF length(v_code) < 4 OR length(v_code) > 12 THEN
    RAISE EXCEPTION 'invalid_doctor_code' USING ERRCODE = '22023';
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
  p_admin_key text,
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
  PERFORM public.flexza_assert_admin(p_admin_key);

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
  p_admin_key text,
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
  PERFORM public.flexza_assert_admin(p_admin_key);

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

CREATE OR REPLACE FUNCTION public.admin_platform_stats(p_admin_key text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_admin_key);

  RETURN jsonb_build_object(
    'ok', true,
    'clinics_total', (SELECT count(*)::int FROM public.clinics),
    'clinics_active', (SELECT count(*)::int FROM public.clinics WHERE status = 'active'),
    'doctors_total', (SELECT count(*)::int FROM public.doctors),
    'tokens_today', (
      SELECT count(*)::int
      FROM public.tokens t
      JOIN public.queue_sessions s ON s.id = t.session_id
      WHERE s.session_date = public.flexza_today()
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_clinics(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_doctors(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_clinic(text, text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_doctor(text, uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_clinic_status(text, uuid, public.clinic_status) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_clinic_plan(text, uuid, public.clinic_plan) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_platform_stats(text) TO anon, authenticated;
