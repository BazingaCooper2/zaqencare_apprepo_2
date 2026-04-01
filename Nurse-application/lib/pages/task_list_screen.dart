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
      final tasks = await _service.getShiftTasks(widget.shift.shiftId);
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PROGRESS
  // ─────────────────────────────────────────────

  int get _doneCount =>
      _tasks.where((t) => t.isDone || t.isSkipped).length;
  int get _totalCount => _tasks.length;
  double get _progress =>
      _totalCount == 0 ? 0 : _doneCount / _totalCount;

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.shift.clientName ?? 'Tasks',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.shift.formattedTimeRange,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          _buildProgressHeader(theme, colorScheme),
          // Task list
          Expanded(child: _buildBody(theme, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_doneCount of $_totalCount tasks completed',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  color: _progress == 1
                      ? Colors.green
                      : colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                _progress == 1 ? Colors.green : colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadTasks, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist,
                color: colorScheme.onSurface.withValues(alpha: 0.3), size: 64),
            const SizedBox(height: 16),
            Text(
              'No tasks for this shift',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // Group tasks by category
    final grouped = <String, List<ShiftTask>>{};
    for (final t in _tasks) {
      final cat = t.category ?? 'General';
      grouped.putIfAbsent(cat, () => []).add(t);
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: colorScheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: grouped.entries.map((entry) {
          return _CategorySection(
            category: entry.key,
            tasks: entry.value,
            updatingTasks: _updatingTasks,
            onDone: _markDone,
            onSkip: _skipTask,
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CATEGORY SECTION
// ─────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final String category;
  final List<ShiftTask> tasks;
  final Set<int> updatingTasks;
  final Future<void> Function(ShiftTask) onDone;
  final Future<void> Function(ShiftTask) onSkip;

  const _CategorySection({
    required this.category,
    required this.tasks,
    required this.updatingTasks,
    required this.onDone,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                category.toUpperCase(),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${tasks.length})',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        ...tasks.map((t) => _TaskCard(
              task: t,
              updating: updatingTasks.contains(t.shiftTaskId),
              onDone: () => onDone(t),
              onSkip: () => onSkip(t),
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// TASK CARD
// ─────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final ShiftTask task;
  final bool updating;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  const _TaskCard({
    required this.task,
    required this.updating,
    required this.onDone,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isDone = task.isDone;
    final isSkipped = task.isSkipped;
    final isPending = task.isPending;

    Color borderColor;
    Color bgColor;

    if (isDone) {
      borderColor = Colors.green.withValues(alpha: 0.4);
      bgColor = Colors.green.withValues(alpha: 0.05);
    } else if (isSkipped) {
      borderColor = Colors.orange.withValues(alpha: 0.4);
      bgColor = Colors.orange.withValues(alpha: 0.05);
    } else {
      borderColor = colorScheme.outlineVariant;
      bgColor = colorScheme.surface;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (isPending)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task name row
            Row(
              children: [
                if (isDone)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20)
                else if (isSkipped)
                  const Icon(Icons.skip_next, color: Colors.orange, size: 20)
                else
                  Icon(Icons.radio_button_unchecked,
                      color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.taskName,
                    style: TextStyle(
                      color: isDone
                          ? Colors.green
                          : isSkipped
                              ? Colors.orange
                              : colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (task.isTemporary)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'TEMP',
                      style: TextStyle(
                          color: colorScheme.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),

            // Instructions
            if (task.instructions != null && task.instructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  task.instructions!,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ],

            // Skip reason
            if (isSkipped && task.skipReason != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Reason: ${task.skipReason}',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action buttons (only for pending tasks)
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (updating)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colorScheme.primary),
                    )
                  else ...[
                    _SmallButton(
                      label: 'Skip',
                      icon: Icons.skip_next,
                      color: Colors.orange,
                      onTap: onSkip,
                    ),
                    const SizedBox(width: 8),
                    _SmallButton(
                      label: 'Done',
                      icon: Icons.check,
                      color: colorScheme.primary,
                      onTap: onDone,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SKIP REASON DIALOG
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.skip_next, color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Skip Task',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Please provide a reason for skipping this task:',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'e.g., Client refused, Not applicable today...',
                hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.3)),
                filled: true,
                fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: colorScheme.onSurface.withValues(alpha: 0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final reason = _controller.text.trim();
                    if (reason.isEmpty) return;
                    Navigator.pop(context, reason);
                  },
                  child: const Text('Skip Task'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


