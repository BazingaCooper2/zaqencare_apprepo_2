-- ==============================================================================
-- GET ACTIVE SHIFT V3 (Fix for blank clock-in/out screen)
--
-- Changes from V2:
--   1. JOIN uses public.client_final (c.id) instead of public.client (c.client_id)
--      because the app's Tables.client constant = 'client_final'
--   2. Filter uses shift_end_time > now() so nurses who arrive late still see their shift
--   3. Returns client name and service_type for display even before manual client fetch
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
  -- ✅ JOIN client_final (not client or client_staging)
  LEFT JOIN public.client_final c ON s.client_id = c.id
  WHERE s.emp_id = p_emp_id
    AND (
       -- 1. ALWAYS include IN_PROGRESS shifts (active work in progress)
       s.shift_status ILIKE 'in_progress'
       OR
       -- 2. Include SCHEDULED shifts if the shift end time hasn't passed yet.
       --    This means a nurse who is late still sees their shift.
       (
         s.shift_status ILIKE 'scheduled'
         AND
         to_timestamp(s.date || ' ' || s.shift_end_time, 'YYYY-MM-DD HH24:MI') > now()
       )
    )
  ORDER BY
    -- In Progress is highest priority
    (CASE WHEN s.shift_status ILIKE 'in_progress' THEN 0 ELSE 1 END) ASC,
    -- Then earliest start time
    to_timestamp(s.date || ' ' || s.shift_start_time, 'YYYY-MM-DD HH24:MI') ASC
  LIMIT 1;
END;
$$;
