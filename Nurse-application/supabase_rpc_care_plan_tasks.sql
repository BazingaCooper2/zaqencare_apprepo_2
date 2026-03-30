-- ============================================================================
-- NURSE CARE PLAN TASK SYSTEM — Supabase RPC Functions
-- ============================================================================
-- Architecture Flow:
--   care_plan_tasks (templates)
--          ↓
--   auto_populate_shift_tasks (on clock-in)
--          ↓
--   shift_tasks (actual tasks for that shift)
--          ↓
--   nurse marks done / skipped
--
-- Task Status Values: 'pending' | 'done' | 'skipped'
-- ============================================================================


-- ============================================================================
-- FUNCTION 1: auto_populate_shift_tasks
-- ============================================================================
-- Called on clock-in to copy care plan template tasks into shift_tasks.
-- WILL NOT duplicate — if shift_tasks already exist for this shift, it returns
-- immediately without inserting anything.
-- ============================================================================
CREATE OR REPLACE FUNCTION auto_populate_shift_tasks(p_shift_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_id BIGINT;
  v_care_plan_id BIGINT;
  v_inserted_count INT;
BEGIN
  -- -----------------------------------------------
  -- 1. Guard: Do NOT duplicate if tasks already exist
  -- -----------------------------------------------
  IF EXISTS (SELECT 1 FROM shift_tasks WHERE shift_id = p_shift_id) THEN
    RETURN json_build_object(
      'success', true,
      'message', 'Tasks already populated for this shift',
      'inserted_count', 0
    );
  END IF;

  -- -----------------------------------------------
  -- 2. Get client_id from the shift
  -- -----------------------------------------------
  SELECT client_id INTO v_client_id
  FROM shift
  WHERE shift_id = p_shift_id;

  IF v_client_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Shift not found for shift_id: ' || p_shift_id,
      'inserted_count', 0
    );
  END IF;

  -- -----------------------------------------------
  -- 3. Get the active care plan for this client
  -- -----------------------------------------------
  SELECT care_plan_id INTO v_care_plan_id
  FROM care_plans
  WHERE client_id = v_client_id
    AND status = 'active'
  ORDER BY care_plan_id DESC
  LIMIT 1;

  IF v_care_plan_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'message', 'No active care plan found for client_id: ' || v_client_id,
      'inserted_count', 0
    );
  END IF;

  -- -----------------------------------------------
  -- 4. Insert active care plan tasks into shift_tasks
  -- -----------------------------------------------
  INSERT INTO shift_tasks (
    shift_id,
    task_id,
    task_name,
    category,
    instructions,
    is_temporary,
    status
  )
  SELECT
    p_shift_id,
    cpt.task_id,
    cpt.task_name,
    cpt.category,
    cpt.instructions,
    false,          -- is_temporary
    'pending'       -- status
  FROM care_plan_tasks cpt
  WHERE cpt.care_plan_id = v_care_plan_id
    AND cpt.is_active = true;

  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;

  RETURN json_build_object(
    'success', true,
    'message', 'Tasks populated successfully',
    'inserted_count', v_inserted_count
  );
END;
$$;


-- ============================================================================
-- FUNCTION 2: get_shift_tasks
-- ============================================================================
-- Returns all tasks for a given shift, ordered by:
--   1. is_temporary ASC  (permanent tasks first, temporary last)
--   2. sort_order   ASC  (from care_plan_tasks, NULLs last)
--   3. task_name    ASC  (alphabetical fallback)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_shift_tasks(p_shift_id BIGINT)
RETURNS TABLE (
  shift_task_id BIGINT,
  task_name     TEXT,
  category      TEXT,
  instructions  TEXT,
  is_temporary  BOOLEAN,
  status        TEXT,
  skip_reason   TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    st.shift_task_id,
    st.task_name,
    st.category,
    st.instructions,
    st.is_temporary,
    st.status,
    st.skip_reason
  FROM shift_tasks st
  LEFT JOIN care_plan_tasks cpt ON cpt.task_id = st.task_id
  WHERE st.shift_id = p_shift_id
  ORDER BY
    st.is_temporary ASC,                     -- permanent first, temporary last
    COALESCE(cpt.sort_order, 999999) ASC,    -- sort_order (NULLs last)
    st.task_name ASC;                        -- alphabetical fallback
END;
$$;


-- ============================================================================
-- FUNCTION 3: complete_shift_task
-- ============================================================================
-- Marks a shift task as 'done' or 'skipped'.
-- Sets completed_at = now() and records who completed it.
-- ============================================================================
CREATE OR REPLACE FUNCTION complete_shift_task(
  p_shift_task_id BIGINT,
  p_status        TEXT,
  p_skip_reason   TEXT DEFAULT NULL,
  p_completed_by  BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated_count INT;
BEGIN
  -- Validate status
  IF p_status NOT IN ('done', 'skipped') THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Invalid status. Use ''done'' or ''skipped''.'
    );
  END IF;

  -- Update the task
  UPDATE shift_tasks
  SET
    status       = p_status,
    skip_reason  = p_skip_reason,
    completed_by = p_completed_by,
    completed_at = now()
  WHERE shift_task_id = p_shift_task_id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Shift task not found for shift_task_id: ' || p_shift_task_id
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'Task marked as ' || p_status
  );
END;
$$;


-- ============================================================================
-- FUNCTION 4: add_temporary_shift_task
-- ============================================================================
-- Adds an ad-hoc (temporary) task to a shift.
-- These are NOT from the care plan — nurse-created on the spot.
-- ============================================================================
CREATE OR REPLACE FUNCTION add_temporary_shift_task(
  p_shift_id     BIGINT,
  p_task_name    TEXT,
  p_instructions TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_id BIGINT;
BEGIN
  INSERT INTO shift_tasks (
    shift_id,
    task_id,
    task_name,
    category,
    instructions,
    is_temporary,
    status
  )
  VALUES (
    p_shift_id,
    NULL,           -- no care_plan_tasks reference
    p_task_name,
    NULL,           -- no category for temp tasks
    p_instructions,
    true,           -- is_temporary
    'pending'       -- status
  )
  RETURNING shift_task_id INTO v_new_id;

  RETURN json_build_object(
    'success', true,
    'message', 'Temporary task added successfully',
    'shift_task_id', v_new_id
  );
END;
$$;
