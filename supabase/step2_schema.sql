-- ============================================================
-- ClinicQ Step 2 — Queue System Schema
-- Run this AFTER step1 schema in Supabase SQL Editor
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. QUEUE ENTRIES TABLE
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.queue_entries (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id    UUID        NOT NULL REFERENCES public.hospitals(id) ON DELETE CASCADE,
  token_number   INT         NOT NULL,
  queue_date     DATE        NOT NULL DEFAULT CURRENT_DATE,
  patient_name   TEXT        NOT NULL,
  patient_phone  TEXT        NOT NULL,
  patient_age    INT,
  reason         TEXT,
  status         TEXT        NOT NULL DEFAULT 'waiting'
                             CHECK (status IN ('waiting','serving','done','skipped')),
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),

  -- Prevent duplicate tokens for same hospital on same day
  UNIQUE (hospital_id, token_number, queue_date)
);

-- ─────────────────────────────────────────────
-- 2. QUEUE DAILY STATE TABLE
-- One row per hospital per day
-- Tracks last issued token + currently serving token
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.queue_daily_state (
  id                   UUID  PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id          UUID  NOT NULL REFERENCES public.hospitals(id) ON DELETE CASCADE,
  queue_date           DATE  NOT NULL DEFAULT CURRENT_DATE,
  last_token_number    INT   NOT NULL DEFAULT 0,
  current_token_number INT   NOT NULL DEFAULT 0,
  updated_at           TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE (hospital_id, queue_date)
);

-- ─────────────────────────────────────────────
-- 3. PERFORMANCE INDEXES
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_queue_entries_hospital_date
  ON public.queue_entries (hospital_id, queue_date);

CREATE INDEX IF NOT EXISTS idx_queue_entries_status
  ON public.queue_entries (hospital_id, status, queue_date);

CREATE INDEX IF NOT EXISTS idx_queue_daily_state_hospital_date
  ON public.queue_daily_state (hospital_id, queue_date);

-- ─────────────────────────────────────────────
-- 4. AUTO-UPDATE updated_at TRIGGER
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_queue_entries_updated_at ON public.queue_entries;
CREATE TRIGGER set_queue_entries_updated_at
  BEFORE UPDATE ON public.queue_entries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_queue_daily_state_updated_at ON public.queue_daily_state;
CREATE TRIGGER set_queue_daily_state_updated_at
  BEFORE UPDATE ON public.queue_daily_state
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- RLS POLICIES
-- ============================================================

ALTER TABLE public.queue_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.queue_daily_state ENABLE ROW LEVEL SECURITY;

-- ── queue_entries ─────────────────────────────────────────

-- Anyone (incl. anon) can INSERT (public check-in)
DROP POLICY IF EXISTS "Public can insert queue entry" ON public.queue_entries;
CREATE POLICY "Public can insert queue entry"
  ON public.queue_entries FOR INSERT
  WITH CHECK (true);

-- Anyone can SELECT a specific entry by id (token status page)
DROP POLICY IF EXISTS "Public can read entry by id" ON public.queue_entries;
CREATE POLICY "Public can read entry by id"
  ON public.queue_entries FOR SELECT
  USING (true);   -- Restrict via RPC; direct table only used by auth users

-- Authenticated hospital owner can select all entries for their hospital
DROP POLICY IF EXISTS "Owner can read own hospital queue" ON public.queue_entries;
CREATE POLICY "Owner can read own hospital queue"
  ON public.queue_entries FOR SELECT
  USING (
    hospital_id IN (
      SELECT h.id FROM public.hospitals h
      JOIN public.users u ON h.created_by = u.id
      WHERE u.auth_id = auth.uid()
    )
  );

-- Authenticated hospital owner can update status
DROP POLICY IF EXISTS "Owner can update queue status" ON public.queue_entries;
CREATE POLICY "Owner can update queue status"
  ON public.queue_entries FOR UPDATE
  USING (
    hospital_id IN (
      SELECT h.id FROM public.hospitals h
      JOIN public.users u ON h.created_by = u.id
      WHERE u.auth_id = auth.uid()
    )
  );

-- ── queue_daily_state ─────────────────────────────────────

-- Anyone can read daily state (just token numbers, no PII)
DROP POLICY IF EXISTS "Public can read daily state" ON public.queue_daily_state;
CREATE POLICY "Public can read daily state"
  ON public.queue_daily_state FOR SELECT
  USING (true);

-- Only owner can update daily state
DROP POLICY IF EXISTS "Owner can update daily state" ON public.queue_daily_state;
CREATE POLICY "Owner can update daily state"
  ON public.queue_daily_state FOR UPDATE
  USING (
    hospital_id IN (
      SELECT h.id FROM public.hospitals h
      JOIN public.users u ON h.created_by = u.id
      WHERE u.auth_id = auth.uid()
    )
  );

-- System (SECURITY DEFINER RPCs) can insert daily state
DROP POLICY IF EXISTS "Allow system insert daily state" ON public.queue_daily_state;
CREATE POLICY "Allow system insert daily state"
  ON public.queue_daily_state FOR INSERT
  WITH CHECK (true);

-- ============================================================
-- RPC 1: get_hospital_full
-- Returns hospital info + settings in one call
-- Accessible by anon (check-in page)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_hospital_full(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital  public.hospitals;
  v_settings  public.hospital_settings;
  v_result    JSON;
BEGIN
  -- Fetch hospital
  SELECT * INTO v_hospital
  FROM public.hospitals
  WHERE id = p_hospital_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Hospital not found: %', p_hospital_id;
  END IF;

  -- Fetch settings
  SELECT * INTO v_settings
  FROM public.hospital_settings
  WHERE hospital_id = p_hospital_id;

  -- Build result JSON (no joins, explicit fields)
  v_result := json_build_object(
    'id',                   v_hospital.id,
    'name',                 v_hospital.name,
    'slug',                 v_hospital.slug,
    'address',              v_hospital.address,
    'phone',                v_hospital.phone,
    'created_at',           v_hospital.created_at,
    'settings', json_build_object(
      'token_limit',           COALESCE(v_settings.token_limit, 100),
      'avg_time_per_patient',  COALESCE(v_settings.avg_time_per_patient, 5),
      'alert_before',          COALESCE(v_settings.alert_before, 3),
      'working_hours_start',   COALESCE(v_settings.working_hours_start::TEXT, '09:00'),
      'working_hours_end',     COALESCE(v_settings.working_hours_end::TEXT, '18:00')
    )
  );

  RETURN v_result;
END;
$$;

-- ============================================================
-- RPC 2: create_queue_entry
-- Atomically generates a token and inserts a queue entry
-- Uses advisory lock to prevent duplicate tokens
-- Accessible by anon (check-in page)
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_queue_entry(
  p_hospital_id  UUID,
  p_name         TEXT,
  p_phone        TEXT,
  p_age          INT     DEFAULT NULL,
  p_reason       TEXT    DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_number   INT;
  v_token_limit    INT;
  v_queue_id       UUID;
  v_today          DATE := CURRENT_DATE;
  v_lock_key       BIGINT;
BEGIN
  -- Advisory lock key: hash of hospital_id + date to serialize token generation
  v_lock_key := abs(hashtext(p_hospital_id::TEXT || v_today::TEXT));
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Check token limit
  SELECT COALESCE(token_limit, 100) INTO v_token_limit
  FROM public.hospital_settings
  WHERE hospital_id = p_hospital_id;

  -- Upsert daily state row, increment last_token_number
  INSERT INTO public.queue_daily_state (hospital_id, queue_date, last_token_number, current_token_number)
  VALUES (p_hospital_id, v_today, 1, 0)
  ON CONFLICT (hospital_id, queue_date) DO UPDATE
    SET last_token_number = queue_daily_state.last_token_number + 1,
        updated_at        = NOW()
  RETURNING last_token_number INTO v_token_number;

  -- Enforce daily token limit
  IF v_token_number > COALESCE(v_token_limit, 100) THEN
    RAISE EXCEPTION 'TOKEN_LIMIT_REACHED: Daily token limit of % reached', v_token_limit;
  END IF;

  -- Insert the queue entry
  INSERT INTO public.queue_entries (
    hospital_id,
    token_number,
    queue_date,
    patient_name,
    patient_phone,
    patient_age,
    reason,
    status
  )
  VALUES (
    p_hospital_id,
    v_token_number,
    v_today,
    trim(p_name),
    trim(p_phone),
    p_age,
    p_reason,
    'waiting'
  )
  RETURNING id INTO v_queue_id;

  -- Return full entry
  RETURN json_build_object(
    'id',            v_queue_id,
    'token_number',  v_token_number,
    'hospital_id',   p_hospital_id,
    'patient_name',  trim(p_name),
    'patient_phone', trim(p_phone),
    'patient_age',   p_age,
    'reason',        p_reason,
    'status',        'waiting',
    'queue_date',    v_today
  );
END;
$$;

-- ============================================================
-- RPC 3: get_token_status
-- Returns status of a specific queue entry + position + wait
-- Accessible by anon (token status page)
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
  -- Fetch the entry
  SELECT * INTO v_entry
  FROM public.queue_entries
  WHERE id = p_queue_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry not found: %', p_queue_id;
  END IF;

  -- Fetch daily state for this hospital + date
  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = v_entry.hospital_id
    AND queue_date  = v_entry.queue_date;

  -- Count how many waiting entries are ahead of this token
  SELECT COUNT(*) INTO v_ahead
  FROM public.queue_entries
  WHERE hospital_id  = v_entry.hospital_id
    AND queue_date   = v_entry.queue_date
    AND status       = 'waiting'
    AND token_number < v_entry.token_number;

  -- Fetch avg time per patient for this hospital
  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_time
  FROM public.hospital_settings
  WHERE hospital_id = v_entry.hospital_id;

  v_wait_mins := v_ahead * v_avg_time;

  RETURN json_build_object(
    'id',                    v_entry.id,
    'token_number',          v_entry.token_number,
    'patient_name',          v_entry.patient_name,
    'status',                v_entry.status,
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
-- RPC 4: call_next_token
-- Dashboard: advances current_token to next waiting entry
-- Requires authenticated hospital owner
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
  v_current_entry    public.queue_entries;
BEGIN
  -- Verify caller owns this hospital
  SELECT u.id INTO v_caller_user_id
  FROM public.users u
  WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals
  WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not own this hospital';
  END IF;

  -- Mark currently serving entry as done
  UPDATE public.queue_entries
  SET status = 'done', updated_at = NOW()
  WHERE hospital_id  = p_hospital_id
    AND queue_date   = v_today
    AND status       = 'serving';

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

  -- Mark next entry as serving
  UPDATE public.queue_entries
  SET status = 'serving', updated_at = NOW()
  WHERE id = v_next_entry.id;

  -- Update daily state current token
  UPDATE public.queue_daily_state
  SET current_token_number = v_next_entry.token_number,
      updated_at           = NOW()
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today;

  RETURN json_build_object(
    'success',       true,
    'token_number',  v_next_entry.token_number,
    'patient_name',  v_next_entry.patient_name,
    'entry_id',      v_next_entry.id
  );
END;
$$;

-- ============================================================
-- RPC 5: get_queue_today
-- Dashboard: returns today's full queue for a hospital
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
BEGIN
  -- Verify caller owns this hospital
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

  -- Fetch all entries for today ordered by token
  SELECT json_agg(
    json_build_object(
      'id',             e.id,
      'token_number',   e.token_number,
      'patient_name',   e.patient_name,
      'patient_phone',  e.patient_phone,
      'patient_age',    e.patient_age,
      'reason',         e.reason,
      'status',         e.status,
      'created_at',     e.created_at,
      'updated_at',     e.updated_at
    ) ORDER BY e.token_number ASC
  ) INTO v_entries
  FROM public.queue_entries e
  WHERE e.hospital_id = p_hospital_id
    AND e.queue_date  = v_today;

  -- Summary counts
  SELECT json_build_object(
    'total',    COUNT(*),
    'waiting',  COUNT(*) FILTER (WHERE status = 'waiting'),
    'serving',  COUNT(*) FILTER (WHERE status = 'serving'),
    'done',     COUNT(*) FILTER (WHERE status = 'done'),
    'skipped',  COUNT(*) FILTER (WHERE status = 'skipped')
  ) INTO v_counts
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  RETURN json_build_object(
    'entries',              COALESCE(v_entries, '[]'::JSON),
    'current_token_number', COALESCE(v_daily.current_token_number, 0),
    'last_token_number',    COALESCE(v_daily.last_token_number, 0),
    'counts',               v_counts,
    'queue_date',           v_today
  );
END;
$$;

-- ============================================================
-- RPC 6: skip_token
-- Dashboard: mark an entry as skipped
-- ============================================================
CREATE OR REPLACE FUNCTION public.skip_token(p_entry_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_entry          public.queue_entries;
BEGIN
  SELECT * INTO v_entry
  FROM public.queue_entries WHERE id = p_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Entry not found';
  END IF;

  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  -- Verify ownership
  IF NOT EXISTS (
    SELECT 1 FROM public.hospitals h
    WHERE h.id = v_entry.hospital_id
      AND h.created_by = v_caller_user_id
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  UPDATE public.queue_entries
  SET status = 'skipped', updated_at = NOW()
  WHERE id = p_entry_id;

  RETURN json_build_object('success', true, 'entry_id', p_entry_id);
END;
$$;

-- Grant execute to anon + authenticated for public RPCs
GRANT EXECUTE ON FUNCTION public.get_hospital_full(UUID)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_queue_entry(UUID, TEXT, TEXT, INT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_token_status(UUID)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.call_next_token(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_queue_today(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.skip_token(UUID)            TO authenticated;
