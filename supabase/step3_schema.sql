-- ============================================================
-- ClinicQ Step 3 — Queue Logic, Realtime & Settings
-- Run AFTER step1_schema.sql and step2_schema.sql
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- PART 1: Add 'in_progress' status to queue_entries
--
-- Flow: waiting → in_progress → done
--       waiting → skipped
--
-- 'in_progress' = doctor has called this patient, they are
--                 currently being seen (replaces 'serving')
-- ─────────────────────────────────────────────────────────

-- Drop the old constraint and add the updated one
ALTER TABLE public.queue_entries
  DROP CONSTRAINT IF EXISTS queue_entries_status_check;

ALTER TABLE public.queue_entries
  ADD CONSTRAINT queue_entries_status_check
  CHECK (status IN ('waiting', 'in_progress', 'serving', 'done', 'skipped'));

-- Migrate existing 'serving' rows → 'in_progress'
UPDATE public.queue_entries SET status = 'in_progress' WHERE status = 'serving';

-- ─────────────────────────────────────────────────────────
-- PART 2: Add called_at / completed_at timestamps
-- ─────────────────────────────────────────────────────────
ALTER TABLE public.queue_entries
  ADD COLUMN IF NOT EXISTS called_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- ─────────────────────────────────────────────────────────
-- PART 3: avg_wait_mins column in queue_daily_state
-- ─────────────────────────────────────────────────────────
ALTER TABLE public.queue_daily_state
  ADD COLUMN IF NOT EXISTS total_served      INT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS avg_actual_wait   INT  NOT NULL DEFAULT 0; -- minutes

-- ============================================================
-- RPC: complete_token
-- Mark the in_progress patient as done WITHOUT calling next.
-- Doctor uses this when they want manual control.
-- ============================================================
CREATE OR REPLACE FUNCTION public.complete_token(p_entry_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_entry          public.queue_entries;
  v_wait_mins      INT;
BEGIN
  SELECT * INTO v_entry
  FROM public.queue_entries WHERE id = p_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry not found';
  END IF;

  -- Verify ownership
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  IF NOT EXISTS (
    SELECT 1 FROM public.hospitals h
    WHERE h.id = v_entry.hospital_id
      AND h.created_by = v_caller_user_id
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Only in_progress (or waiting) entries can be completed
  IF v_entry.status NOT IN ('in_progress', 'waiting', 'serving') THEN
    RAISE EXCEPTION 'Cannot complete entry with status: %', v_entry.status;
  END IF;

  -- Calculate actual wait time if we have called_at
  IF v_entry.called_at IS NOT NULL THEN
    v_wait_mins := EXTRACT(EPOCH FROM (NOW() - v_entry.called_at)) / 60;
  END IF;

  -- Mark as done
  UPDATE public.queue_entries
  SET
    status       = 'done',
    completed_at = NOW(),
    updated_at   = NOW()
  WHERE id = p_entry_id;

  -- Update daily stats
  UPDATE public.queue_daily_state
  SET
    total_served    = total_served + 1,
    avg_actual_wait = CASE
      WHEN total_served = 0 THEN COALESCE(v_wait_mins, 0)
      ELSE (avg_actual_wait * total_served + COALESCE(v_wait_mins, 0)) / (total_served + 1)
    END,
    updated_at = NOW()
  WHERE hospital_id = v_entry.hospital_id
    AND queue_date  = v_entry.queue_date;

  RETURN json_build_object(
    'success',    true,
    'entry_id',   p_entry_id,
    'wait_mins',  COALESCE(v_wait_mins, 0)
  );
END;
$$;

-- ============================================================
-- RPC: call_next_token (UPDATED)
-- Now sets status = 'in_progress' (not 'serving')
-- Also marks called_at timestamp
-- ============================================================
CREATE OR REPLACE FUNCTION public.call_next_token(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id   UUID;
  v_hospital_owner   UUID;
  v_today            DATE := CURRENT_DATE;
  v_next_entry       public.queue_entries;
BEGIN
  -- Verify ownership
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not own this hospital';
  END IF;

  -- Mark current in_progress entry as done
  UPDATE public.queue_entries
  SET
    status       = 'done',
    completed_at = NOW(),
    updated_at   = NOW()
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      IN ('in_progress', 'serving');

  -- Update served count
  UPDATE public.queue_daily_state
  SET total_served = total_served + 1, updated_at = NOW()
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  -- Find next waiting entry (lowest token number)
  SELECT * INTO v_next_entry
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      = 'waiting'
  ORDER BY token_number ASC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'message', 'No more patients in queue'
    );
  END IF;

  -- Mark next entry as in_progress + stamp called_at
  UPDATE public.queue_entries
  SET
    status    = 'in_progress',
    called_at = NOW(),
    updated_at = NOW()
  WHERE id = v_next_entry.id;

  -- Update daily state current token
  INSERT INTO public.queue_daily_state
    (hospital_id, queue_date, current_token_number, last_token_number)
  VALUES (p_hospital_id, v_today, v_next_entry.token_number, v_next_entry.token_number)
  ON CONFLICT (hospital_id, queue_date) DO UPDATE
    SET current_token_number = v_next_entry.token_number,
        updated_at           = NOW();

  RETURN json_build_object(
    'success',       true,
    'token_number',  v_next_entry.token_number,
    'patient_name',  v_next_entry.patient_name,
    'patient_phone', v_next_entry.patient_phone,
    'entry_id',      v_next_entry.id
  );
END;
$$;

-- ============================================================
-- RPC: get_queue_today (UPDATED)
-- Now includes in_progress in counts + called_at/completed_at
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_queue_today(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_hospital_owner UUID;
  v_today          DATE := CURRENT_DATE;
  v_entries        JSON;
  v_daily          public.queue_daily_state;
  v_counts         JSON;
  v_avg_settings   INT;
BEGIN
  -- Verify ownership
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Fetch daily state
  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  -- Avg time from settings
  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_settings
  FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  -- All entries for today
  SELECT json_agg(
    json_build_object(
      'id',             e.id,
      'hospital_id',    e.hospital_id,
      'token_number',   e.token_number,
      'queue_date',     e.queue_date,
      'patient_name',   e.patient_name,
      'patient_phone',  e.patient_phone,
      'patient_age',    e.patient_age,
      'reason',         e.reason,
      'status',         e.status,
      'called_at',      e.called_at,
      'completed_at',   e.completed_at,
      'created_at',     e.created_at,
      'updated_at',     e.updated_at
    ) ORDER BY e.token_number ASC
  ) INTO v_entries
  FROM public.queue_entries e
  WHERE e.hospital_id = p_hospital_id AND e.queue_date = v_today;

  -- Counts including in_progress
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

-- ============================================================
-- RPC: get_token_status (UPDATED)
-- Now counts 'in_progress' as the current serving entry
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_token_status(p_queue_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry         public.queue_entries;
  v_daily         public.queue_daily_state;
  v_ahead         INT;
  v_wait_mins     INT;
  v_avg_time      INT;
BEGIN
  SELECT * INTO v_entry
  FROM public.queue_entries WHERE id = p_queue_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry not found: %', p_queue_id;
  END IF;

  -- Daily state
  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = v_entry.hospital_id AND queue_date = v_entry.queue_date;

  -- Count waiting entries ahead of this token
  SELECT COUNT(*) INTO v_ahead
  FROM public.queue_entries
  WHERE hospital_id  = v_entry.hospital_id
    AND queue_date   = v_entry.queue_date
    AND status       = 'waiting'
    AND token_number < v_entry.token_number;

  -- Avg time
  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_time
  FROM public.hospital_settings WHERE hospital_id = v_entry.hospital_id;

  v_wait_mins := v_ahead * v_avg_time;

  RETURN json_build_object(
    'id',                    v_entry.id,
    'token_number',          v_entry.token_number,
    'patient_name',          v_entry.patient_name,
    'status',                CASE
                               WHEN v_entry.status = 'in_progress' THEN 'serving'
                               ELSE v_entry.status
                             END,
    'reason',                v_entry.reason,
    'queue_date',            v_entry.queue_date,
    'hospital_id',           v_entry.hospital_id,
    'current_token_number',  COALESCE(v_daily.current_token_number, 0),
    'position_ahead',        v_ahead,
    'estimated_wait_mins',   v_wait_mins
  );
END;
$$;

-- ============================================================
-- RPC: get_queue_stats
-- Lightweight stats for a hospital — no auth needed (public)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_queue_stats(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today  DATE := CURRENT_DATE;
  v_daily  public.queue_daily_state;
  v_counts JSON;
  v_avg    INT;
BEGIN
  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT json_build_object(
    'total',       COUNT(*),
    'waiting',     COUNT(*) FILTER (WHERE status = 'waiting'),
    'in_progress', COUNT(*) FILTER (WHERE status IN ('in_progress','serving')),
    'done',        COUNT(*) FILTER (WHERE status = 'done'),
    'skipped',     COUNT(*) FILTER (WHERE status = 'skipped')
  ) INTO v_counts
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg
  FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  RETURN json_build_object(
    'current_token_number', COALESCE(v_daily.current_token_number, 0),
    'last_token_number',    COALESCE(v_daily.last_token_number, 0),
    'total_served',         COALESCE(v_daily.total_served, 0),
    'avg_actual_wait',      COALESCE(v_daily.avg_actual_wait, 0),
    'avg_time_setting',     v_avg,
    'counts',               v_counts,
    'queue_date',           v_today
  );
END;
$$;

-- ============================================================
-- RPC: update_hospital_settings
-- Authenticated — only hospital owner can update
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_hospital_settings(
  p_hospital_id          UUID,
  p_token_limit          INT     DEFAULT NULL,
  p_avg_time_per_patient INT     DEFAULT NULL,
  p_alert_before         INT     DEFAULT NULL,
  p_working_hours_start  TEXT    DEFAULT NULL,
  p_working_hours_end    TEXT    DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_hospital_owner UUID;
BEGIN
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Validate values
  IF p_token_limit IS NOT NULL AND (p_token_limit < 1 OR p_token_limit > 500) THEN
    RAISE EXCEPTION 'token_limit must be between 1 and 500';
  END IF;
  IF p_avg_time_per_patient IS NOT NULL AND (p_avg_time_per_patient < 1 OR p_avg_time_per_patient > 120) THEN
    RAISE EXCEPTION 'avg_time_per_patient must be between 1 and 120 minutes';
  END IF;

  INSERT INTO public.hospital_settings (hospital_id)
  VALUES (p_hospital_id)
  ON CONFLICT (hospital_id) DO NOTHING;

  UPDATE public.hospital_settings SET
    token_limit          = COALESCE(p_token_limit,          token_limit),
    avg_time_per_patient = COALESCE(p_avg_time_per_patient, avg_time_per_patient),
    alert_before         = COALESCE(p_alert_before,         alert_before),
    working_hours_start  = COALESCE(p_working_hours_start::TIME, working_hours_start),
    working_hours_end    = COALESCE(p_working_hours_end::TIME,   working_hours_end)
  WHERE hospital_id = p_hospital_id;

  RETURN json_build_object('success', true, 'hospital_id', p_hospital_id);
END;
$$;

-- ============================================================
-- RPC: reset_queue_today
-- Clear all today's queue entries for a hospital (hard reset)
-- ============================================================
CREATE OR REPLACE FUNCTION public.reset_queue_today(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_hospital_owner UUID;
  v_today          DATE := CURRENT_DATE;
  v_deleted        INT;
BEGIN
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  DELETE FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Reset daily state
  UPDATE public.queue_daily_state SET
    last_token_number    = 0,
    current_token_number = 0,
    total_served         = 0,
    avg_actual_wait      = 0,
    updated_at           = NOW()
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  RETURN json_build_object(
    'success',         true,
    'entries_deleted', v_deleted
  );
END;
$$;

-- ============================================================
-- GRANT permissions for new RPCs
-- ============================================================
GRANT EXECUTE ON FUNCTION public.complete_token(UUID)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_queue_stats(UUID)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_hospital_settings(UUID, INT, INT, INT, TEXT, TEXT)
                                                                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_queue_today(UUID)         TO authenticated;

-- Re-grant updated RPCs
GRANT EXECUTE ON FUNCTION public.call_next_token(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_queue_today(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_token_status(UUID)          TO anon, authenticated;
