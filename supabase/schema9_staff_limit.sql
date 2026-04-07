-- ============================================================
-- ClinicQ Schema 9 Staff Limit Helper
-- Run AFTER schema9_fix2.sql
-- Adds an RPC to query current staff count — used by Flutter
-- to show the limit badge without calling the edge function.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_staff_count(p_hospital_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_count INT;
  v_total_count INT;
BEGIN
  IF NOT public._is_hospital_member(p_hospital_id) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT COUNT(*) INTO v_staff_count
  FROM public.hospital_users
  WHERE hospital_id = p_hospital_id
    AND role        = 'staff'
    AND is_active   = true;

  SELECT COUNT(*) INTO v_total_count
  FROM public.hospital_users
  WHERE hospital_id = p_hospital_id;

  RETURN json_build_object(
    'staff_count', v_staff_count,
    'total_count', v_total_count,
    'staff_limit', 5,
    'can_add',     v_staff_count < 5
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_count(UUID) TO authenticated;
