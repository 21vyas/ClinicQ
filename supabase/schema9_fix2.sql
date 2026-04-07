-- ============================================================
-- ClinicQ Schema 9 Fix 2 — Resolve users table RLS recursion
-- Run this AFTER schema9_fix.sql
-- Root cause: Part 8 "Users can view own record" policy
--   queried public.users inside its own USING clause (super_admin
--   check) and also joined public.users in the colleague check.
--   Both cause infinite recursion.
-- Fix: Add a SECURITY DEFINER helper _is_super_admin() and
--   rewrite the policy to avoid self-referential subqueries.
-- ============================================================

-- Step 1: SECURITY DEFINER helper — bypasses RLS to check super_admin
CREATE OR REPLACE FUNCTION public._is_super_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE auth_id = auth.uid();
  RETURN COALESCE(v_role = 'super_admin', false);
END;
$$;

GRANT EXECUTE ON FUNCTION public._is_super_admin() TO authenticated;

-- Step 2: Replace the recursive users policy
DROP POLICY IF EXISTS "Users can view own record" ON public.users;
CREATE POLICY "Users can view own record"
  ON public.users FOR SELECT
  USING (
    -- Own record — always allowed, no subquery needed
    auth_id = auth.uid()
    OR
    -- super_admin sees all — use SECURITY DEFINER to avoid recursion
    public._is_super_admin()
  );

-- NOTE: The "see colleagues in same hospital" clause was removed.
-- The list_hospital_users() RPC (SECURITY DEFINER) handles colleague
-- lookups safely without needing direct table access via RLS.
