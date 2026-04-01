-- ============================================================
-- ClinicQ Step 5 — TV Display + Analytics + Patient Management
-- Run AFTER step1–step4 schemas
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- PART 1: Extend queue_entries with visit_type + served_at
-- ─────────────────────────────────────────────────────────

ALTER TABLE public.queue_entries
  ADD COLUMN IF NOT EXISTS visit_type TEXT
    CHECK (visit_type IN ('first_visit','follow_up','emergency','general') OR visit_type IS NULL),
  ADD COLUMN IF NOT EXISTS served_at  TIMESTAMPTZ;

-- Index for analytics queries
CREATE INDEX IF NOT EXISTS idx_queue_entries_visit_type
  ON public.queue_entries (hospital_id, visit_type, queue_date);

CREATE INDEX IF NOT EXISTS idx_queue_entries_phone
  ON public.queue_entries (hospital_id, patient_phone);

-- ─────────────────────────────────────────────────────────
-- PART 2: TV Display RPC
-- Public — accessible by anon (TV screen is unauthenticated)
-- Returns current serving + next 5 waiting + stats
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_tv_display(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today         DATE := CURRENT_DATE;
  v_hospital      public.hospitals;
  v_settings      public.hospital_settings;
  v_daily         public.queue_daily_state;
  v_current       public.queue_entries;
  v_next_tokens   JSON;
  v_total_waiting INT;
  v_total_done    INT;
  v_avg_wait      INT;
  v_more_count    INT;
BEGIN
  -- Hospital name
  SELECT * INTO v_hospital FROM public.hospitals WHERE id = p_hospital_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Hospital not found'; END IF;

  -- Settings for avg time
  SELECT * INTO v_settings FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  -- Daily state
  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  -- Current in_progress entry
  SELECT * INTO v_current
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      IN ('in_progress', 'serving')
  LIMIT 1;

  -- Count waiting
  SELECT COUNT(*) INTO v_total_waiting
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      = 'waiting';

  -- Count done
  SELECT COUNT(*) INTO v_total_done
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      = 'done';

  -- More waiting beyond top 5
  v_more_count := GREATEST(0, v_total_waiting - 5);

  -- Next 5 waiting tokens (ordered by token_number)
  SELECT json_agg(
    json_build_object(
      'id',           e.id,
      'token_number', e.token_number,
      'patient_name', e.patient_name,
      'reason',       e.reason,
      'visit_type',   e.visit_type,
      'created_at',   e.created_at
    ) ORDER BY e.token_number ASC
  ) INTO v_next_tokens
  FROM (
    SELECT * FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND queue_date  = v_today
      AND status      = 'waiting'
    ORDER BY token_number ASC
    LIMIT 5
  ) e;

  -- Avg wait (use actual or settings-based)
  SELECT CASE
    WHEN COALESCE(v_daily.avg_actual_wait, 0) > 0 THEN v_daily.avg_actual_wait
    ELSE COALESCE(v_settings.avg_time_per_patient, 5)
  END INTO v_avg_wait;

  RETURN json_build_object(
    'hospital_name',        v_hospital.name,
    'hospital_address',     v_hospital.address,
    'current_token', CASE
      WHEN v_current IS NOT NULL THEN json_build_object(
        'id',           v_current.id,
        'token_number', v_current.token_number,
        'patient_name', v_current.patient_name,
        'reason',       v_current.reason
      )
      ELSE NULL
    END,
    'current_token_number', COALESCE(v_daily.current_token_number, 0),
    'next_tokens',          COALESCE(v_next_tokens, '[]'::JSON),
    'total_waiting',        v_total_waiting,
    'total_done',           v_total_done,
    'more_waiting',         v_more_count,
    'avg_wait_mins',        v_avg_wait,
    'queue_date',           v_today,
    'last_updated',         NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_tv_display(UUID) TO anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- PART 3: Analytics RPC
-- Authenticated — returns daily stats for the hospital
-- ─────────────────────────────────────────────────────────

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
  v_caller_user_id UUID;
  v_hospital_owner UUID;
  v_total_patients      INT;
  v_total_done          INT;
  v_avg_wait_mins       INT;
  v_visit_type_dist     JSON;
  v_peak_hours          JSON;
  v_daily_totals        JSON;
  v_top_reasons         JSON;
BEGIN
  -- Ownership check
  SELECT u.id INTO v_caller_user_id FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT created_by INTO v_hospital_owner FROM public.hospitals WHERE id = p_hospital_id;
  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Total patients in range
  SELECT COUNT(*) INTO v_total_patients
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date BETWEEN p_date_from AND p_date_to;

  -- Total completed
  SELECT COUNT(*) INTO v_total_done
  FROM public.queue_entries
  WHERE hospital_id  = p_hospital_id
    AND queue_date   BETWEEN p_date_from AND p_date_to
    AND status       = 'done';

  -- Average actual wait time (called_at - created_at) for done entries that have called_at
  SELECT COALESCE(
    ROUND(AVG(EXTRACT(EPOCH FROM (called_at - created_at)) / 60))::INT,
    0
  ) INTO v_avg_wait_mins
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  BETWEEN p_date_from AND p_date_to
    AND status      = 'done'
    AND called_at   IS NOT NULL
    AND called_at   > created_at;

  -- Visit type distribution
  SELECT json_agg(json_build_object(
    'visit_type', COALESCE(visit_type, 'general'),
    'count',      cnt
  ) ORDER BY cnt DESC) INTO v_visit_type_dist
  FROM (
    SELECT COALESCE(visit_type, 'general') AS visit_type, COUNT(*) AS cnt
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND queue_date  BETWEEN p_date_from AND p_date_to
    GROUP BY COALESCE(visit_type, 'general')
  ) t;

  -- Peak hours (count of registrations per hour 0-23)
  SELECT json_agg(json_build_object(
    'hour',  hour_of_day,
    'count', cnt
  ) ORDER BY hour_of_day) INTO v_peak_hours
  FROM (
    SELECT EXTRACT(HOUR FROM created_at AT TIME ZONE 'Asia/Kolkata')::INT AS hour_of_day,
           COUNT(*) AS cnt
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND queue_date  BETWEEN p_date_from AND p_date_to
    GROUP BY EXTRACT(HOUR FROM created_at AT TIME ZONE 'Asia/Kolkata')::INT
  ) t;

  -- Daily totals (for trend line)
  SELECT json_agg(json_build_object(
    'date',    queue_date,
    'total',   total,
    'done',    done_count
  ) ORDER BY queue_date) INTO v_daily_totals
  FROM (
    SELECT queue_date,
           COUNT(*)                                     AS total,
           COUNT(*) FILTER (WHERE status = 'done')     AS done_count
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND queue_date  BETWEEN p_date_from AND p_date_to
    GROUP BY queue_date
  ) t;

  -- Top reasons
  SELECT json_agg(json_build_object(
    'reason', reason,
    'count',  cnt
  ) ORDER BY cnt DESC) INTO v_top_reasons
  FROM (
    SELECT COALESCE(reason, 'Not specified') AS reason, COUNT(*) AS cnt
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND queue_date  BETWEEN p_date_from AND p_date_to
      AND reason IS NOT NULL AND reason != ''
    GROUP BY reason
    ORDER BY cnt DESC
    LIMIT 8
  ) t;

  RETURN json_build_object(
    'total_patients',   v_total_patients,
    'total_done',       v_total_done,
    'avg_wait_mins',    v_avg_wait_mins,
    'visit_type_dist',  COALESCE(v_visit_type_dist,  '[]'::JSON),
    'peak_hours',       COALESCE(v_peak_hours,        '[]'::JSON),
    'daily_totals',     COALESCE(v_daily_totals,      '[]'::JSON),
    'top_reasons',      COALESCE(v_top_reasons,       '[]'::JSON),
    'date_from',        p_date_from,
    'date_to',          p_date_to
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_analytics(UUID, DATE, DATE) TO authenticated;

-- ─────────────────────────────────────────────────────────
-- PART 4: Patient Management RPC
-- Returns grouped patient history
-- ─────────────────────────────────────────────────────────

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
  v_caller_user_id UUID;
  v_hospital_owner UUID;
  v_patients       JSON;
  v_total          INT;
BEGIN
  SELECT u.id INTO v_caller_user_id FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT created_by INTO v_hospital_owner FROM public.hospitals WHERE id = p_hospital_id;
  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Total count
  SELECT COUNT(DISTINCT patient_phone) INTO v_total
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND (p_date_from IS NULL OR queue_date >= p_date_from)
    AND (p_date_to   IS NULL OR queue_date <= p_date_to)
    AND (p_search    IS NULL OR
         patient_name  ILIKE '%' || p_search || '%' OR
         patient_phone ILIKE '%' || p_search || '%');

  -- Grouped patient records
  SELECT json_agg(json_build_object(
    'patient_phone',   patient_phone,
    'patient_name',    last_name,
    'visit_count',     visit_count,
    'last_visit',      last_visit,
    'first_visit',     first_visit,
    'last_reason',     last_reason,
    'last_token',      last_token,
    'is_returning',    visit_count > 1
  ) ORDER BY last_visit DESC)
  INTO v_patients
  FROM (
    SELECT
      patient_phone,
      (array_agg(patient_name ORDER BY created_at DESC))[1] AS last_name,
      COUNT(*)                                               AS visit_count,
      MAX(queue_date)                                        AS last_visit,
      MIN(queue_date)                                        AS first_visit,
      (array_agg(reason ORDER BY created_at DESC))[1]       AS last_reason,
      (array_agg(token_number ORDER BY created_at DESC))[1] AS last_token
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND (p_date_from IS NULL OR queue_date >= p_date_from)
      AND (p_date_to   IS NULL OR queue_date <= p_date_to)
      AND (p_search    IS NULL OR
           patient_name  ILIKE '%' || p_search || '%' OR
           patient_phone ILIKE '%' || p_search || '%')
    GROUP BY patient_phone
    ORDER BY MAX(queue_date) DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'patients', COALESCE(v_patients, '[]'::JSON),
    'total',    v_total,
    'limit',    p_limit,
    'offset',   p_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_patients(UUID, DATE, DATE, TEXT, INT, INT) TO authenticated;

-- ─────────────────────────────────────────────────────────
-- PART 5: Patient visit history RPC
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_patient_history(
  p_hospital_id  UUID,
  p_patient_phone TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_user_id UUID;
  v_hospital_owner UUID;
  v_visits         JSON;
BEGIN
  SELECT u.id INTO v_caller_user_id FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT created_by INTO v_hospital_owner FROM public.hospitals WHERE id = p_hospital_id;
  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
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

  RETURN json_build_object(
    'phone',   p_patient_phone,
    'visits',  COALESCE(v_visits, '[]'::JSON)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_patient_history(UUID, TEXT) TO authenticated;