-- ============================================================
-- ClinicQ Step 4 — Fix get_queue_today RPC
-- Run this AFTER schema1, schema2, schema3 in Supabase SQL Editor
--
-- Fixes:
--   1. hospital_id was missing from entries JSON (caused crash)
--   2. counts key was 'serving' but Flutter expects 'in_progress'
--   3. Added missing fields: total_served, avg_actual_wait, avg_time_setting
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
  v_avg_time       INT;
  v_total_served   INT;
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

  -- Fetch avg time setting
  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_time
  FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  -- Fetch all entries (fix: hospital_id now included)
  SELECT json_agg(
    json_build_object(
      'id',            e.id,
      'hospital_id',   e.hospital_id,
      'token_number',  e.token_number,
      'patient_name',  e.patient_name,
      'patient_phone', e.patient_phone,
      'patient_age',   e.patient_age,
      'reason',        e.reason,
      'status',        e.status,
      'created_at',    e.created_at,
      'updated_at',    e.updated_at
    ) ORDER BY e.token_number ASC
  ) INTO v_entries
  FROM public.queue_entries e
  WHERE e.hospital_id = p_hospital_id AND e.queue_date = v_today;

  -- Summary counts (fix: key is 'in_progress' to match Flutter model)
  SELECT json_build_object(
    'total',       COUNT(*),
    'waiting',     COUNT(*) FILTER (WHERE status = 'waiting'),
    'in_progress', COUNT(*) FILTER (WHERE status = 'serving'),
    'done',        COUNT(*) FILTER (WHERE status = 'done'),
    'skipped',     COUNT(*) FILTER (WHERE status = 'skipped')
  ) INTO v_counts
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  -- Total served today
  SELECT COUNT(*) INTO v_total_served
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status IN ('done', 'serving');

  RETURN json_build_object(
    'entries',              COALESCE(v_entries, '[]'::JSON),
    'current_token_number', COALESCE(v_daily.current_token_number, 0),
    'last_token_number',    COALESCE(v_daily.last_token_number, 0),
    'total_served',         COALESCE(v_total_served, 0),
    'avg_actual_wait',      0,
    'avg_time_setting',     COALESCE(v_avg_time, 5),
    'counts',               v_counts,
    'queue_date',           v_today
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_queue_today(UUID) TO authenticated;
