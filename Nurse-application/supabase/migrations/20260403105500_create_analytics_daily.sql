-- STEP 1 — Create analytics_daily Table
CREATE TABLE public.analytics_daily (
  analytics_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  emp_id BIGINT,
  date DATE,

  total_hours NUMERIC DEFAULT 0,
  overtime_hours NUMERIC DEFAULT 0,

  completed_shifts INT DEFAULT 0,
  cancelled_shifts INT DEFAULT 0,
  inprogress_shifts INT DEFAULT 0,

  tasks_completed INT DEFAULT 0,

  week_number INT,
  month INT,
  year INT,

  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(emp_id, date)
);

-- STEP 3 — Function to Generate Daily Analytics
CREATE OR REPLACE FUNCTION generate_daily_analytics(p_emp_id BIGINT, p_date DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_hours NUMERIC := 0;
  v_overtime NUMERIC := 0;
  v_completed INT := 0;
  v_cancelled INT := 0;
  v_inprogress INT := 0;
  v_tasks INT := 0;
BEGIN

  -- Total hours worked
  SELECT COALESCE(SUM(total_hours), 0)
  INTO v_total_hours
  FROM time_logs
  WHERE emp_id = p_emp_id
  AND date = p_date;

  -- Overtime calculation
  v_overtime := GREATEST(v_total_hours - 8, 0);

  -- Completed shifts
  SELECT COUNT(*)
  INTO v_completed
  FROM shift
  WHERE emp_id = p_emp_id
  AND date = p_date
  AND (shift_status = 'Completed' OR shift_status = 'Clocked out');

  -- Cancelled shifts
  SELECT COUNT(*)
  INTO v_cancelled
  FROM shift
  WHERE emp_id = p_emp_id
  AND date = p_date
  AND shift_status = 'Cancelled';

  -- In Progress shifts
  SELECT COUNT(*)
  INTO v_inprogress
  FROM shift
  WHERE emp_id = p_emp_id
  AND date = p_date
  AND (shift_status = 'In Progress' OR shift_status = 'Clocked in');

  -- Tasks completed (from shift_tasks)
  SELECT COUNT(*)
  INTO v_tasks
  FROM shift_tasks st
  JOIN shift s ON s.shift_id = st.shift_id
  WHERE s.emp_id = p_emp_id
  AND DATE(st.completed_at) = p_date
  AND st.status = 'completed';

  -- UPSERT into analytics_daily
  INSERT INTO analytics_daily (
    emp_id,
    date,
    total_hours,
    overtime_hours,
    completed_shifts,
    cancelled_shifts,
    inprogress_shifts,
    tasks_completed,
    week_number,
    month,
    year
  )
  VALUES (
    p_emp_id,
    p_date,
    v_total_hours,
    v_overtime,
    v_completed,
    v_cancelled,
    v_inprogress,
    v_tasks,
    EXTRACT(WEEK FROM p_date),
    EXTRACT(MONTH FROM p_date),
    EXTRACT(YEAR FROM p_date)
  )
  ON CONFLICT (emp_id, date)
  DO UPDATE SET
    total_hours = EXCLUDED.total_hours,
    overtime_hours = EXCLUDED.overtime_hours,
    completed_shifts = EXCLUDED.completed_shifts,
    cancelled_shifts = EXCLUDED.cancelled_shifts,
    inprogress_shifts = EXCLUDED.inprogress_shifts,
    tasks_completed = EXCLUDED.tasks_completed,
    week_number = EXCLUDED.week_number,
    month = EXCLUDED.month,
    year = EXCLUDED.year;

END;
$$;

-- STEP 4 — Trigger When Nurse Clocks Out
CREATE OR REPLACE FUNCTION trigger_clock_out_analytics()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM generate_daily_analytics(NEW.emp_id, NEW.date);
  RETURN NEW;
END;
$$;

CREATE TRIGGER clock_out_trigger
AFTER UPDATE OF clock_out ON time_logs
FOR EACH ROW
WHEN (NEW.clock_out IS NOT NULL)
EXECUTE FUNCTION trigger_clock_out_analytics();

-- STEP 5 — Trigger When Shift Completed
CREATE OR REPLACE FUNCTION trigger_shift_completed_analytics()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.shift_status = 'Completed' THEN
    PERFORM generate_daily_analytics(NEW.emp_id, NEW.date);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER shift_completed_trigger
AFTER UPDATE OF shift_status ON shift
FOR EACH ROW
EXECUTE FUNCTION trigger_shift_completed_analytics();
