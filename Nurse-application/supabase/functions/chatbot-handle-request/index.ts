import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import {
  getEmployeeDetails,
  createShiftChangeRequest,
  createLeaveRecord,
  updateShiftStatus,
} from "./db.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { emp_id, message, intent_type, signature_url, start_time, end_time, leave_start_date, leave_end_date } = await req.json();

    if (!emp_id || !intent_type) throw new Error("Missing data in request");

    const emp = await getEmployeeDetails(emp_id);
    if (!emp) throw new Error(`Employee with ID ${emp_id} not found`);

    // 1. Create Shift Change Request
    const requestRecord = await createShiftChangeRequest({
      emp_id,
      request_type: intent_type,
      requested_start_time: start_time ?? null,
      requested_end_time: end_time ?? null,
      requested_date: new Date().toISOString().slice(0, 10),
      reason: message,
      signature_url: signature_url ?? null,
    });

    // 2. Create Leave Record if sick
    if (intent_type === "call_in_sick" || intent_type === "emergency_leave") {
      await createLeaveRecord({
        emp_id,
        leave_type: intent_type,
        leave_reason: message,
        leave_start_date: leave_start_date ?? new Date().toISOString().slice(0, 10),
        leave_end_date: leave_end_date ?? new Date().toISOString().slice(0, 10),
        leave_start_time: start_time ?? null,
        leave_end_time: end_time ?? null,
        status: 'pending',
        signature_url: signature_url ?? null,
      });
    }

    // 3. Update Shift
    await updateShiftStatus(emp_id, intent_type);

    return new Response(JSON.stringify({
      ok: true,
      request_id: requestRecord?.id ?? null,
      supervisor: emp.supervisor_name,
      supervisor_email: emp.supervisor_email,
      employee_name: emp.full_name,
      type: intent_type,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err) {
    console.error("❌ Edge Function Error:", err.message);
    return new Response(JSON.stringify({ 
      ok: false, 
      error: err.message,
      stack: err.stack 
    }), { 
      status: 200, 
      headers: { ...corsHeaders, "Content-Type": "application/json" } 
    });
  }
});
