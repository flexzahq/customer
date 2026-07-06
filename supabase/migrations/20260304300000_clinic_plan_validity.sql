-- Clinic plan validity: each plan defines access days; clinics expire after that period.
-- Admin plan change resets validity. Vendor + patient booking blocked when expired.

ALTER TABLE public.plans
  ADD COLUMN IF NOT EXISTS validity_days int NOT NULL DEFAULT 30;

ALTER TABLE public.clinics
  ADD COLUMN IF NOT EXISTS plan_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS plan_expires_at timestamptz;

COMMENT ON COLUMN public.plans.validity_days IS 'Vendor/patient access duration when plan is assigned to a clinic';
COMMENT ON COLUMN public.clinics.plan_started_at IS 'Start of current plan validity window';
COMMENT ON COLUMN public.clinics.plan_expires_at IS 'End of current plan validity window';

UPDATE public.plans SET validity_days = 30 WHERE code = 'free';
UPDATE public.plans SET validity_days = 365 WHERE code IN ('starter', 'pro');
UPDATE public.plans SET validity_days = 30 WHERE validity_days IS NULL OR validity_days < 1;

UPDATE public.clinics c
SET plan_id = p.id
FROM public.plans p
WHERE c.plan_id IS NULL
  AND p.code = c.plan::text;

UPDATE public.clinics c
SET plan_id = p.id
FROM public.plans p
WHERE c.plan_id IS NULL
  AND p.code = 'free';

UPDATE public.clinics c
SET
  plan_started_at = coalesce(c.plan_started_at, c.created_at),
  plan_expires_at = coalesce(
    c.plan_expires_at,
    c.created_at + (coalesce(p.validity_days, 30) || ' days')::interval
  )
FROM public.plans p
WHERE c.plan_id = p.id
  AND c.plan_expires_at IS NULL;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.flexza_clinic_plan_row(p_clinic public.clinics)
RETURNS public.plans
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.plans;
BEGIN
  IF p_clinic.plan_id IS NOT NULL THEN
    SELECT * INTO v_plan FROM public.plans WHERE id = p_clinic.plan_id;
    IF FOUND THEN
      RETURN v_plan;
    END IF;
  END IF;

  SELECT * INTO v_plan FROM public.plans WHERE code = p_clinic.plan::text;
  IF FOUND THEN
    RETURN v_plan;
  END IF;

  SELECT * INTO v_plan FROM public.plans WHERE code = 'free';
  RETURN v_plan;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_apply_clinic_plan_period(p_clinic_id uuid)
RETURNS public.clinics
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
  v_plan public.plans;
BEGIN
  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_plan := public.flexza_clinic_plan_row(v_clinic);

  UPDATE public.clinics
  SET
    plan_id = v_plan.id,
    plan = CASE
      WHEN v_plan.code = 'free' THEN 'free'::public.clinic_plan
      WHEN v_plan.code = 'starter' THEN 'starter'::public.clinic_plan
      WHEN v_plan.code = 'pro' THEN 'pro'::public.clinic_plan
      ELSE plan
    END,
    plan_started_at = now(),
    plan_expires_at = now() + make_interval(days => greatest(coalesce(v_plan.validity_days, 30), 1))
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  RETURN v_clinic;
END;
$$;

CREATE OR REPLACE FUNCTION public.flexza_assert_clinic_subscription(p_clinic_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clinic public.clinics;
BEGIN
  SELECT * INTO v_clinic FROM public.clinics WHERE id = p_clinic_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_clinic.status = 'pending' THEN
    RAISE EXCEPTION 'clinic_pending_approval' USING ERRCODE = 'P0001';
  END IF;

  IF v_clinic.status <> 'active' THEN
    RAISE EXCEPTION 'clinic_disabled' USING ERRCODE = 'P0001';
  END IF;

  IF v_clinic.plan_expires_at IS NOT NULL AND v_clinic.plan_expires_at <= now() THEN
    RAISE EXCEPTION 'clinic_plan_expired' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Staff session — block expired plans
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

  PERFORM public.flexza_assert_clinic_subscription(v_session.clinic_id);

  RETURN v_session;
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin plan CRUD — validity_days
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_upsert_plan(text, uuid, text, text, text, numeric, numeric, text, jsonb, boolean, int);

CREATE OR REPLACE FUNCTION public.admin_upsert_plan(
  p_session_token text,
  p_id uuid DEFAULT NULL,
  p_code text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_price_monthly numeric DEFAULT 0,
  p_price_yearly numeric DEFAULT 0,
  p_currency text DEFAULT 'INR',
  p_features jsonb DEFAULT '[]'::jsonb,
  p_is_active boolean DEFAULT true,
  p_sort_order int DEFAULT 0,
  p_validity_days int DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text := lower(trim(coalesce(p_code, '')));
  v_plan public.plans;
  v_days int := greatest(coalesce(p_validity_days, 30), 1);
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_plan_name' USING ERRCODE = '22023';
  END IF;

  IF v_code IS NULL OR v_code !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'invalid_plan_code' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.plans (
      code, name, description, price_monthly, price_yearly, currency,
      features, is_active, sort_order, validity_days
    ) VALUES (
      v_code, trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
      coalesce(p_price_monthly, 0), coalesce(p_price_yearly, 0),
      coalesce(nullif(trim(p_currency), ''), 'INR'),
      coalesce(p_features, '[]'::jsonb), coalesce(p_is_active, true),
      coalesce(p_sort_order, 0), v_days
    )
    RETURNING * INTO v_plan;
  ELSE
    UPDATE public.plans
    SET
      code = v_code,
      name = trim(p_name),
      description = nullif(trim(coalesce(p_description, '')), ''),
      price_monthly = coalesce(p_price_monthly, 0),
      price_yearly = coalesce(p_price_yearly, 0),
      currency = coalesce(nullif(trim(p_currency), ''), 'INR'),
      features = coalesce(p_features, '[]'::jsonb),
      is_active = coalesce(p_is_active, true),
      sort_order = coalesce(p_sort_order, 0),
      validity_days = v_days
    WHERE id = p_id
    RETURNING * INTO v_plan;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'plan_not_found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'plan', to_jsonb(v_plan));
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_plan_code' USING ERRCODE = '23505';
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin clinic plan + status + create
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_clinic_plan_id(
  p_session_token text,
  p_clinic_id uuid,
  p_plan_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.plans;
  v_clinic public.clinics;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  SELECT * INTO v_plan FROM public.plans WHERE id = p_plan_id AND is_active = true;
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
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_clinic := public.flexza_apply_clinic_plan_period(p_clinic_id);

  RETURN jsonb_build_object(
    'ok', true,
    'clinic_id', v_clinic.id,
    'plan_id', v_plan.id,
    'plan_code', v_plan.code,
    'plan_name', v_plan.name,
    'plan_started_at', v_clinic.plan_started_at,
    'plan_expires_at', v_clinic.plan_expires_at,
    'validity_days', v_plan.validity_days
  );
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
  v_had_expiry boolean;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  SELECT plan_expires_at IS NOT NULL INTO v_had_expiry
  FROM public.clinics
  WHERE id = p_clinic_id;

  UPDATE public.clinics
  SET status = p_status
  WHERE id = p_clinic_id
  RETURNING * INTO v_clinic;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'clinic_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_status = 'active' AND NOT coalesce(v_had_expiry, false) THEN
    v_clinic := public.flexza_apply_clinic_plan_period(p_clinic_id);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'clinic_id', v_clinic.id,
    'status', v_clinic.status,
    'plan_expires_at', v_clinic.plan_expires_at
  );
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
  v_free_plan_id uuid;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF p_name IS NULL OR length(trim(p_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_clinic_name' USING ERRCODE = '22023';
  END IF;

  IF v_slug IS NULL OR v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' THEN
    RAISE EXCEPTION 'invalid_clinic_slug' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_free_plan_id FROM public.plans WHERE code = 'free' LIMIT 1;

  INSERT INTO public.clinics (name, slug, subtitle, status, plan, plan_id)
  VALUES (
    trim(p_name),
    v_slug,
    nullif(trim(coalesce(p_subtitle, '')), ''),
    'active',
    'free',
    v_free_plan_id
  )
  RETURNING * INTO v_clinic;

  v_clinic := public.flexza_apply_clinic_plan_period(v_clinic.id);

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
    'doctor_code', v_doctor.code,
    'plan_expires_at', v_clinic.plan_expires_at
  );
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_slug_or_code' USING ERRCODE = '23505';
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
      c.id, c.name, c.slug, c.subtitle, c.status, c.plan, c.plan_id,
      c.phone, c.email, c.address, c.about,
      c.morning_start, c.morning_end, c.evening_start, c.evening_end,
      c.created_at, c.updated_at,
      c.plan_started_at,
      c.plan_expires_at,
      p.code AS plan_code,
      p.name AS plan_name,
      p.validity_days AS plan_validity_days,
      CASE
        WHEN c.plan_expires_at IS NULL THEN null
        ELSE greatest(0, ceil(extract(epoch FROM (c.plan_expires_at - now())) / 86400)::int)
      END AS plan_days_remaining,
      (c.plan_expires_at IS NOT NULL AND c.plan_expires_at <= now()) AS plan_expired,
      (SELECT count(*)::int FROM public.doctors d WHERE d.clinic_id = c.id) AS doctor_count
    FROM public.clinics c
    LEFT JOIN public.plans p ON p.id = c.plan_id
  ) row;

  RETURN jsonb_build_object('ok', true, 'clinics', v_rows);
END;
$$;

-- ---------------------------------------------------------------------------
-- Apply offer — refresh plan validity when plan linked
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

    v_clinic := public.flexza_apply_clinic_plan_period(p_clinic_id);
  END IF;

  UPDATE public.offer_codes
  SET redemption_count = redemption_count + 1
  WHERE id = v_offer.id;

  RETURN jsonb_build_object(
    'ok', true,
    'offer_code', v_offer.code,
    'plan_id', v_offer.plan_id,
    'plan_name', v_plan.name,
    'plan_expires_at', v_clinic.plan_expires_at
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Staff OTP login — block expired plans
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

  PERFORM public.flexza_assert_clinic_subscription(v_clinic.id);

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

  PERFORM public.flexza_assert_clinic_subscription(v_clinic.id);

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
    'doctor_name', v_doctor.name,
    'plan_expires_at', v_clinic.plan_expires_at
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Patient booking — block expired clinics
-- ---------------------------------------------------------------------------
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
  PERFORM public.flexza_assert_clinic_subscription(v_clinic.id);

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
  PERFORM public.flexza_assert_clinic_subscription(v_clinic.id);

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

GRANT EXECUTE ON FUNCTION public.admin_upsert_plan(
  text, uuid, text, text, text, numeric, numeric, text, jsonb, boolean, int, int
) TO anon, authenticated;
