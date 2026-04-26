import 'package:flutter/material.dart';
import '../models/shift.dart';
import '../models/employee.dart';
import '../models/shift_task_model.dart';
import '../services/care_plan_service.dart';

/// ✅ TaskListScreen
/// Displays all shift_tasks for a given shift with Done / Skip actions.
class TaskListScreen extends StatefulWidget {
  final Shift shift;
  final Employee employee;

  const TaskListScreen({
    super.key,
    required this.shift,
    required this.employee,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final _service = CarePlanService();
  List<ShiftTask> _tasks = [];
  bool _loading = true;
  String? _error;
  final Set<int> _updatingTasks = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<ShiftTask> tasks = await _service.getShiftTasks(widget.shift.shiftId);
      
      // Fallback: If no shift_tasks exist yet, show the Care Plan tasks
      if (tasks.isEmpty && widget.shift.client?.carePlans != null) {
        for (final cp in widget.shift.client!.carePlans!) {
          for (final t in cp.tasks) {
            tasks.add(ShiftTask(
              shiftTaskId: t.taskId, // Synthetic ID
              shiftId: widget.shift.shiftId,
              taskId: t.taskId,
              taskName: t.taskName,
              isTemporary: false,
              status: 'pending',
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────
  // MARK DONE
  // ─────────────────────────────────────────────

  Future<void> _markDone(ShiftTask task) async {
    if (_updatingTasks.contains(task.shiftTaskId)) return;
    setState(() => _updatingTasks.add(task.shiftTaskId));

    try {
      final ok = await _service.completeTask(
        task.shiftTaskId,
        widget.employee.empId,
      );
      if (ok) {
        _showSnack('✅ Task marked done');
        _loadTasks();
      } else {
        _showSnack('❌ Failed to update task', isError: true);
      }
    } catch (e) {
      _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingTasks.remove(task.shiftTaskId));
    }
  }

  // ─────────────────────────────────────────────
  // SKIP TASK
  // ─────────────────────────────────────────────

  Future<void> _skipTask(ShiftTask task) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _SkipReasonDialog(),
    );

    if (reason == null || reason.trim().isEmpty) return;
    if (_updatingTasks.contains(task.shiftTaskId)) return;

    setState(() => _updatingTasks.add(task.shiftTaskId));

    try {
      final ok = await _service.skipTask(
        task.shiftTaskId,
        reason.trim(),
        widget.employee.empId,
      );
      if (ok) {
        _showSnack('⏭️ Task skipped');
        _loadTasks();
      } else {
        _showSnack('❌ Failed to skip task', isError: true);
      }
    } catch (e) {
      _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingTasks.remove(task.shiftTaskId));
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PROGRESS
  // ─────────────────────────────────────────────

  int get _doneCount => _tasks.where((t) => t.isDone || t.isSkipped).length;
  int get _totalCount => _tasks.length;
  double get _progress => _totalCount == 0 ? 0 : _doneCount / _totalCount;

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0EE), // Light mint/grey background from SC
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Header: Icon + Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.assignment_rounded, 
                      color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Shift Tasks',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Task List
            Expanded(
              child: _buildBody(),
            ),

            // Footer: Close Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadTasks, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Text(
          'No tasks for this shift',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _tasks.length,
      separatorBuilder: (context, index) => Divider(
        color: Colors.black.withOpacity(0.1),
        height: 48,
        thickness: 0.8,
      ),
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.taskName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Color(0xFF3C4043),
                height: 1.4,
              ),
            ),
            if (task.instructions != null && task.instructions!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.instructions!,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// SKIP REASON DIALOG (Keep but style)
// ─────────────────────────────────────────────

class _SkipReasonDialog extends StatefulWidget {
  const _SkipReasonDialog();

  @override
  State<_SkipReasonDialog> createState() => _SkipReasonDialogState();
}

class _SkipReasonDialogState extends State<_SkipReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skip Task',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Reason for skipping...',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final reason = _controller.text.trim();
                    if (reason.isEmpty) return;
                    Navigator.pop(context, reason);
                  },
                  child: const Text('Skip'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
