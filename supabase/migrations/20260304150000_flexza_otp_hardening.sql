-- Flexza OTP hardening (Step 5)
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
--
-- Step 4 already requires OTP on every book.
-- Step 5: rate limits, cooldown, dev_otp flag (SMS provider later).

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- App settings (admin can flip later; no SMS keys in DB)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.flexza_app_settings (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL DEFAULT 'null'::jsonb,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.flexza_app_settings ENABLE ROW LEVEL SECURITY;
-- No public policies: deny anon/authenticated direct access

REVOKE ALL ON public.flexza_app_settings FROM anon, authenticated;

INSERT INTO public.flexza_app_settings (key, value)
VALUES
  ('expose_dev_otp', 'true'::jsonb),
  ('otp_cooldown_seconds', '30'::jsonb),
  ('otp_max_per_hour', '5'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.flexza_setting_bool(p_key text, p_default boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT (value = 'true'::jsonb OR value = 'true') FROM public.flexza_app_settings WHERE key = p_key),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION public.flexza_setting_int(p_key text, p_default int)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT (value #>> '{}')::int FROM public.flexza_app_settings WHERE key = p_key),
    p_default
  );
$$;

-- ---------------------------------------------------------------------------
-- request_book_otp (hardened)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_book_otp(
  p_clinic_slug text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mobile text;
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
  v_clinic := public.flexza_get_active_clinic(p_clinic_slug);

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

  -- Expire previous unused challenges
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

  -- SMS provider (MSG91 / Twilio) will send v_code here later via Edge Function.
  -- Until then, expose_dev_otp=true returns code for testing only.

  v_result := jsonb_build_object(
    'ok', true,
    'challenge_id', v_id,
    'expires_in_seconds', 600,
    'message', 'OTP sent'
  );

  IF v_expose_dev THEN
    v_result := v_result || jsonb_build_object('dev_otp', v_code);
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_book_otp(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.flexza_setting_bool(text, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.flexza_setting_int(text, int) TO anon, authenticated;
