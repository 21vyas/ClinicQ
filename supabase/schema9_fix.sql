-- ============================================================
-- ClinicQ Schema 9 Fix — Resolve hospital_users RLS recursion
-- Run this AFTER schema9.sql
-- Root cause: Part 6 policies queried hospital_users inside
--   their own USING clause → infinite recursion.
-- Fix: use SECURITY DEFINER helpers that bypass RLS instead.
-- ============================================================

-- ── SELECT ───────────────────────────────────────────────
DROP POLICY IF EXISTS "Hospital members can view staff" ON public.hospital_users;
CREATE POLICY "Hospital members can view staff"
  ON public.hospital_users FOR SELECT
  USING (
    public._is_hospital_member(hospital_id)
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE auth_id = auth.uid() AND role = 'super_admin'
    )
  );

-- ── INSERT ───────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin can add staff" ON public.hospital_users;
CREATE POLICY "Admin can add staff"
  ON public.hospital_users FOR INSERT
  WITH CHECK (
    public._is_hospital_admin(hospital_id)
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE auth_id = auth.uid() AND role = 'super_admin'
    )
  );

-- ── UPDATE ───────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin can update staff" ON public.hospital_users;
CREATE POLICY "Admin can update staff"
  ON public.hospital_users FOR UPDATE
  USING (
    public._is_hospital_admin(hospital_id)
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE auth_id = auth.uid() AND role = 'super_admin'
    )
  );
