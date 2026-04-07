-- ============================================================
-- ClinicQ Schema 9 Fix 3 — Fix get_patients SQL bug
-- Run AFTER schema9_fix2.sql
-- Bug: inner subquery used SELECT * with GROUP BY patient_phone
--      which is invalid PostgreSQL — causes RPC to fail.
-- Fix: use a CTE to get paginated patient_phones first, then
--      re-join to get all visit data for those patients.
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

  -- Paginated patient aggregation via CTE
  WITH paged_phones AS (
    -- Step 1: get the paginated set of patient phones
    SELECT patient_phone
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
    'patient_phone', e.patient_phone,
    'patient_name',  (array_agg(e.patient_name  ORDER BY e.created_at DESC))[1],
    'visit_count',   COUNT(*),
    'last_visit',    MAX(e.queue_date),
    'first_visit',   MIN(e.queue_date),
    'last_reason',   (array_agg(e.reason        ORDER BY e.created_at DESC))[1],
    'last_token',    (array_agg(e.token_number  ORDER BY e.created_at DESC))[1],
    'is_returning',  COUNT(*) > 1
  ) ORDER BY MAX(e.queue_date) DESC)
  INTO v_patients
  FROM public.queue_entries e
  JOIN paged_phones p ON p.patient_phone = e.patient_phone
  WHERE e.hospital_id = p_hospital_id
    AND (p_date_from IS NULL OR e.queue_date >= p_date_from)
    AND (p_date_to   IS NULL OR e.queue_date <= p_date_to)
    AND (p_search IS NULL OR
         e.patient_name  ILIKE '%' || p_search || '%' OR
         e.patient_phone ILIKE '%' || p_search || '%')
  GROUP BY e.patient_phone;

  RETURN json_build_object(
    'patients', COALESCE(v_patients, '[]'::JSON),
    'total',    v_total,
    'limit',    p_limit,
    'offset',   p_offset
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_patients(UUID, DATE, DATE, TEXT, INT, INT) TO authenticated;
