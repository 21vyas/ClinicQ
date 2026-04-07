-- ============================================================
-- ClinicQ - Complete Database Schema
-- Run this in Supabase SQL Editor
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. USERS TABLE
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id     UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  full_name   TEXT,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 2. HOSPITALS TABLE
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hospitals (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL,
  address     TEXT,
  phone       TEXT,
  created_by  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 3. HOSPITAL SETTINGS TABLE
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hospital_settings (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id           UUID UNIQUE NOT NULL REFERENCES public.hospitals(id) ON DELETE CASCADE,
  token_limit           INT DEFAULT 100,
  avg_time_per_patient  INT DEFAULT 5,   -- in minutes
  alert_before          INT DEFAULT 3,   -- tokens before, trigger alert
  working_hours_start   TIME DEFAULT '09:00',
  working_hours_end     TIME DEFAULT '18:00',
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 4. INDEXES FOR PERFORMANCE
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_auth_id     ON public.users(auth_id);
CREATE INDEX IF NOT EXISTS idx_hospitals_created_by ON public.hospitals(created_by);
CREATE INDEX IF NOT EXISTS idx_hospital_settings_hospital_id ON public.hospital_settings(hospital_id);

-- ============================================================
-- AUTO PROFILE CREATION TRIGGER
-- Fires when a new auth user signs up
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (auth_id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture', '')
  )
  ON CONFLICT (auth_id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Drop trigger if it already exists (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hospitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hospital_settings ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────
-- USERS policies
-- ─────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can view own record" ON public.users;
CREATE POLICY "Users can view own record"
  ON public.users FOR SELECT
  USING (auth_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own record" ON public.users;
CREATE POLICY "Users can update own record"
  ON public.users FOR UPDATE
  USING (auth_id = auth.uid());

DROP POLICY IF EXISTS "Allow trigger insert" ON public.users;
CREATE POLICY "Allow trigger insert"
  ON public.users FOR INSERT
  WITH CHECK (auth_id = auth.uid());

-- ─────────────────────────────────────────────
-- HOSPITALS policies
-- ─────────────────────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can insert hospital" ON public.hospitals;
CREATE POLICY "Authenticated users can insert hospital"
  ON public.hospitals FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL AND
    created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can view own hospitals" ON public.hospitals;
CREATE POLICY "Users can view own hospitals"
  ON public.hospitals FOR SELECT
  USING (
    created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can update own hospitals" ON public.hospitals;
CREATE POLICY "Users can update own hospitals"
  ON public.hospitals FOR UPDATE
  USING (
    created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
  );

-- ─────────────────────────────────────────────
-- HOSPITAL SETTINGS policies
-- ─────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can view own hospital settings" ON public.hospital_settings;
CREATE POLICY "Users can view own hospital settings"
  ON public.hospital_settings FOR SELECT
  USING (
    hospital_id IN (
      SELECT id FROM public.hospitals
      WHERE created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can insert own hospital settings" ON public.hospital_settings;
CREATE POLICY "Users can insert own hospital settings"
  ON public.hospital_settings FOR INSERT
  WITH CHECK (
    hospital_id IN (
      SELECT id FROM public.hospitals
      WHERE created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update own hospital settings" ON public.hospital_settings;
CREATE POLICY "Users can update own hospital settings"
  ON public.hospital_settings FOR UPDATE
  USING (
    hospital_id IN (
      SELECT id FROM public.hospitals
      WHERE created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
  );

-- ============================================================
-- HELPER FUNCTION: Get user's hospital
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_hospital(user_auth_id UUID)
RETURNS TABLE (
  hospital_id   UUID,
  hospital_name TEXT,
  hospital_slug TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT h.id, h.name, h.slug
  FROM public.hospitals h
  JOIN public.users u ON h.created_by = u.id
  WHERE u.auth_id = user_auth_id
  LIMIT 1;
END;
$$;
