-- Flexza RLS policies (Step 3)
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
--
-- Model:
-- - Patient app (anon): can READ active clinic + live queue only
-- - Direct INSERT/UPDATE/DELETE from anon: DENIED (no write policies)
-- - Mutations come later via SECURITY DEFINER RPCs (Step 4) / service_role
-- - staff_users, admin_users, patients, otp_challenges: no public access

-- ---------------------------------------------------------------------------
-- Enable RLS on all public tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.queue_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_challenges ENABLE ROW LEVEL SECURITY;

-- Optional: force RLS even for table owner (RPCs use SECURITY DEFINER carefully)
-- ALTER TABLE ... FORCE ROW LEVEL SECURITY;  -- not enabled yet; RPCs need owner bypass

-- ---------------------------------------------------------------------------
-- Helper: clinic is publicly visible
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_clinic_public(p_clinic_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clinics c
    WHERE c.id = p_clinic_id
      AND c.status = 'active'
  );
$$;

REVOKE ALL ON FUNCTION public.is_clinic_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_clinic_public(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- clinics: public can read active clinics only
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS clinics_public_select_active ON public.clinics;
CREATE POLICY clinics_public_select_active
  ON public.clinics
  FOR SELECT
  TO anon, authenticated
  USING (status = 'active');

-- No INSERT/UPDATE/DELETE policies for anon/authenticated

-- ---------------------------------------------------------------------------
-- doctors: public can read active doctors of active clinics
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS doctors_public_select_active ON public.doctors;
CREATE POLICY doctors_public_select_active
  ON public.doctors
  FOR SELECT
  TO anon, authenticated
  USING (
    is_active = true
    AND public.is_clinic_public(clinic_id)
  );

-- ---------------------------------------------------------------------------
-- queue_sessions: public can read sessions of active clinics (live board)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS queue_sessions_public_select ON public.queue_sessions;
CREATE POLICY queue_sessions_public_select
  ON public.queue_sessions
  FOR SELECT
  TO anon, authenticated
  USING (public.is_clinic_public(clinic_id));

-- ---------------------------------------------------------------------------
-- tokens: public can read tokens of active clinics (live queue numbers)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS tokens_public_select ON public.tokens;
CREATE POLICY tokens_public_select
  ON public.tokens
  FOR SELECT
  TO anon, authenticated
  USING (public.is_clinic_public(clinic_id));

-- ---------------------------------------------------------------------------
-- patients: no public access (book flow uses RPC later)
-- ---------------------------------------------------------------------------
-- (RLS on, zero policies for anon/authenticated = deny)

-- ---------------------------------------------------------------------------
-- staff_users: no public access
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- admin_users: no public access
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- otp_challenges: no public access (OTP only via RPC / edge functions)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Grants: table-level privileges (RLS still applies)
-- service_role bypasses RLS automatically in Supabase
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON public.clinics TO anon, authenticated;
GRANT SELECT ON public.doctors TO anon, authenticated;
GRANT SELECT ON public.queue_sessions TO anon, authenticated;
GRANT SELECT ON public.tokens TO anon, authenticated;

-- Explicitly no grants on sensitive tables for anon/authenticated:
REVOKE ALL ON public.patients FROM anon, authenticated;
REVOKE ALL ON public.staff_users FROM anon, authenticated;
REVOKE ALL ON public.admin_users FROM anon, authenticated;
REVOKE ALL ON public.otp_challenges FROM anon, authenticated;

-- No write grants on queue tables for anon/authenticated
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.clinics FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.doctors FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.queue_sessions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.tokens FROM anon, authenticated;
