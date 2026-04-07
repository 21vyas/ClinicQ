-- ============================================================
-- ClinicQ Schema 9 Fix 4 — get_patients: no nested aggregates
-- Run AFTER schema9_fix3.sql (replaces it)
-- Bug: json_agg(... ORDER BY MAX(...)) = nested aggregate = error
-- Fix: pre-aggregate in CTE, then json_agg over plain rows
-- ============================================================

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

  -- Total distinct patients matching the filter
  SELECT COUNT(DISTINCT patient_phone) INTO v_total
  FROM public.queue_entries
  WHERE hospital_id = p_hospital_id
    AND (p_date_from IS NULL OR queue_date >= p_date_from)
    AND (p_date_to   IS NULL OR queue_date <= p_date_to)
    AND (p_search IS NULL OR
         patient_name  ILIKE '%' || p_search || '%' OR
         patient_phone ILIKE '%' || p_search || '%');

  -- Pre-aggregate per patient, then paginate, then json_agg
  WITH aggregated AS (
    SELECT
      patient_phone,
      COUNT(*)                                              AS visit_count,
      MAX(queue_date)                                       AS last_visit,
      MIN(queue_date)                                       AS first_visit,
      (array_agg(patient_name ORDER BY created_at DESC))[1] AS patient_name,
      (array_agg(reason       ORDER BY created_at DESC))[1] AS last_reason,
      (array_agg(token_number ORDER BY created_at DESC))[1] AS last_token,
      COUNT(*) > 1                                          AS is_returning
    FROM public.queue_entries
    WHERE hospital_id = p_hospital_id
      AND (p_date_from IS NULL OR queue_date >= p_date_from)
      AND (p_date_to   IS NULL OR queue_date <= p_date_to)
      AND (p_search IS NULL OR
           patient_name  ILIKE '%' || p_search || '%' OR
           patient_phone ILIKE '%' || p_search || '%')
    GROUP BY patient_phone
    ORDER BY MAX(queue_date) DESC
    LIMIT p_limit OFFSET p_offset
  )
  SELECT json_agg(json_build_object(
    'patient_phone', patient_phone,
    'patient_name',  patient_name,
    'visit_count',   visit_count,
    'last_visit',    last_visit,
    'first_visit',   first_visit,
    'last_reason',   last_reason,
    'last_token',    last_token,
    'is_returning',  is_returning
  ))
  INTO v_patients
  FROM aggregated;

  RETURN json_build_object(
    'patients', COALESCE(v_patients, '[]'::JSON),
    'total',    v_total,
    'limit',    p_limit,
    'offset',   p_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_patients(UUID, DATE, DATE, TEXT, INT, INT) TO authenticated;
