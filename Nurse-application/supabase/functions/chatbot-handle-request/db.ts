import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseKey) throw new Error("Supabase config missing");

const supabase = createClient(supabaseUrl, supabaseKey);

export async function getEmployeeDetails(emp_id: number) {
  const { data: emp, error: empErr } = await supabase
    .from("employee_final")
    .select("emp_id, first_name, last_name, email, supervisor_id")
    .eq("emp_id", emp_id)
    .single();

  if (empErr || !emp) return null;

  let supervisor_name = null;
  let supervisor_email = null;

  if (emp.supervisor_id) {
    const { data: sup } = await supabase
      .from("supervisors")
      .select("full_name, email")
      .eq("id", emp.supervisor_id)
      .single();

    if (sup) {
      supervisor_name = sup.full_name;
      supervisor_email = sup.email;
    }
  }

  return {
    emp_id: emp.emp_id,
    full_name: `${emp.first_name} ${emp.last_name}`,
    email: emp.email,
    supervisor_name,
    supervisor_email,
  };
}

export async function createShiftChangeRequest(payload: any) {
  const { data } = await supabase
    .from("shift_change_requests")
    .insert([payload])
    .select()
    .single();
  return data;
}

export async function createLeaveRecord(payload: any) {
  const { data } = await supabase
    .from("leaves")
    .insert([payload])
    .select()
    .single();
  return data;
}

export async function updateShiftStatus(emp_id: number, type: string) {
  let status = "late";
  if (type === "call_in_sick" || type === "emergency_leave") status = "on_leave";
  if (type === "partial_shift_change") status = "pending_reschedule";

  const today = new Date().toISOString().slice(0, 10);
  await supabase
    .from("shift")
    .update({ shift_status: status })
    .eq("emp_id", emp_id)
    .eq("date", today);
}
