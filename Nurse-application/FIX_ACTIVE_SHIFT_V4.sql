-- ==============================================================================
-- GET ACTIVE SHIFT V4 (Improved status support)
--
-- Changes from V3:
--   1. Added 'Clocked in', 'Assigned', and 'Accepted' to active candidate list.
--   2. Ensures 'Clocked in' shifts take absolute priority.
-- ==============================================================================

CREATE OR REPLACE FUNCTION get_active_shift(p_emp_id BIGINT)
RETURNS TABLE (
  shift_id          BIGINT,
  emp_id            BIGINT,
  client_id         BIGINT,
  start_ts          TIMESTAMPTZ,
  shift_status      TEXT,
  date              TEXT,
  shift_start_time  TEXT,
  shift_end_time    TEXT,
  client_name       TEXT,
  client_service_type TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.shift_id,
    s.emp_id,
    s.client_id,
    to_timestamp(s.date || ' ' || s.shift_start_time, 'YYYY-MM-DD HH24:MI') AS start_ts,
    s.shift_status,
    s.date,
    s.shift_start_time,
    s.shift_end_time,
    c.name            AS client_name,
    c.service_type    AS client_service_type
  FROM public.shift s
  LEFT JOIN public.client_final c ON s.client_id = c.id
  WHERE s.emp_id = p_emp_id
    AND (
       -- 1. Shifts that are already live
       s.shift_status ILIKE 'in_progress' 
       OR s.shift_status ILIKE 'Clocked in' 
       OR s.shift_status ILIKE 'active'
       OR
       -- 2. Shifts that are ready to be started (scheduled, assigned, or accepted)
       --    and haven't ended yet
       (
         (s.shift_status ILIKE 'scheduled' OR s.shift_status ILIKE 'assigned' OR s.shift_status ILIKE 'accepted')
         AND
         to_timestamp(s.date || ' ' || s.shift_end_time, 'YYYY-MM-DD HH24:MI') > now()
       )
    )
  ORDER BY
    -- Priority 1: Physically clocked in
    (CASE WHEN s.shift_status ILIKE 'Clocked in' THEN 0 
          WHEN s.shift_status ILIKE 'in_progress' THEN 1 
          ELSE 2 END) ASC,
    -- Priority 2: Earliest start time
    to_timestamp(s.date || ' ' || s.shift_start_time, 'YYYY-MM-DD HH24:MI') ASC
  LIMIT 1;
END;
$$;
