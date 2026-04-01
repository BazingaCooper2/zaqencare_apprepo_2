class ShiftTask {
  final int shiftTaskId;
  final int shiftId;
  final int? taskId; // references care_plan_tasks.task_id (null for temp tasks)
  final String taskName;
  final String? category;
  final String? instructions;
  final bool isTemporary;
  final String status; // pending | done | skipped
  final String? skipReason;
  final DateTime? completedAt;
  final int? completedBy; // emp_id
  final DateTime? createdAt;

  ShiftTask({
    required this.shiftTaskId,
    required this.shiftId,
    this.taskId,
    required this.taskName,
    this.category,
    this.instructions,
    required this.isTemporary,
    required this.status,
    this.skipReason,
    this.completedAt,
    this.completedBy,
    this.createdAt,
  });

  factory ShiftTask.fromJson(Map<String, dynamic> json) {
    return ShiftTask(
      shiftTaskId: json['shift_task_id'] as int,
      shiftId: json['shift_id'] as int,
      taskId: json['task_id'] as int?,
      taskName: json['task_name'] as String? ?? '',
      category: json['category'] as String?,
      instructions: json['instructions'] as String?,
      isTemporary: json['is_temporary'] as bool? ?? false,
      status: json['status'] as String? ?? 'pending',
      skipReason: json['skip_reason'] as String?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      completedBy: json['completed_by'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shift_task_id': shiftTaskId,
      'shift_id': shiftId,
      'task_id': taskId,
      'task_name': taskName,
      'category': category,
      'instructions': instructions,
      'is_temporary': isTemporary,
      'status': status,
      'skip_reason': skipReason,
      'completed_at': completedAt?.toIso8601String(),
      'completed_by': completedBy,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  bool get isDone => status == 'done';
  bool get isSkipped => status == 'skipped';
  bool get isPending => status == 'pending';
}
