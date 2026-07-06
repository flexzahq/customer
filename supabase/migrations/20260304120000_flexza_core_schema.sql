-- Flexza core schema (Step 2)
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run only on empty project (uses IF NOT EXISTS where possible)

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.clinic_status AS ENUM ('active', 'disabled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.clinic_plan AS ENUM ('free', 'starter', 'pro');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('open', 'paused', 'closed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.token_status AS ENUM (
    'waiting',
    'serving',
    'skipped',
    'completed',
    'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.staff_role AS ENUM ('owner', 'staff');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.otp_purpose AS ENUM ('book_token', 'staff_login', 'admin_login');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- clinics (permanent QR = slug; plan/status for admin from day one)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clinics (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  slug          text NOT NULL,
  subtitle      text,
  status        public.clinic_status NOT NULL DEFAULT 'active',
  plan          public.clinic_plan NOT NULL DEFAULT 'free',
  morning_start time,
  morning_end   time,
  evening_start time,
  evening_end   time,
  phone         text,
  email         text,
  address       text,
  about         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT clinics_slug_format CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

CREATE UNIQUE INDEX IF NOT EXISTS clinics_slug_key ON public.clinics (slug);
CREATE INDEX IF NOT EXISTS clinics_status_idx ON public.clinics (status);
CREATE INDEX IF NOT EXISTS clinics_plan_idx ON public.clinics (plan);

COMMENT ON COLUMN public.clinics.slug IS 'Permanent public link/QR target, e.g. /c/svedna — never rotate daily';
COMMENT ON COLUMN public.clinics.plan IS 'free by default; paid plans activated later via admin';
COMMENT ON COLUMN public.clinics.status IS 'admin can disable clinic without deleting data';

-- ---------------------------------------------------------------------------
-- doctors
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.doctors (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id  uuid NOT NULL REFERENCES public.clinics (id) ON DELETE CASCADE,
  name       text NOT NULL,
  -- Globally unique entry/QR code (names may duplicate; codes must not)
  code       text NOT NULL,
  is_active  boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT doctors_code_format CHECK (code ~ '^[A-Z0-9]{4,12}$')
);

CREATE INDEX IF NOT EXISTS doctors_clinic_id_idx ON public.doctors (clinic_id);
CREATE UNIQUE INDEX IF NOT EXISTS doctors_code_key ON public.doctors (code);

-- ---------------------------------------------------------------------------
-- patients (platform-wide by mobile)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.patients (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile     text NOT NULL,
  name       text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT patients_mobile_format CHECK (mobile ~ '^[0-9]{10}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS patients_mobile_key ON public.patients (mobile);

-- ---------------------------------------------------------------------------
-- staff_users (clinic app login)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_users (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id  uuid NOT NULL REFERENCES public.clinics (id) ON DELETE CASCADE,
  mobile     text NOT NULL,
  name       text,
  role       public.staff_role NOT NULL DEFAULT 'owner',
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_users_mobile_format CHECK (mobile ~ '^[0-9]{10}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS staff_users_clinic_mobile_key
  ON public.staff_users (clinic_id, mobile);
CREATE INDEX IF NOT EXISTS staff_users_mobile_idx ON public.staff_users (mobile);

-- ---------------------------------------------------------------------------
-- admin_users (Flexza team — admin panel)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_users (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile     text NOT NULL,
  name       text,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_users_mobile_format CHECK (mobile ~ '^[0-9]{10}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS admin_users_mobile_key ON public.admin_users (mobile);

-- ---------------------------------------------------------------------------
-- queue_sessions (one open/paused session per doctor per calendar day)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.queue_sessions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id   uuid NOT NULL REFERENCES public.doctors (id) ON DELETE CASCADE,
  clinic_id   uuid NOT NULL REFERENCES public.clinics (id) ON DELETE CASCADE,
  session_date date NOT NULL DEFAULT (timezone('Asia/Kolkata', now()))::date,
  status      public.session_status NOT NULL DEFAULT 'open',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS queue_sessions_doctor_date_key
  ON public.queue_sessions (doctor_id, session_date);
CREATE INDEX IF NOT EXISTS queue_sessions_clinic_date_idx
  ON public.queue_sessions (clinic_id, session_date);
CREATE INDEX IF NOT EXISTS queue_sessions_status_idx
  ON public.queue_sessions (status);

-- ---------------------------------------------------------------------------
-- tokens (sequential number per session)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL REFERENCES public.queue_sessions (id) ON DELETE CASCADE,
  clinic_id   uuid NOT NULL REFERENCES public.clinics (id) ON DELETE CASCADE,
  doctor_id   uuid NOT NULL REFERENCES public.doctors (id) ON DELETE CASCADE,
  patient_id  uuid NOT NULL REFERENCES public.patients (id) ON DELETE RESTRICT,
  number      int NOT NULL,
  status      public.token_status NOT NULL DEFAULT 'waiting',
  booked_at   timestamptz NOT NULL DEFAULT now(),
  called_at   timestamptz,
  completed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tokens_number_positive CHECK (number > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS tokens_session_number_key
  ON public.tokens (session_id, number);

-- One active (waiting/serving) token per patient per session
CREATE UNIQUE INDEX IF NOT EXISTS tokens_one_active_per_patient_session
  ON public.tokens (session_id, patient_id)
  WHERE status IN ('waiting', 'serving');

-- At most one serving token per session
CREATE UNIQUE INDEX IF NOT EXISTS tokens_one_serving_per_session
  ON public.tokens (session_id)
  WHERE status = 'serving';

CREATE INDEX IF NOT EXISTS tokens_session_status_idx
  ON public.tokens (session_id, status);
CREATE INDEX IF NOT EXISTS tokens_clinic_booked_at_idx
  ON public.tokens (clinic_id, booked_at DESC);
CREATE INDEX IF NOT EXISTS tokens_patient_id_idx ON public.tokens (patient_id);

-- ---------------------------------------------------------------------------
-- otp_challenges (OTP required on every patient book)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.otp_challenges (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mobile      text NOT NULL,
  code_hash   text NOT NULL,
  purpose     public.otp_purpose NOT NULL,
  clinic_id   uuid REFERENCES public.clinics (id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  verified_at timestamptz,
  attempts    int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT otp_challenges_mobile_format CHECK (mobile ~ '^[0-9]{10}$')
);

CREATE INDEX IF NOT EXISTS otp_challenges_mobile_purpose_idx
  ON public.otp_challenges (mobile, purpose, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clinics_set_updated_at ON public.clinics;
CREATE TRIGGER clinics_set_updated_at
  BEFORE UPDATE ON public.clinics
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS doctors_set_updated_at ON public.doctors;
CREATE TRIGGER doctors_set_updated_at
  BEFORE UPDATE ON public.doctors
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS patients_set_updated_at ON public.patients;
CREATE TRIGGER patients_set_updated_at
  BEFORE UPDATE ON public.patients
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS staff_users_set_updated_at ON public.staff_users;
CREATE TRIGGER staff_users_set_updated_at
  BEFORE UPDATE ON public.staff_users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS admin_users_set_updated_at ON public.admin_users;
CREATE TRIGGER admin_users_set_updated_at
  BEFORE UPDATE ON public.admin_users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS queue_sessions_set_updated_at ON public.queue_sessions;
CREATE TRIGGER queue_sessions_set_updated_at
  BEFORE UPDATE ON public.queue_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS tokens_set_updated_at ON public.tokens;
CREATE TRIGGER tokens_set_updated_at
  BEFORE UPDATE ON public.tokens
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
