-- ============================================================
-- ClinicQ Schema 8 — Token format fields in public RPCs
-- Run AFTER schema7.sql
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- PART 1: Add token format columns to hospital_settings
--         (safe — ignored if already present)
-- ─────────────────────────────────────────────────────────

ALTER TABLE public.hospital_settings
  ADD COLUMN IF NOT EXISTS token_prefix  TEXT    NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS token_format  TEXT    NOT NULL DEFAULT 'numeric'
    CHECK (token_format IN ('numeric', 'prefix', 'custom')),
  ADD COLUMN IF NOT EXISTS token_padding INT     NOT NULL DEFAULT 2;

-- ─────────────────────────────────────────────────────────
-- PART 2: update_hospital_settings — add token format params
-- Drop old overloaded signatures first so CREATE OR REPLACE
-- is unambiguous (step3_schema had 6 params, schema5 had 9).
-- ─────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.update_hospital_settings(UUID, INT, INT, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_hospital_settings(UUID, INT, INT, INT, TEXT, TEXT, BOOLEAN, BOOLEAN, JSONB);

CREATE OR REPLACE FUNCTION public.update_hospital_settings(
  p_hospital_id          UUID,
  p_token_limit          INT     DEFAULT NULL,
  p_avg_time_per_patient INT     DEFAULT NULL,
  p_alert_before         INT     DEFAULT NULL,
  p_working_hours_start  TEXT    DEFAULT NULL,
  p_working_hours_end    TEXT    DEFAULT NULL,
  p_enable_age           BOOLEAN DEFAULT NULL,
  p_enable_reason        BOOLEAN DEFAULT NULL,
  p_custom_fields        JSONB   DEFAULT NULL,
  p_token_prefix         TEXT    DEFAULT NULL,
  p_token_format         TEXT    DEFAULT NULL,
  p_token_padding        INT     DEFAULT NULL
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

  IF p_token_limit IS NOT NULL AND (p_token_limit < 1 OR p_token_limit > 500) THEN
    RAISE EXCEPTION 'token_limit must be between 1 and 500';
  END IF;

  IF p_avg_time_per_patient IS NOT NULL AND
     (p_avg_time_per_patient < 1 OR p_avg_time_per_patient > 120) THEN
    RAISE EXCEPTION 'avg_time_per_patient must be between 1 and 120';
  END IF;

  IF p_custom_fields IS NOT NULL AND jsonb_typeof(p_custom_fields) != 'array' THEN
    RAISE EXCEPTION 'custom_fields must be a JSON array';
  END IF;

  IF p_token_format IS NOT NULL AND p_token_format NOT IN ('numeric','prefix','custom') THEN
    RAISE EXCEPTION 'token_format must be numeric, prefix, or custom';
  END IF;

  INSERT INTO public.hospital_settings (hospital_id)
  VALUES (p_hospital_id)
  ON CONFLICT (hospital_id) DO NOTHING;

  UPDATE public.hospital_settings SET
    token_limit          = COALESCE(p_token_limit,          token_limit),
    avg_time_per_patient = COALESCE(p_avg_time_per_patient, avg_time_per_patient),
    alert_before         = COALESCE(p_alert_before,         alert_before),
    working_hours_start  = COALESCE(p_working_hours_start::TIME, working_hours_start),
    working_hours_end    = COALESCE(p_working_hours_end::TIME,   working_hours_end),
    enable_age           = COALESCE(p_enable_age,           enable_age),
    enable_reason        = COALESCE(p_enable_reason,        enable_reason),
    custom_fields        = COALESCE(p_custom_fields,        custom_fields),
    token_prefix         = COALESCE(p_token_prefix,         token_prefix),
    token_format         = COALESCE(p_token_format,         token_format),
    token_padding        = COALESCE(p_token_padding,        token_padding)
  WHERE hospital_id = p_hospital_id;

  RETURN (SELECT json_build_object(
    'success',        true,
    'hospital_id',    p_hospital_id,
    'token_prefix',   token_prefix,
    'token_format',   token_format,
    'token_padding',  token_padding
  ) FROM public.hospital_settings WHERE hospital_id = p_hospital_id);
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 3: get_hospital_full — include token format fields
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_hospital_full(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital public.hospitals;
  v_settings public.hospital_settings;
BEGIN
  SELECT * INTO v_hospital FROM public.hospitals WHERE id = p_hospital_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT * INTO v_settings FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  RETURN json_build_object(
    'id',                   v_hospital.id,
    'name',                 v_hospital.name,
    'slug',                 v_hospital.slug,
    'address',              v_hospital.address,
    'phone',                v_hospital.phone,
    'settings', json_build_object(
      'token_limit',          COALESCE(v_settings.token_limit, 100),
      'avg_time_per_patient', COALESCE(v_settings.avg_time_per_patient, 5),
      'alert_before',         COALESCE(v_settings.alert_before, 3),
      'working_hours_start',  COALESCE(v_settings.working_hours_start::TEXT, '09:00'),
      'working_hours_end',    COALESCE(v_settings.working_hours_end::TEXT,   '18:00'),
      'enable_age',           COALESCE(v_settings.enable_age,    true),
      'enable_reason',        COALESCE(v_settings.enable_reason, true),
      'custom_fields',        COALESCE(v_settings.custom_fields, '[]'::JSONB),
      'token_prefix',         COALESCE(v_settings.token_prefix,  ''),
      'token_format',         COALESCE(v_settings.token_format,  'numeric'),
      'token_padding',        COALESCE(v_settings.token_padding, 2)
    )
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 4: get_tv_display — include token format fields
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
  SELECT * INTO v_hospital FROM public.hospitals WHERE id = p_hospital_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Hospital not found'; END IF;

  SELECT * INTO v_settings FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT * INTO v_current
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND queue_date  = v_today
    AND status      IN ('in_progress', 'serving')
  LIMIT 1;

  SELECT COUNT(*) INTO v_total_waiting
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today AND status = 'waiting';

  SELECT COUNT(*) INTO v_total_done
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id AND queue_date = v_today AND status = 'done';

  v_more_count := GREATEST(0, v_total_waiting - 5);

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
    'last_updated',         NOW(),
    'token_prefix',         COALESCE(v_settings.token_prefix, ''),
    'token_format',         COALESCE(v_settings.token_format, 'numeric'),
    'token_padding',        COALESCE(v_settings.token_padding, 2)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 5: get_token_status — include token format fields
-- ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_token_status(p_queue_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry    public.queue_entries;
  v_daily    public.queue_daily_state;
  v_settings public.hospital_settings;
  v_ahead    INT;
  v_wait_mins INT;
  v_avg_time  INT;
BEGIN
  SELECT * INTO v_entry FROM public.queue_entries WHERE id = p_queue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry not found: %', p_queue_id;
  END IF;

  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = v_entry.hospital_id AND queue_date = v_entry.queue_date;

  SELECT * INTO v_settings
  FROM public.hospital_settings WHERE hospital_id = v_entry.hospital_id;

  SELECT COUNT(*) INTO v_ahead
  FROM public.queue_entries
  WHERE hospital_id  = v_entry.hospital_id
    AND queue_date   = v_entry.queue_date
    AND status       = 'waiting'
    AND token_number < v_entry.token_number;

  v_avg_time  := COALESCE(v_settings.avg_time_per_patient, 5);
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
    'estimated_wait_mins',   v_wait_mins,
    'token_prefix',          COALESCE(v_settings.token_prefix, ''),
    'token_format',          COALESCE(v_settings.token_format, 'numeric'),
    'token_padding',         COALESCE(v_settings.token_padding, 2)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 6: Re-grant permissions
-- ─────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.update_hospital_settings TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_hospital_full(UUID)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_tv_display(UUID)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_token_status(UUID)   TO anon, authenticated;
