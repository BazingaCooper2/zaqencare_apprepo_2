import 'package:flutter/foundation.dart';
import '../../main.dart';
import '../models/shift_task_model.dart';
import '../models/shift.dart';

/// ✅ Service handling all Care Plan + Shift Task operations via Supabase
class CarePlanService {
  // ─────────────────────────────────────────────
  // SHIFT FETCHING
  // ─────────────────────────────────────────────

  /// Get all shifts (blocks, children, standalone) for the employee for TODAY.
  /// (Per User Rules: One Query, 00:00 to 00:00, filter by shift_start_time)
  Future<List<Shift>> getAllShiftsToday(int empId) async {
    try {
      debugPrint('📥 One Query: Fetching ALL shifts today for emp=$empId');

      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      final endOfToday = DateTime(tomorrow.year, tomorrow.month, tomorrow.day).toUtc().toIso8601String();

      // We include 'clocked_in' to ensure active shifts are fetched
      final response = await supabase
          .from('shift')
          .select('*, client:client_final(*)')
          .eq('emp_id', empId)
          .inFilter('shift_status', ['Scheduled', 'Assigned', 'clocked_in'])
          .gte('shift_start_time', startOfToday)
          .lt('shift_start_time', endOfToday)
          .order('shift_start_time');

      return (response as List)
          .map((e) => Shift.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ getAllShiftsToday error: $e');
      return [];
    }
  }

  /// DEPRECATED: Please use getAllShiftsToday and group in Flutter
  Future<List<Shift>> getShifts(int empId) async => getAllShiftsToday(empId);

  /// Get child shifts for a block parent
  Future<List<Shift>> getChildShifts(int blockShiftId) async {
    try {
      debugPrint('📥 Fetching child shifts for block=$blockShiftId');

      final response = await supabase
          .from('shift')
          .select('*')
          .eq('parent_block_id', blockShiftId)
          .order('shift_start_time');

      return (response as List)
          .map((e) => Shift.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ getChildShifts error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // CLOCK IN / CLOCK OUT
  // ─────────────────────────────────────────────

  /// Clock in a shift: updates shift table and auto-populates tasks
  Future<bool> clockInShift(int shiftId) async {
    try {
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      await supabase.from('shift').update({
        'clock_in': nowUtc,
        'shift_status': 'clocked_in',
      }).eq('shift_id', shiftId);

      debugPrint('✅ clockInShift: shift $shiftId set to In Progress');
      return true;
    } catch (e) {
      debugPrint('❌ clockInShift error: $e');
      return false;
    }
  }

  /// Clock out a shift: updates shift table
  Future<bool> clockOutShift(int shiftId) async {
    try {
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      await supabase.from('shift').update({
        'clock_out': nowUtc,
        'shift_status': 'clocked_out',
      }).eq('shift_id', shiftId);

      debugPrint('✅ clockOutShift: shift $shiftId set to Completed');
      return true;
    } catch (e) {
      debugPrint('❌ clockOutShift error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // TASK AUTO-POPULATE
  // ─────────────────────────────────────────────

  /// Auto-populate shift_tasks from care_plan_tasks on clock-in.
  /// Finds the active care plan for the client, then copies all active tasks.
  Future<bool> autoPopulateTasks(int shiftId, int clientId) async {
    try {
      debugPrint('🔄 Auto-populating tasks for shift=$shiftId, client=$clientId');

      // 1. Get active care plan for client
      final carePlans = await supabase
          .from('care_plans')
          .select('care_plan_id')
          .eq('client_id', clientId)
          .eq('status', 'active')
          .limit(1);

      if (carePlans.isEmpty) {
        debugPrint('⚠️ No active care plan found for client $clientId');
        return true; // Not an error — shift may have no care plan
      }

      final carePlanId = carePlans.first['care_plan_id'] as int;

      // 2. Get active care plan tasks
      final planTasks = await supabase
          .from('care_plan_tasks')
          .select('*')
          .eq('care_plan_id', carePlanId)
          .eq('is_active', true)
          .order('sort_order');

      if (planTasks.isEmpty) {
        debugPrint('⚠️ No active tasks in care plan $carePlanId');
        return true;
      }

      // 3. Check which task_ids already exist in shift_tasks (avoid duplicates)
      final existing = await supabase
          .from('shift_tasks')
          .select('task_id')
          .eq('shift_id', shiftId)
          .not('task_id', 'is', null);

      final existingTaskIds = existing
          .map((e) => e['task_id'] as int)
          .toSet();

      // 4. Build insert rows, skipping already-present tasks
      final insertRows = <Map<String, dynamic>>[];
      for (final pt in planTasks) {
        final taskId = pt['task_id'] as int;
        if (!existingTaskIds.contains(taskId)) {
          insertRows.add({
            'shift_id': shiftId,
            'task_id': taskId,
            'task_name': pt['task_name'],
            'category': pt['category'],
            'instructions': pt['instructions'],
            'is_temporary': false,
            'status': 'pending',
          });
        }
      }

      if (insertRows.isNotEmpty) {
        await supabase.from('shift_tasks').insert(insertRows);
        debugPrint('✅ Auto-populated ${insertRows.length} tasks');
      } else {
        debugPrint('ℹ️ All tasks already populated');
      }

      return true;
    } catch (e) {
      debugPrint('❌ autoPopulateTasks error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // SHIFT TASKS
  // ─────────────────────────────────────────────

  /// Fetch all shift_tasks for a given shift
  Future<List<ShiftTask>> getShiftTasks(int shiftId) async {
    try {
      final response = await supabase
          .from('shift_tasks')
          .select('*')
          .eq('shift_id', shiftId)
          .order('created_at');

      return (response as List)
          .map((e) => ShiftTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ getShiftTasks error: $e');
      return [];
    }
  }

  /// Mark a shift task as DONE
  Future<bool> completeTask(int shiftTaskId, int empId) async {
    try {
      await supabase.from('shift_tasks').update({
        'status': 'done',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'completed_by': empId,
      }).eq('shift_task_id', shiftTaskId);

      debugPrint('✅ Task $shiftTaskId marked done');
      return true;
    } catch (e) {
      debugPrint('❌ completeTask error: $e');
      return false;
    }
  }

  /// Mark a shift task as SKIPPED
  Future<bool> skipTask(int shiftTaskId, String reason, int empId) async {
    try {
      await supabase.from('shift_tasks').update({
        'status': 'skipped',
        'skip_reason': reason,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'completed_by': empId,
      }).eq('shift_task_id', shiftTaskId);

      debugPrint('✅ Task $shiftTaskId skipped');
      return true;
    } catch (e) {
      debugPrint('❌ skipTask error: $e');
      return false;
    }
  }



  /// Check if all tasks for a shift are done or skipped (clock-out guard)
  Future<bool> areAllTasksComplete(int shiftId) async {
    try {
      final response = await supabase
          .from('shift_tasks')
          .select('status')
          .eq('shift_id', shiftId)
          .eq('status', 'pending');

      return response.isEmpty;
    } catch (e) {
      debugPrint('❌ areAllTasksComplete error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // CLIENT DETAILS
  // ─────────────────────────────────────────────

  /// Fetch client details from client_final table
  Future<Map<String, dynamic>?> getClientDetails(int clientId) async {
    try {
      final response = await supabase
          .from('client_final')
          .select('*')
          .eq('id', clientId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('❌ getClientDetails error: $e');
      return null;
    }
  }
}
