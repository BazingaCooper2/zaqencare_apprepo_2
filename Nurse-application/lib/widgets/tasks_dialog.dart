import 'package:flutter/material.dart';
import '../main.dart';
import '../models/task_model.dart';
import '../models/shift.dart';
import '../constants/tables.dart';

class TasksDialog extends StatefulWidget {
  final Shift shift;
  const TasksDialog({super.key, required this.shift});

  @override
  State<TasksDialog> createState() => _TasksDialogState();
}

class _TasksDialogState extends State<TasksDialog> {
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      // ──────────────────────────────────────────────────────
      // 1. PRIMARY: Parse shift.task_id comma-separated string
      //    e.g. "task1,task2,task3,task4,task5"
      // ──────────────────────────────────────────────────────
      if (widget.shift.taskId != null && widget.shift.taskId!.contains(',')) {
        final parsed = Task.fromCommaSeparated(
          widget.shift.taskId,
          shiftId: widget.shift.shiftId,
        );
        if (parsed.isNotEmpty) {
          debugPrint(
              '✅ TasksDialog: Loaded ${parsed.length} tasks from shift.task_id (comma-separated)');
          if (mounted) {
            setState(() {
              _tasks = parsed;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // ──────────────────────────────────────────────────────
      // 2. Fetch tasks from client_final.tasks JSONB via client_id
      // ──────────────────────────────────────────────────────
      if (widget.shift.clientId != null) {
        try {
          final clientResponse = await supabase
              .from(Tables.client)
              .select('tasks')
              .eq('id', widget.shift.clientId!)
              .maybeSingle();

          if (clientResponse != null && clientResponse['tasks'] != null) {
            final clientTasks = Task.fromClientTasksJson(
              clientResponse['tasks'],
              shiftId: widget.shift.shiftId,
            );

            if (clientTasks.isNotEmpty) {
              debugPrint(
                  '✅ TasksDialog: Loaded ${clientTasks.length} tasks from client_final.tasks');
              if (mounted) {
                setState(() {
                  _tasks = clientTasks;
                  _isLoading = false;
                });
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('⚠️ TasksDialog: Error fetching client_final tasks: $e');
        }
      }

      // 2b. If client has embedded tasks in the shift's client object
      if (widget.shift.client?.tasks != null) {
        final clientTasks = Task.fromClientTasksJson(
          widget.shift.client!.tasks,
          shiftId: widget.shift.shiftId,
        );

        if (clientTasks.isNotEmpty) {
          debugPrint(
              '✅ TasksDialog: Loaded ${clientTasks.length} tasks from embedded client.tasks');
          if (mounted) {
            setState(() {
              _tasks = clientTasks;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // ──────────────────────────────────────────────────────
      // 3. Fallback: Legacy tasks table by shift_id
      // ──────────────────────────────────────────────────────
      var response = await supabase
          .from('tasks')
          .select('*')
          .eq('shift_id', widget.shift.shiftId)
          .order('task_id');

      // 4. Fallback: Try linking via shift.task_id as a single task_code
      if (response.isEmpty && widget.shift.taskId != null) {
        final shiftTaskCode = widget.shift.taskId!;
        final fallbackResponse = await supabase
            .from('tasks')
            .select('*')
            .eq('task_code', shiftTaskCode);

        if (fallbackResponse.isNotEmpty) {
          response = fallbackResponse;
        }
      }

      if (mounted) {
        setState(() {
          _tasks = response.map<Task>((e) => Task.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _allTasksCompleted =>
      _tasks.isNotEmpty && _tasks.every((t) => t.status);

  Future<void> _toggleTask(Task task, bool value) async {
    // Optimistic update
    final index = _tasks.indexWhere((t) => t.taskId == task.taskId);
    if (index == -1) return;

    final updatedTask = Task(
      taskId: task.taskId,
      shiftId: task.shiftId,
      details: task.details,
      status: value,
      comment: task.comment,
      taskCode: task.taskCode,
      isFromClient: task.isFromClient,
      isFromShiftTaskId: task.isFromShiftTaskId,
    );

    setState(() {
      _tasks[index] = updatedTask;
    });

    // Only persist to tasks table if it's from the legacy tasks table
    if (!task.isLocal) {
      try {
        await supabase
            .from('tasks')
            .update({'status': value}).eq('task_id', task.taskId);
      } catch (e) {
        debugPrint('Error updating task: $e');
        if (mounted) {
          setState(() {
            _tasks[index] = task;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update task: $e')),
          );
        }
      }
    }
    // Local tasks (from shift.task_id or client.tasks) toggle in-memory only
  }

  Future<void> _completeShift() async {
    try {
      await supabase.from('shift').update({'shift_status': 'completed'}).eq(
          'shift_id', widget.shift.shiftId);

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift marked as Completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error completing shift: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete shift: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.assignment_turned_in, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          const Text('Shift Tasks',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 150, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: double.maxFinite,
              child: _tasks.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_late_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No tasks assigned for this shift.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _tasks.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          title: Text(
                            task.details ?? 'Task ${index + 1}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
          ),
          child: const Text('Close'),
        ),
        // 'Update' button removed as requested
      ],
    );
  }
}
