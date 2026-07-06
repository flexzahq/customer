-- Step 1–4 polish: clinic profile for patient app, offer apply, staff notifications
-- Run in: Supabase Dashboard → SQL Editor → Run

-- ---------------------------------------------------------------------------
-- Richer resolve_doctor_code (Timing / About pages)
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
    'evening_end', v_clinic.evening_end
  );
EXCEPTION
  WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

-- ---------------------------------------------------------------------------
-- Apply offer code to a clinic (admin)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_apply_offer(
  p_session_token text,
  p_clinic_id uuid,
  p_offer_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := upper(trim(coalesce(p_offer_code, '')));
  v_offer public.offer_codes;
  v_plan public.plans;
  v_clinic public.clinics;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF v_code IS NULL OR length(v_code) < 3 THEN
    RAISE EXCEPTION 'invalid_offer_code' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_offer
  FROM public.offer_codes
  WHERE code = v_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_offer.is_active THEN
    RAISE EXCEPTION 'offer_inactive' USING ERRCODE = 'P0001';
  END IF;

  IF v_offer.starts_at IS NOT NULL AND v_offer.starts_at > now() THEN
    RAISE EXCEPTION 'offer_not_started' USING ERRCODE = 'P0001';
  END IF;

  IF v_offer.ends_at IS NOT NULL AND v_offer.ends_at < now() THEN
    RAISE EXCEPTION 'offer_expired' USING ERRCODE = 'P0001';
  END IF;

  IF v_offer.max_redemptions IS NOT NULL
     AND v_offer.redemption_count >= v_offer.max_redemptions THEN
    RAISE EXCEPTION 'offer_exhausted' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_offer.plan_id IS NOT NULL THEN
    SELECT * INTO v_plan FROM public.plans WHERE id = v_offer.plan_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'plan_not_found' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.clinics
    SET
      plan_id = v_plan.id,
      plan = CASE
        WHEN v_plan.code = 'free' THEN 'free'::public.clinic_plan
        WHEN v_plan.code = 'starter' THEN 'starter'::public.clinic_plan
        WHEN v_plan.code = 'pro' THEN 'pro'::public.clinic_plan
        ELSE plan
      END
    WHERE id = p_clinic_id;
  END IF;

  UPDATE public.offer_codes
  SET redemption_count = redemption_count + 1
  WHERE id = v_offer.id
  RETURNING * INTO v_offer;

  RETURN jsonb_build_object(
    'ok', true,
    'offer_code', v_offer.code,
    'redemption_count', v_offer.redemption_count,
    'plan_id', v_offer.plan_id,
    'plan_code', v_plan.code,
    'plan_name', v_plan.name
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Staff-visible notifications (sent only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_staff_notifications(p_doctor_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doctor public.doctors;
  v_clinic public.clinics;
  v_rows jsonb;
BEGIN
  v_doctor := public.flexza_get_doctor_by_code(p_doctor_code);
  SELECT * INTO v_clinic FROM public.clinics WHERE id = v_doctor.clinic_id;

  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.sent_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT n.id, n.title, n.body, n.audience, n.sent_at, n.created_at
    FROM public.admin_notifications n
    WHERE n.status = 'sent'
      AND (
        n.audience = 'all'
        OR (n.audience = 'active_clinics' AND v_clinic.status = 'active')
        OR (n.audience = 'clinic' AND n.clinic_id = v_clinic.id)
      )
    ORDER BY n.sent_at DESC NULLS LAST
    LIMIT 50
  ) row;

  RETURN jsonb_build_object('ok', true, 'notifications', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_apply_offer(text, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_staff_notifications(text) TO anon, authenticated;
