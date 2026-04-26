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

      // 2c. If client has care plans / tasks (Modern Care Plan system)
      if (widget.shift.client?.carePlans != null && widget.shift.client!.carePlans!.isNotEmpty) {
        final List<Task> cpTasks = [];
        for (final cp in widget.shift.client!.carePlans!) {
          for (final t in cp.tasks) {
            cpTasks.add(Task(
              taskId: t.taskId,
              shiftId: widget.shift.shiftId,
              details: t.taskName,
              status: false,
              isFromClient: true,
            ));
          }
        }
        if (cpTasks.isNotEmpty) {
          debugPrint('✅ TasksDialog: Loaded ${cpTasks.length} tasks from modern care_plans');
          if (mounted) {
            setState(() {
              _tasks = cpTasks;
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
      await supabase.from('shift').update({'shift_status': 'Clocked out'}).eq(
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
    return Dialog(
      backgroundColor: const Color(0xFFE8F0EE),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Blue Icon
            Row(
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
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Task List
            Flexible(
              child: _isLoading
                ? const SizedBox(
                    height: 150, 
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)))
                  )
                : _tasks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.assignment_late_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No tasks assigned for this shift.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _tasks.length,
                          separatorBuilder: (context, index) => Divider(
                            color: Colors.black.withOpacity(0.1),
                            height: 32,
                            thickness: 0.8,
                          ),
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.details ?? 'Task ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF3C4043),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
            ),
            
            const SizedBox(height: 12),
            
            // Footer: Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
          ],
        ),
      ),
    );
  }
}
