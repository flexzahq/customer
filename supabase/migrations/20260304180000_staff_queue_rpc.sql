-- Staff queue board (Step 8)
-- Run in: Supabase Dashboard → SQL Editor → Run

CREATE OR REPLACE FUNCTION public.get_staff_queue(p_doctor_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_clinic public.clinics;
  v_session public.queue_sessions;
  v_serving jsonb;
  v_waiting jsonb;
  v_skipped jsonb;
  v_completed jsonb;
  v_total_today int;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);

  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;

  SELECT * INTO v_session
  FROM public.queue_sessions
  WHERE doctor_id = v_doctor.id
    AND session_date = public.flexza_today();

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'doctor_code', v_doctor.code,
      'doctor_name', v_doctor.name,
      'clinic_name', v_clinic.name,
      'clinic_subtitle', v_clinic.subtitle,
      'session_id', null,
      'session_status', null,
      'serving', null,
      'waiting', '[]'::jsonb,
      'skipped', '[]'::jsonb,
      'completed', '[]'::jsonb,
      'waiting_count', 0,
      'total_today', 0
    );
  END IF;

  SELECT count(*)::int INTO v_total_today
  FROM public.tokens
  WHERE session_id = v_session.id;

  SELECT to_jsonb(row) INTO v_serving
  FROM (
    SELECT
      t.id,
      t.number,
      t.status,
      t.booked_at,
      p.name AS patient_name,
      p.mobile AS patient_mobile
    FROM public.tokens t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE t.session_id = v_session.id
      AND t.status = 'serving'
    LIMIT 1
  ) row;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.number), '[]'::jsonb)
  INTO v_waiting
  FROM (
    SELECT
      t.id,
      t.number,
      t.status,
      t.booked_at,
      p.name AS patient_name,
      p.mobile AS patient_mobile
    FROM public.tokens t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE t.session_id = v_session.id
      AND t.status = 'waiting'
    ORDER BY t.number
  ) row;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.number), '[]'::jsonb)
  INTO v_skipped
  FROM (
    SELECT
      t.id,
      t.number,
      t.status,
      t.booked_at,
      p.name AS patient_name,
      p.mobile AS patient_mobile
    FROM public.tokens t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE t.session_id = v_session.id
      AND t.status = 'skipped'
    ORDER BY t.number
  ) row;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.number DESC), '[]'::jsonb)
  INTO v_completed
  FROM (
    SELECT
      t.id,
      t.number,
      t.status,
      t.booked_at,
      t.completed_at,
      p.name AS patient_name,
      p.mobile AS patient_mobile
    FROM public.tokens t
    JOIN public.patients p ON p.id = t.patient_id
    WHERE t.session_id = v_session.id
      AND t.status = 'completed'
    ORDER BY t.number DESC
    LIMIT 50
  ) row;

  RETURN jsonb_build_object(
    'ok', true,
    'doctor_code', v_doctor.code,
    'doctor_name', v_doctor.name,
    'clinic_name', v_clinic.name,
    'clinic_subtitle', v_clinic.subtitle,
    'session_id', v_session.id,
    'session_status', v_session.status,
    'serving', v_serving,
    'waiting', v_waiting,
    'skipped', v_skipped,
    'completed', v_completed,
    'waiting_count', jsonb_array_length(v_waiting),
    'total_today', v_total_today
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_queue(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_today_session(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_session_status(uuid, public.session_status) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_token(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.skip_token(uuid) TO anon, authenticated;
