-- Wipe all operational data for a blank E2E start (no Svedna / no clinics).
-- Run in: Supabase Dashboard → SQL Editor → Run
-- Keeps schema, RLS, RPCs, and flexza_app_settings.

TRUNCATE TABLE
  public.tokens,
  public.otp_challenges,
  public.queue_sessions,
  public.patients,
  public.staff_users,
  public.admin_users,
  public.doctors,
  public.clinics
RESTART IDENTITY CASCADE;

-- Confirm blank:
-- SELECT count(*) FROM public.clinics;  -- 0
