-- Plans CRUD, offer codes, admin notifications
-- Run in: Supabase Dashboard → SQL Editor → Run

-- ---------------------------------------------------------------------------
-- Plans (packages)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.plans (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            text NOT NULL,
  name            text NOT NULL,
  description     text,
  price_monthly   numeric(12, 2) NOT NULL DEFAULT 0,
  price_yearly    numeric(12, 2) NOT NULL DEFAULT 0,
  currency        text NOT NULL DEFAULT 'INR',
  features        jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active       boolean NOT NULL DEFAULT true,
  sort_order      int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT plans_code_format CHECK (code ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

CREATE UNIQUE INDEX IF NOT EXISTS plans_code_key ON public.plans (code);

DROP TRIGGER IF EXISTS plans_set_updated_at ON public.plans;
CREATE TRIGGER plans_set_updated_at
  BEFORE UPDATE ON public.plans
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.plans FROM anon, authenticated;

INSERT INTO public.plans (code, name, description, price_monthly, price_yearly, features, sort_order)
VALUES
  ('free', 'Free', 'Starter queue for pilots', 0, 0, '["Live queue","OTP booking","1 doctor"]'::jsonb, 0),
  ('starter', 'Starter', 'For growing clinics', 799, 7999, '["Live queue","OTP booking","WhatsApp alerts","QR"]'::jsonb, 1),
  ('pro', 'Pro', 'Full features', 1999, 19999, '["Everything in Starter","Multi doctor","Priority support"]'::jsonb, 2)
ON CONFLICT (code) DO NOTHING;

-- Link clinics to plans (keep legacy enum column in sync for now)
ALTER TABLE public.clinics
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.plans (id);

UPDATE public.clinics c
SET plan_id = p.id
FROM public.plans p
WHERE c.plan_id IS NULL
  AND p.code = c.plan::text;

-- ---------------------------------------------------------------------------
-- Offer codes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.offer_codes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code              text NOT NULL,
  description       text,
  plan_id           uuid REFERENCES public.plans (id) ON DELETE SET NULL,
  discount_percent  numeric(5, 2),
  discount_amount   numeric(12, 2),
  max_redemptions   int,
  redemption_count  int NOT NULL DEFAULT 0,
  starts_at         timestamptz,
  ends_at           timestamptz,
  is_active         boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT offer_codes_code_format CHECK (code = upper(code)),
  CONSTRAINT offer_codes_discount_check CHECK (
    discount_percent IS NOT NULL OR discount_amount IS NOT NULL
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS offer_codes_code_key ON public.offer_codes (code);

DROP TRIGGER IF EXISTS offer_codes_set_updated_at ON public.offer_codes;
CREATE TRIGGER offer_codes_set_updated_at
  BEFORE UPDATE ON public.offer_codes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.offer_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.offer_codes FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admin notifications (broadcast log / trigger records)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.notification_audience AS ENUM ('all', 'active_clinics', 'clinic');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'sent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title       text NOT NULL,
  body        text NOT NULL,
  audience    public.notification_audience NOT NULL DEFAULT 'all',
  clinic_id   uuid REFERENCES public.clinics (id) ON DELETE SET NULL,
  status      public.notification_status NOT NULL DEFAULT 'draft',
  sent_at     timestamptz,
  created_by  uuid REFERENCES public.admin_accounts (id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_notifications_created_at_idx
  ON public.admin_notifications (created_at DESC);

ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_notifications FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Plans RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_plans(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rows jsonb;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.sort_order, p.created_at), '[]'::jsonb)
  INTO v_rows FROM public.plans p;
  RETURN jsonb_build_object('ok', true, 'plans', v_rows);
END;
$$;

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
  p_sort_order int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_code text := lower(trim(coalesce(p_code, '')));
  v_plan public.plans;
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
      code, name, description, price_monthly, price_yearly, currency, features, is_active, sort_order
    ) VALUES (
      v_code, trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
      coalesce(p_price_monthly, 0), coalesce(p_price_yearly, 0),
      coalesce(nullif(trim(p_currency), ''), 'INR'),
      coalesce(p_features, '[]'::jsonb), coalesce(p_is_active, true), coalesce(p_sort_order, 0)
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
      sort_order = coalesce(p_sort_order, 0)
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

CREATE OR REPLACE FUNCTION public.admin_delete_plan(
  p_session_token text,
  p_plan_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_code text;
  v_in_use int;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  SELECT code INTO v_code FROM public.plans WHERE id = p_plan_id;
  IF v_code IS NULL THEN
    RAISE EXCEPTION 'plan_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_code IN ('free', 'starter', 'pro') THEN
    RAISE EXCEPTION 'plan_protected' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)::int INTO v_in_use FROM public.clinics WHERE plan_id = p_plan_id;
  IF v_in_use > 0 THEN
    RAISE EXCEPTION 'plan_in_use' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.plans WHERE id = p_plan_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Assign plan by plan id (and sync legacy enum when code matches)
CREATE OR REPLACE FUNCTION public.admin_set_clinic_plan_id(
  p_session_token text,
  p_clinic_id uuid,
  p_plan_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

  RETURN jsonb_build_object(
    'ok', true,
    'clinic_id', v_clinic.id,
    'plan_id', v_plan.id,
    'plan_code', v_plan.code
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Offer codes RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_offers(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rows jsonb;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT o.*, p.code AS plan_code, p.name AS plan_name
    FROM public.offer_codes o
    LEFT JOIN public.plans p ON p.id = o.plan_id
  ) row;
  RETURN jsonb_build_object('ok', true, 'offers', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_offer(
  p_session_token text,
  p_id uuid DEFAULT NULL,
  p_code text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_plan_id uuid DEFAULT NULL,
  p_discount_percent numeric DEFAULT NULL,
  p_discount_amount numeric DEFAULT NULL,
  p_max_redemptions int DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_code text := upper(trim(coalesce(p_code, '')));
  v_offer public.offer_codes;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  IF v_code IS NULL OR length(v_code) < 3 THEN
    RAISE EXCEPTION 'invalid_offer_code' USING ERRCODE = '22023';
  END IF;

  IF p_discount_percent IS NULL AND p_discount_amount IS NULL THEN
    RAISE EXCEPTION 'invalid_offer_discount' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.offer_codes (
      code, description, plan_id, discount_percent, discount_amount,
      max_redemptions, starts_at, ends_at, is_active
    ) VALUES (
      v_code,
      nullif(trim(coalesce(p_description, '')), ''),
      p_plan_id,
      p_discount_percent,
      p_discount_amount,
      p_max_redemptions,
      p_starts_at,
      p_ends_at,
      coalesce(p_is_active, true)
    )
    RETURNING * INTO v_offer;
  ELSE
    UPDATE public.offer_codes
    SET
      code = v_code,
      description = nullif(trim(coalesce(p_description, '')), ''),
      plan_id = p_plan_id,
      discount_percent = p_discount_percent,
      discount_amount = p_discount_amount,
      max_redemptions = p_max_redemptions,
      starts_at = p_starts_at,
      ends_at = p_ends_at,
      is_active = coalesce(p_is_active, true)
    WHERE id = p_id
    RETURNING * INTO v_offer;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer_not_found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'offer', to_jsonb(v_offer));
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_offer_code' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_offer_active(
  p_session_token text,
  p_offer_id uuid,
  p_is_active boolean
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_offer public.offer_codes;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  UPDATE public.offer_codes
  SET is_active = p_is_active
  WHERE id = p_offer_id
  RETURNING * INTO v_offer;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object('ok', true, 'offer_id', v_offer.id, 'is_active', v_offer.is_active);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_offer(
  p_session_token text,
  p_offer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  DELETE FROM public.offer_codes WHERE id = p_offer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- Notifications RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_notifications(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rows jsonb;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);
  SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY row.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT n.*, c.name AS clinic_name
    FROM public.admin_notifications n
    LEFT JOIN public.clinics c ON c.id = n.clinic_id
    ORDER BY n.created_at DESC
    LIMIT 100
  ) row;
  RETURN jsonb_build_object('ok', true, 'notifications', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_create_notification(
  p_session_token text,
  p_title text,
  p_body text,
  p_audience public.notification_audience DEFAULT 'all',
  p_clinic_id uuid DEFAULT NULL,
  p_send_now boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_row public.admin_notifications;
BEGIN
  v_admin_id := public.flexza_assert_admin(p_session_token);

  IF p_title IS NULL OR length(trim(p_title)) < 2 THEN
    RAISE EXCEPTION 'invalid_notification_title' USING ERRCODE = '22023';
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) < 2 THEN
    RAISE EXCEPTION 'invalid_notification_body' USING ERRCODE = '22023';
  END IF;
  IF p_audience = 'clinic' AND p_clinic_id IS NULL THEN
    RAISE EXCEPTION 'clinic_required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.admin_notifications (
    title, body, audience, clinic_id, status, sent_at, created_by
  ) VALUES (
    trim(p_title),
    trim(p_body),
    p_audience,
    CASE WHEN p_audience = 'clinic' THEN p_clinic_id ELSE NULL END,
    CASE WHEN p_send_now THEN 'sent'::public.notification_status ELSE 'draft'::public.notification_status END,
    CASE WHEN p_send_now THEN now() ELSE NULL END,
    v_admin_id
  )
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('ok', true, 'notification', to_jsonb(v_row));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_send_notification(
  p_session_token text,
  p_notification_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_row public.admin_notifications;
BEGIN
  PERFORM public.flexza_assert_admin(p_session_token);

  UPDATE public.admin_notifications
  SET status = 'sent', sent_at = now()
  WHERE id = p_notification_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Hook point for SMS/WhatsApp/push providers later.
  RETURN jsonb_build_object('ok', true, 'notification', to_jsonb(v_row));
END;
$$;

-- Extend clinic list with plan_id + plan details
CREATE OR REPLACE FUNCTION public.admin_list_clinics(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_rows jsonb;
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
      p.code AS plan_code,
      p.name AS plan_name,
      (SELECT count(*)::int FROM public.doctors d WHERE d.clinic_id = c.id) AS doctor_count
    FROM public.clinics c
    LEFT JOIN public.plans p ON p.id = c.plan_id
  ) row;

  RETURN jsonb_build_object('ok', true, 'clinics', v_rows);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_plans(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_plan(text, uuid, text, text, text, numeric, numeric, text, jsonb, boolean, int) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_plan(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_clinic_plan_id(text, uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_offers(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_offer(text, uuid, text, text, uuid, numeric, numeric, int, timestamptz, timestamptz, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_offer_active(text, uuid, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_offer(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_notifications(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_notification(text, text, text, public.notification_audience, uuid, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_notification(text, uuid) TO anon, authenticated;
