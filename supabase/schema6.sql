-- ============================================================
-- ClinicQ Schema 6 — Safety re-apply of schema5 columns & functions
-- Run this if the dashboard shows "Database function missing".
-- All statements are idempotent (safe to re-run).
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- PART 1: Ensure schema5 columns exist
-- ─────────────────────────────────────────────────────────

-- queue_entries: custom_data column (added by schema5)
ALTER TABLE public.queue_entries
  ADD COLUMN IF NOT EXISTS custom_data JSONB DEFAULT '{}'::JSONB;

-- hospital_settings: field-toggle columns (added by schema5)
ALTER TABLE public.hospital_settings
  ADD COLUMN IF NOT EXISTS enable_age     BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS enable_reason  BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS custom_fields  JSONB   NOT NULL DEFAULT '[]'::JSONB;

-- GIN index for custom_data (safe with IF NOT EXISTS)
CREATE INDEX IF NOT EXISTS idx_queue_entries_custom_data
  ON public.queue_entries USING gin (custom_data);

-- ─────────────────────────────────────────────────────────
-- PART 2: Re-create get_queue_today (references custom_data)
-- ─────────────────────────────────────────────────────────
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
  SELECT u.id INTO v_caller_user_id
  FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT created_by INTO v_hospital_owner
  FROM public.hospitals WHERE id = p_hospital_id;

  IF v_caller_user_id IS NULL OR v_caller_user_id != v_hospital_owner THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT * INTO v_daily
  FROM public.queue_daily_state
  WHERE hospital_id = p_hospital_id AND queue_date = v_today;

  SELECT COALESCE(avg_time_per_patient, 5) INTO v_avg_settings
  FROM public.hospital_settings WHERE hospital_id = p_hospital_id;

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
      'custom_data',    COALESCE(e.custom_data, '{}'::JSONB),
      'called_at',      e.called_at,
      'completed_at',   e.completed_at,
      'created_at',     e.created_at,
      'updated_at',     e.updated_at
    ) ORDER BY e.token_number ASC
  ) INTO v_entries
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
    'last_token_number',    COALESCE(v_daily.last_token_number,    0),
    'total_served',         COALESCE(v_daily.total_served,         0),
    'avg_actual_wait',      COALESCE(v_daily.avg_actual_wait,      0),
    'avg_time_setting',     COALESCE(v_avg_settings,               5),
    'counts',               v_counts,
    'queue_date',           v_today
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 3: Re-create get_hospital_full (references enable_age etc.)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_hospital_full(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hospital  public.hospitals;
  v_settings  public.hospital_settings;
BEGIN
  SELECT * INTO v_hospital
  FROM public.hospitals
  WHERE id = p_hospital_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Hospital not found: %', p_hospital_id;
  END IF;

  SELECT * INTO v_settings
  FROM public.hospital_settings
  WHERE hospital_id = p_hospital_id;

  RETURN json_build_object(
    'id',       v_hospital.id,
    'name',     v_hospital.name,
    'slug',     v_hospital.slug,
    'address',  v_hospital.address,
    'phone',    v_hospital.phone,
    'settings', json_build_object(
      'token_limit',           COALESCE(v_settings.token_limit,           100),
      'avg_time_per_patient',  COALESCE(v_settings.avg_time_per_patient,  5),
      'alert_before',          COALESCE(v_settings.alert_before,          3),
      'working_hours_start',   COALESCE(v_settings.working_hours_start::TEXT, '09:00'),
      'working_hours_end',     COALESCE(v_settings.working_hours_end::TEXT,   '18:00'),
      'enable_age',            COALESCE(v_settings.enable_age,            true),
      'enable_reason',         COALESCE(v_settings.enable_reason,         true),
      'custom_fields',         COALESCE(v_settings.custom_fields,         '[]'::JSONB)
    )
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 4: Re-create create_queue_entry (references custom_data)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_queue_entry(
  p_hospital_id  UUID,
  p_name         TEXT,
  p_phone        TEXT,
  p_age          INT     DEFAULT NULL,
  p_reason       TEXT    DEFAULT NULL,
  p_custom_data  JSONB   DEFAULT '{}'
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
  v_lock_key := abs(hashtext(p_hospital_id::TEXT || v_today::TEXT));
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(token_limit, 100) INTO v_token_limit
  FROM public.hospital_settings
  WHERE hospital_id = p_hospital_id;

  INSERT INTO public.queue_daily_state
    (hospital_id, queue_date, last_token_number, current_token_number)
  VALUES (p_hospital_id, v_today, 1, 0)
  ON CONFLICT (hospital_id, queue_date) DO UPDATE
    SET last_token_number = queue_daily_state.last_token_number + 1,
        updated_at        = NOW()
  RETURNING last_token_number INTO v_token_number;

  IF v_token_number > COALESCE(v_token_limit, 100) THEN
    RAISE EXCEPTION 'TOKEN_LIMIT_REACHED: Daily token limit of % reached', v_token_limit;
  END IF;

  INSERT INTO public.queue_entries (
    hospital_id, token_number, queue_date,
    patient_name, patient_phone, patient_age,
    reason, status, custom_data
  )
  VALUES (
    p_hospital_id, v_token_number, v_today,
    trim(p_name), trim(p_phone), p_age,
    p_reason, 'waiting',
    COALESCE(p_custom_data, '{}'::JSONB)
  )
  RETURNING id INTO v_queue_id;

  RETURN json_build_object(
    'id',            v_queue_id,
    'token_number',  v_token_number,
    'hospital_id',   p_hospital_id,
    'patient_name',  trim(p_name),
    'patient_phone', trim(p_phone),
    'patient_age',   p_age,
    'reason',        p_reason,
    'status',        'waiting',
    'queue_date',    v_today,
    'custom_data',   COALESCE(p_custom_data, '{}'::JSONB)
  );
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 5: Re-create update_hospital_settings (9-param version)
-- ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_hospital_settings(
  p_hospital_id          UUID,
  p_token_limit          INT     DEFAULT NULL,
  p_avg_time_per_patient INT     DEFAULT NULL,
  p_alert_before         INT     DEFAULT NULL,
  p_working_hours_start  TEXT    DEFAULT NULL,
  p_working_hours_end    TEXT    DEFAULT NULL,
  p_enable_age           BOOLEAN DEFAULT NULL,
  p_enable_reason        BOOLEAN DEFAULT NULL,
  p_custom_fields        JSONB   DEFAULT NULL
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
    custom_fields        = COALESCE(p_custom_fields,        custom_fields)
  WHERE hospital_id = p_hospital_id;

  RETURN (SELECT json_build_object(
    'success',        true,
    'hospital_id',    p_hospital_id,
    'enable_age',     enable_age,
    'enable_reason',  enable_reason,
    'custom_fields',  custom_fields
  ) FROM public.hospital_settings WHERE hospital_id = p_hospital_id);
END;
$$;

-- ─────────────────────────────────────────────────────────
-- PART 6: Re-grant all permissions
-- ─────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.get_queue_today(UUID)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.get_hospital_full(UUID)
  TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_queue_entry(UUID, TEXT, TEXT, INT, TEXT, JSONB)
  TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.update_hospital_settings(
  UUID, INT, INT, INT, TEXT, TEXT, BOOLEAN, BOOLEAN, JSONB)
  TO authenticated;
