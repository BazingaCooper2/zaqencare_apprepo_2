-- Step 1: Create Debug Function
CREATE OR REPLACE FUNCTION debug_auth_uid()
RETURNS text
LANGUAGE sql
AS $$
  SELECT auth.uid()::text;
$$;

-- Step 2: Update RLS Policies with EXISTS-based logic for better security and performance

-- Injury Reports
DROP POLICY IF EXISTS employee_insert_injury_reports ON injury_reports;
CREATE POLICY employee_insert_injury_reports
ON injury_reports
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = injury_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS employee_select_own_injury_reports ON injury_reports;
CREATE POLICY employee_select_own_injury_reports
ON injury_reports
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = injury_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);

-- Incident Reports
DROP POLICY IF EXISTS employee_insert_incident_reports ON incident_reports;
CREATE POLICY employee_insert_incident_reports
ON incident_reports
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = incident_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS employee_select_own_incident_reports ON incident_reports;
CREATE POLICY employee_select_own_incident_reports
ON incident_reports
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = incident_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);

-- Hazard Reports
DROP POLICY IF EXISTS employee_insert_hazard_reports ON hazard_near_miss_reports;
CREATE POLICY employee_insert_hazard_reports
ON hazard_near_miss_reports
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = hazard_near_miss_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS employee_select_own_hazard_reports ON hazard_near_miss_reports;
CREATE POLICY employee_select_own_hazard_reports
ON hazard_near_miss_reports
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM employee
    WHERE employee.emp_id = hazard_near_miss_reports.emp_id
    AND employee.user_id = auth.uid()
  )
);
