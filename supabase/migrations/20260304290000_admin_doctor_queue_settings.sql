-- Admin: per-doctor queue settings (minutes per patient, max tokens/day)
-- Like clinic timing — set per doctor in admin clinic detail, not bulk for all.

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
      d.max_tokens_per_day
    FROM public.doctors d
    WHERE d.clinic_id = p_clinic_id
  ) row;

  RETURN jsonb_build_object('ok', true, 'doctors', v_rows);
END;
$$;

DROP FUNCTION IF EXISTS public.admin_update_doctor(text, uuid, text, text, boolean);

CREATE OR REPLACE FUNCTION public.admin_update_doctor(
  p_session_token text,
  p_doctor_id uuid,
  p_name text,
  p_code text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL,
  p_minutes_per_patient int DEFAULT NULL,
  p_max_tokens_per_day int DEFAULT NULL
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

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_id', v_doctor.id,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'is_active', v_doctor.is_active,
    'minutes_per_patient', v_doctor.minutes_per_patient,
    'max_tokens_per_day', v_doctor.max_tokens_per_day
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_doctor_code' USING ERRCODE = '23505';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_doctors(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_doctor(text, uuid, text, text, boolean, int, int) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
