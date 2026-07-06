-- Admin clinic/doctor edit (Phase 1 full manage foundation)
-- Run in: Supabase Dashboard → SQL Editor → Run

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
      c.phone,
      c.email,
      c.address,
      c.about,
      c.morning_start,
      c.morning_end,
      c.evening_start,
      c.evening_end,
      c.created_at,
      c.updated_at,
      (SELECT count(*)::int FROM public.doctors d WHERE d.clinic_id = c.id) AS doctor_count
    FROM public.clinics c
  ) row;

  RETURN jsonb_build_object('ok', true, 'clinics', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_clinic(
  p_session_token text,
  p_clinic_id uuid,
  p_name text,
  p_slug text,
  p_subtitle text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_about text DEFAULT NULL,
  p_morning_start time DEFAULT NULL,
  p_morning_end time DEFAULT NULL,
  p_evening_start time DEFAULT NULL,
  p_evening_end time DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug text := lower(trim(p_slug));
  v_clinic public.clinics;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_clinic_name' USING ERRCODE = '22023';
  END IF;

  IF v_slug IS NULL OR v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'invalid_clinic_slug' USING ERRCODE = '22023';
  END IF;

  UPDATE public.clinics
  SET
    name = trim(p_name),
    slug = v_slug,
    subtitle = nullif(trim(coalesce(p_subtitle, '')), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    email = nullif(trim(coalesce(p_email, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    about = nullif(trim(coalesce(p_about, '')), ''),
    morning_start = p_morning_start,
    morning_end = p_morning_end,
    evening_start = p_evening_start,
    evening_end = p_evening_end
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object('ok', true, 'clinic_id', v_clinic.id, 'slug', v_clinic.slug);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_slug_or_code' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_doctor(
  p_session_token text,
  p_doctor_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
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

  UPDATE public.doctors
  SET
    name = trim(p_name),
    code = coalesce(v_code, code),
    is_active = coalesce(p_is_active, is_active)
  WHERE id = p_doctor_id
  RETURNING * INTO v_doctor;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'doctor_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'is_active', v_doctor.is_active
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_doctor_code' USING ERRCODE = '23505';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_clinic(text, uuid, text, text, text, text, text, text, text, time, time, time, time) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_doctor(text, uuid, text, text, boolean) TO anon, authenticated;
