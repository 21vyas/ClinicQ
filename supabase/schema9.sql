-- ============================================================
-- ClinicQ Schema 9 — RBAC (Role-Based Access Control)
-- Run AFTER schema8.sql
-- SAFE: no DROP TABLE, no DROP COLUMN, no breaking changes
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- PART 1: Extend users table
-- ─────────────────────────────────────────────────────────

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS role      TEXT    NOT NULL DEFAULT 'admin'
    CHECK (role IN ('super_admin', 'admin', 'staff')),
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Backfill: any existing rows without a valid role → 'admin'
UPDATE public.users
SET role = 'admin'
WHERE role NOT IN ('super_admin', 'admin', 'staff');

-- ─────────────────────────────────────────────────────────
-- PART 2: hospital_users — per-hospital role assignments
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.hospital_users (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id UUID    NOT NULL REFERENCES public.hospitals(id)  ON DELETE CASCADE,
  user_id     UUID    NOT NULL REFERENCES public.users(id)      ON DELETE CASCADE,
  role        TEXT    NOT NULL DEFAULT 'staff'
    CHECK (role IN ('admin', 'staff')),
  is_active   BOOLEAN NOT NULL DEFAULT true,
  invited_by  UUID    REFERENCES public.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (hospital_id, user_id)
);

-- ─────────────────────────────────────────────────────────
-- PART 3: Indexes
-- ─────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_hospital_users_hospital ON public.hospital_users(hospital_id);
CREATE INDEX IF NOT EXISTS idx_hospital_users_user     ON public.hospital_users(user_id);
CREATE INDEX IF NOT EXISTS idx_users_role              ON public.users(role);

-- ─────────────────────────────────────────────────────────
-- PART 4: Backfill — map every hospital owner into hospital_users
-- ─────────────────────────────────────────────────────────

INSERT INTO public.hospital_users (hospital_id, user_id, role, is_active, invited_by)
SELECT h.id, h.created_by, 'admin', true, h.created_by
FROM public.hospitals h
WHERE h.created_by IS NOT NULL
ON CONFLICT (hospital_id, user_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────
-- PART 5: Trigger — auto-add owner to hospital_users on new hospital
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_hospital()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.hospital_users (hospital_id, user_id, role, is_active, invited_by)
  VALUES (NEW.id, NEW.created_by, 'admin', true, NEW.created_by)
  ON CONFLICT (hospital_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_hospital_created ON public.hospitals;
CREATE TRIGGER on_hospital_created
  AFTER INSERT ON public.hospitals
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_hospital();

-- ─────────────────────────────────────────────────────────
-- PART 6: RLS on hospital_users
-- ─────────────────────────────────────────────────────────

ALTER TABLE public.hospital_users ENABLE ROW LEVEL SECURITY;

-- NOTE: These policies use SECURITY DEFINER helper functions (defined in Part 9)
-- to avoid infinite recursion. Direct hospital_users subqueries inside a
-- hospital_users policy cause PostgreSQL to recurse indefinitely.
-- The SECURITY DEFINER functions bypass RLS when they query hospital_users.

-- Members can view their own hospital's user list
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

-- Only admins can insert (invite staff)
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

-- Only admins can update (toggle active / change role)
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

-- ─────────────────────────────────────────────────────────
-- PART 7: Update hospitals SELECT policy — let staff see their hospital
-- ─────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Users can view own hospitals" ON public.hospitals;
CREATE POLICY "Users can view own hospitals"
  ON public.hospitals FOR SELECT
  USING (
    created_by = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.hospital_users hu
      JOIN public.users u ON u.id = hu.user_id
      WHERE hu.hospital_id = hospitals.id
        AND u.auth_id      = auth.uid()
        AND hu.is_active   = true
    )
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE auth_id = auth.uid() AND role = 'super_admin'
    )
  );

-- ─────────────────────────────────────────────────────────
-- PART 8: users table — safe SELECT policy (no self-recursion)
-- The colleague-visibility and super_admin checks both caused
-- recursion when querying public.users inside its own policy.
-- Solution: use _is_super_admin() SECURITY DEFINER helper
-- (defined below in Part 9 — run Parts 9 then 8 if needed,
--  or just run schema9_fix2.sql which sets it up correctly).
-- ─────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Users can view own record" ON public.users;
CREATE POLICY "Users can view own record"
  ON public.users FOR SELECT
  USING (
    auth_id = auth.uid()
    OR public._is_super_admin()
  );

-- ─────────────────────────────────────────────────────────
-- PART 9: Private helper functions
-- ─────────────────────────────────────────────────────────

-- Returns the caller's hospital-level role, or NULL if not a member
CREATE OR REPLACE FUNCTION public._caller_hospital_role(p_hospital_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_global_role TEXT;
  v_role       TEXT;
BEGIN
  SELECT u.id, u.role INTO v_user_id, v_global_role
  FROM public.users u WHERE u.auth_id = auth.uid();

  IF v_user_id IS NULL THEN RETURN NULL; END IF;
  IF v_global_role = 'super_admin' THEN RETURN 'admin'; END IF;

  SELECT hu.role INTO v_role
  FROM public.hospital_users hu
  WHERE hu.hospital_id = p_hospital_id
    AND hu.user_id     = v_user_id
    AND hu.is_active   = true;

  RETURN v_role; -- NULL if not a member
END;
$$;

-- True if caller is a member (any role) of the hospital
CREATE OR REPLACE FUNCTION public._is_hospital_member(p_hospital_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public._caller_hospital_role(p_hospital_id) IS NOT NULL;
END;
$$;

-- True if caller is an admin of the hospital
CREATE OR REPLACE FUNCTION public._is_hospital_admin(p_hospital_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public._caller_hospital_role(p_hospital_id) = 'admin';
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 10: New RPC — get_my_hospital
-- Returns the hospital + caller's role for any member
-- Replaces direct hospitals table query (works for staff too)
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_hospital()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    UUID;
  v_global_role TEXT;
  v_h          public.hospitals;
  v_my_role    TEXT;
BEGIN
  SELECT u.id, u.role INTO v_user_id, v_global_role
  FROM public.users u WHERE u.auth_id = auth.uid();

  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  -- Find hospital via hospital_users (covers both owners and staff)
  SELECT h.* INTO v_h
  FROM public.hospital_users hu
  JOIN public.hospitals h ON h.id = hu.hospital_id
  WHERE hu.user_id   = v_user_id
    AND hu.is_active = true
  ORDER BY hu.created_at ASC
  LIMIT 1;

  IF NOT FOUND THEN RETURN NULL; END IF;

  -- Get hospital-level role
  SELECT hu.role INTO v_my_role
  FROM public.hospital_users hu
  WHERE hu.hospital_id = v_h.id
    AND hu.user_id     = v_user_id
    AND hu.is_active   = true;

  -- super_admin always gets admin role
  IF v_global_role = 'super_admin' THEN v_my_role := 'admin'; END IF;

  RETURN json_build_object(
    'id',         v_h.id,
    'name',       v_h.name,
    'slug',       v_h.slug,
    'address',    v_h.address,
    'phone',      v_h.phone,
    'created_by', v_h.created_by,
    'created_at', v_h.created_at,
    'my_role',    COALESCE(v_my_role, 'staff')
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 11: New RPC — list_hospital_users (admin only)
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.list_hospital_users(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_members JSON;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT json_agg(json_build_object(
    'id',         hu.id,
    'user_id',    u.id,
    'email',      u.email,
    'full_name',  u.full_name,
    'role',       hu.role,
    'is_active',  hu.is_active,
    'created_at', hu.created_at
  ) ORDER BY hu.created_at ASC) INTO v_members
  FROM public.hospital_users hu
  JOIN public.users u ON u.id = hu.user_id
  WHERE hu.hospital_id = p_hospital_id;

  RETURN json_build_object(
    'members', COALESCE(v_members, '[]'::JSON)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 12: New RPC — invite_staff (admin only)
-- Looks up user by email; adds to hospital_users as staff.
-- User must already have a ClinicQ account.
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.invite_staff(
  p_hospital_id UUID,
  p_email       TEXT,
  p_role        TEXT DEFAULT 'staff'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id  UUID;
  v_target_id  UUID;
BEGIN
  IF p_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'role must be admin or staff';
  END IF;

  IF NOT public._is_hospital_admin(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: only admins can invite staff';
  END IF;

  SELECT id INTO v_caller_id FROM public.users WHERE auth_id = auth.uid();

  SELECT id INTO v_target_id FROM public.users
  WHERE lower(email) = lower(trim(p_email));

  IF v_target_id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND: No ClinicQ account found for %', p_email;
  END IF;

  IF v_target_id = v_caller_id THEN
    RAISE EXCEPTION 'Cannot invite yourself';
  END IF;

  INSERT INTO public.hospital_users (hospital_id, user_id, role, is_active, invited_by)
  VALUES (p_hospital_id, v_target_id, p_role, true, v_caller_id)
  ON CONFLICT (hospital_id, user_id) DO UPDATE
    SET role      = EXCLUDED.role,
        is_active = true;

  RETURN json_build_object(
    'success', true,
    'email',   p_email,
    'role',    p_role
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 13: New RPC — toggle_staff_active (admin only)
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.toggle_staff_active(
  p_hospital_user_id UUID,
  p_is_active        BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
BEGIN
  SELECT hospital_id INTO v_hospital_id
  FROM public.hospital_users WHERE id = p_hospital_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;

  IF NOT public._is_hospital_admin(v_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  UPDATE public.hospital_users
  SET is_active = p_is_active
  WHERE id = p_hospital_user_id;

  RETURN json_build_object('success', true, 'is_active', p_is_active);
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 14: New RPC — update_staff_role (admin only)
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_staff_role(
  p_hospital_user_id UUID,
  p_role             TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital_id UUID;
BEGIN
  IF p_role NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'role must be admin or staff';
  END IF;

  SELECT hospital_id INTO v_hospital_id
  FROM public.hospital_users WHERE id = p_hospital_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;

  IF NOT public._is_hospital_admin(v_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  UPDATE public.hospital_users
  SET role = p_role
  WHERE id = p_hospital_user_id;

  RETURN json_build_object('success', true, 'role', p_role);
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 15: Update existing RPCs — extend auth check to hospital_users
-- All changes are backward-compatible: existing owners still pass
-- because they are in hospital_users with role='admin' (backfilled).
-- ─────────────────────────────────────────────────────────

-- ── call_next_token ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.call_next_token(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today        DATE := CURRENT_DATE;
  v_next_entry   public.queue_entries;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have access to this hospital';
  END IF;

  UPDATE public.queue_entries
  SET status = 'done', completed_at = NOW(), updated_at = NOW()
  WHERE hospital_id = p_hospital_id AND queue_date = v_today
    AND status IN ('in_progress', 'serving');

  UPDATE public.queue_daily_state
  SET total_served = total_served + 1, updated_at = NOW()
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT * INTO v_next_entry
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today AND status = 'waiting'
  ORDER BY token_number ASC LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'No more patients in queue');
  END IF;

  UPDATE public.queue_entries
  SET status = 'in_progress', called_at = NOW(), updated_at = NOW()
  WHERE id = v_next_entry.id;

  INSERT INTO public.queue_daily_state (hospital_id, queue_date, current_token_number, last_token_number)
  VALUES (p_hospital_id, v_today, v_next_entry.token_number, v_next_entry.token_number)
  ON CONFLICT (hospital_id, queue_date) DO UPDATE
    SET current_token_number = v_next_entry.token_number, updated_at = NOW();

  RETURN json_build_object(
    'success',       true,
    'token_number',  v_next_entry.token_number,
    'patient_name',  v_next_entry.patient_name,
    'patient_phone', v_next_entry.patient_phone,
    'entry_id',      v_next_entry.id
  );
END;
$$;

-- ── complete_token ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.complete_token(p_entry_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry     public.queue_entries;
  v_wait_mins INT;
BEGIN
  SELECT * INTO v_entry FROM public.queue_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue entry not found'; END IF;

  IF NOT public._is_hospital_member(v_entry.hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  IF v_entry.status NOT IN ('in_progress', 'waiting', 'serving') THEN
    RAISE EXCEPTION 'Cannot complete entry with status: %', v_entry.status;
  END IF;

  IF v_entry.called_at IS NOT NULL THEN
    v_wait_mins := EXTRACT(EPOCH FROM (NOW() - v_entry.called_at)) / 60;
  END IF;

  UPDATE public.queue_entries
  SET status = 'done', completed_at = NOW(), updated_at = NOW()
  WHERE id = p_entry_id;

  UPDATE public.queue_daily_state
  SET total_served    = total_served + 1,
      avg_actual_wait = CASE
        WHEN total_served = 0 THEN COALESCE(v_wait_mins, 0)
        ELSE (avg_actual_wait * total_served + COALESCE(v_wait_mins, 0)) / (total_served + 1)
      END,
      updated_at = NOW()
  WHERE hospital_id = v_entry.hospital_id AND queue_date = v_entry.queue_date;

  RETURN json_build_object('success', true, 'entry_id', p_entry_id,
      'wait_mins', COALESCE(v_wait_mins, 0));
END;
$$;

-- ── skip_token ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.skip_token(p_entry_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry public.queue_entries;
BEGIN
  SELECT * INTO v_entry FROM public.queue_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Entry not found'; END IF;

  IF NOT public._is_hospital_member(v_entry.hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  UPDATE public.queue_entries
  SET status = 'skipped', updated_at = NOW()
  WHERE id = p_entry_id;

  RETURN json_build_object('success', true, 'entry_id', p_entry_id);
END;
$$;

-- ── reset_queue_today (admin-only) ───────────────────────
CREATE OR REPLACE FUNCTION public.reset_queue_today(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today   DATE := CURRENT_DATE;
  v_deleted INT;
BEGIN
  IF NOT public._is_hospital_admin(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: only admins can reset the queue';
  END IF;

  DELETE FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  UPDATE public.queue_daily_state SET
    last_token_number    = 0,
    current_token_number = 0,
    total_served         = 0,
    avg_actual_wait      = 0,
    updated_at           = NOW()
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  RETURN json_build_object('success', true, 'deleted', v_deleted);
END;
$$;

-- ── get_queue_today ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_queue_today(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today        DATE := CURRENT_DATE;
  v_entries      JSON;
  v_daily        public.queue_daily_state;
  v_counts       JSON;
  v_avg_settings INT;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_settings
  FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  SELECT json_agg(json_build_object(
    'id',            e.id,
    'hospital_id',   e.hospital_id,
    'token_number',  e.token_number,
    'queue_date',    e.queue_date,
    'patient_name',  e.patient_name,
    'patient_phone', e.patient_phone,
    'patient_age',   e.patient_age,
    'reason',        e.reason,
    'status',        e.status,
    'called_at',     e.called_at,
    'completed_at',  e.completed_at,
    'created_at',    e.created_at,
    'updated_at',    e.updated_at
  ) ORDER BY e.token_number ASC) INTO v_entries
  FROM public.queue_entries e
  WHERE e.hospital_id = p_hospital_id AND e.queue_date = v_today;

  SELECT json_build_object(
    'total',       COUNT(*),
    'waiting',     COUNT(*) FILTER (WHERE status = 'waiting'),
    'in_progress', COUNT(*) FILTER (WHERE status IN ('in_progress','serving')),
    'done',        COUNT(*) FILTER (WHERE status = 'done'),
    'skipped',     COUNT(*) FILTER (WHERE status = 'skipped')
  ) INTO v_counts
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  RETURN json_build_object(
    'entries',              COALESCE(v_entries, '[]'::JSON),
    'current_token_number', COALESCE(v_daily.current_token_number, 0),
    'last_token_number',    COALESCE(v_daily.last_token_number, 0),
    'total_served',         COALESCE(v_daily.total_served, 0),
    'avg_actual_wait',      COALESCE(v_daily.avg_actual_wait, 0),
    'avg_time_setting',     COALESCE(v_avg_settings, 5),
    'counts',               v_counts,
    'queue_date',           v_today
  );
END;
$$;

-- ── get_analytics ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_analytics(
  p_hospital_id UUID,
  p_date_from   DATE DEFAULT CURRENT_DATE,
  p_date_to     DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_patients  INT;
  v_total_done      INT;
  v_avg_wait_mins   INT;
  v_visit_type_dist JSON;
  v_peak_hours      JSON;
  v_daily_totals    JSON;
  v_top_reasons     JSON;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT COUNT(*) INTO v_total_patients FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to;

  SELECT COUNT(*) INTO v_total_done FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
    AND status = 'done';

  SELECT COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (called_at - created_at)) / 60))::INT, 0)
  INTO v_avg_wait_mins FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
    AND status = 'done' AND called_at IS NOT NULL AND called_at > created_at;

  SELECT json_agg(json_build_object('visit_type', visit_type, 'count', cnt) ORDER BY cnt DESC)
  INTO v_visit_type_dist FROM (
    SELECT COALESCE(visit_type, 'general') AS visit_type, COUNT(*) AS cnt
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
    GROUP BY 1
  ) t;

  SELECT json_agg(json_build_object('hour', hour, 'count', cnt) ORDER BY hour)
  INTO v_peak_hours FROM (
    SELECT EXTRACT(HOUR FROM created_at)::INT AS hour, COUNT(*) AS cnt
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
    GROUP BY 1
  ) t;

  SELECT json_agg(json_build_object('date', queue_date, 'total', total, 'done', done) ORDER BY queue_date)
  INTO v_daily_totals FROM (
    SELECT queue_date,
           COUNT(*) AS total,
           COUNT(*) FILTER (WHERE status = 'done') AS done
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
    GROUP BY queue_date
  ) t;

  SELECT json_agg(json_build_object('reason', reason, 'count', cnt) ORDER BY cnt DESC)
  INTO v_top_reasons FROM (
    SELECT reason, COUNT(*) AS cnt FROM public.queue_entries
    WHERE hospital_id = p_hospital_id AND queue_date BETWEEN p_date_from AND p_date_to
      AND reason IS NOT NULL AND reason != ''
    GROUP BY reason ORDER BY cnt DESC LIMIT 8
  ) t;

  RETURN json_build_object(
    'total_patients',  v_total_patients,
    'total_done',      v_total_done,
    'avg_wait_mins',   v_avg_wait_mins,
    'visit_type_dist', COALESCE(v_visit_type_dist, '[]'::JSON),
    'peak_hours',      COALESCE(v_peak_hours,       '[]'::JSON),
    'daily_totals',    COALESCE(v_daily_totals,     '[]'::JSON),
    'top_reasons',     COALESCE(v_top_reasons,      '[]'::JSON),
    'date_from',       p_date_from,
    'date_to',         p_date_to
  );
END;
$$;

-- ── get_patients ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_patients(
  p_hospital_id UUID,
  p_date_from   DATE    DEFAULT NULL,
  p_date_to     DATE    DEFAULT NULL,
  p_search      TEXT    DEFAULT NULL,
  p_limit       INT     DEFAULT 50,
  p_offset      INT     DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patients JSON;
  v_total    INT;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT COUNT(DISTINCT patient_phone) INTO v_total FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND (p_date_from IS NULL OR queue_date >= p_date_from)
    AND (p_date_to   IS NULL OR queue_date <= p_date_to)
    AND (p_search IS NULL OR
         patient_name  ILIKE '%' || p_search || '%' OR
         patient_phone ILIKE '%' || p_search || '%');

  SELECT json_agg(json_build_object(
    'patient_phone', patient_phone,
    'patient_name',  (array_agg(patient_name ORDER BY created_at DESC))[1],
    'visit_count',   COUNT(*),
    'last_visit',    MAX(queue_date),
    'first_visit',   MIN(queue_date),
    'last_reason',   (array_agg(reason ORDER BY created_at DESC))[1],
    'last_token',    (array_agg(token_number ORDER BY created_at DESC))[1],
    'is_returning',  COUNT(*) > 1
  ) ORDER BY MAX(queue_date) DESC) INTO v_patients
  FROM (
    SELECT * FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND (p_date_from IS NULL OR queue_date >= p_date_from)
      AND (p_date_to   IS NULL OR queue_date <= p_date_to)
      AND (p_search IS NULL OR
           patient_name  ILIKE '%' || p_search || '%' OR
           patient_phone ILIKE '%' || p_search || '%')
    GROUP BY patient_phone
    ORDER BY MAX(queue_date) DESC
    LIMIT p_limit OFFSET p_offset
  ) grouped_entries;

  RETURN json_build_object(
    'patients', COALESCE(v_patients, '[]'::JSON),
    'total',    v_total,
    'limit',    p_limit,
    'offset',   p_offset
  );
END;
$$;

-- ── get_patient_history ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_patient_history(
  p_hospital_id   UUID,
  p_patient_phone TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visits JSON;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT json_agg(json_build_object(
    'id',           id,
    'token_number', token_number,
    'queue_date',   queue_date,
    'reason',       reason,
    'visit_type',   visit_type,
    'status',       status,
    'created_at',   created_at
  ) ORDER BY created_at DESC) INTO v_visits
  FROM public.queue_entries
  WHERE hospital_id   = p_hospital_id
    AND patient_phone = p_patient_phone;

  RETURN json_build_object('visits', COALESCE(v_visits, '[]'::JSON));
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 16: Grants
-- ─────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.get_my_hospital()                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_hospital_users(UUID)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_staff(UUID, TEXT, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_staff_active(UUID, BOOLEAN)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_staff_role(UUID, TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.call_next_token(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_token(UUID)                            TO authenticated;
GRANT EXECUTE ON FUNCTION public.skip_token(UUID)                                TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_queue_today(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_queue_today(UUID)                           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_analytics(UUID, DATE, DATE)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patients(UUID, DATE, DATE, TEXT, INT, INT)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_history(UUID, TEXT)                 TO authenticated;
