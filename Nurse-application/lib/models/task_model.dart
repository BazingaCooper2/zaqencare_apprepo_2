class Task {
  final int taskId;
  final int shiftId;
  final String? details;
  final bool status;
  final String? comment;
  final String? taskCode;
  final bool isFromClient; // true if from client_final.tasks JSONB
  final bool isFromShiftTaskId; // true if from shift.task_id comma-separated
  final String? shiftTaskLogStatus; // pending, done, skipped
  final String? skipReason;

  Task({
    required this.taskId,
    required this.shiftId,
    this.details,
    required this.status,
    this.comment,
    this.taskCode,
    this.isFromClient = false,
    this.isFromShiftTaskId = false,
    this.shiftTaskLogStatus,
    this.skipReason,
  });

  /// Whether this task was parsed locally (not from the `tasks` DB table).
  bool get isLocal => isFromClient || isFromShiftTaskId;

  /// Parse from the existing `tasks` table row.
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      taskId: json['task_id'] as int,
      shiftId: json['shift_id'] as int,
      details: json['details'] as String?,
      status: json['status'] as bool? ?? false,
      comment: json['comment'] as String?,
      taskCode: json['task_code'] as String?,
      isFromClient: false,
      isFromShiftTaskId: false,
    );
  }

  /// Parse from the shift's `task_id` column which is a comma-separated string.
  ///
  /// Example: "task1,task2,task3,task4,task5"
  /// Each item becomes a separate Task with its own checkbox.
  static List<Task> fromCommaSeparated(String? taskIdString,
      {int shiftId = 0}) {
    if (taskIdString == null || taskIdString.trim().isEmpty) return [];

    final items = taskIdString
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return List.generate(items.length, (i) {
      return Task(
        taskId: i + 1, // Synthetic ID (1-based index)
        shiftId: shiftId,
        details: items[i],
        status: false,
        isFromShiftTaskId: true,
      );
    });
  }

  /// Parse from the `client_final.tasks` JSONB array.
  ///
  /// The JSONB can be in several formats:
  ///   - List of strings:       ["Task A", "Task B"]
  ///   - List of objects:       [{"name": "Task A", "status": false}, ...]
  ///   - Object with keys:      {"task1": "Task A", "task2": "Task B"}
  ///   - List of objects (alt): [{"details": "Task A", "completed": false}, ...]
  static List<Task> fromClientTasksJson(dynamic tasksJson, {int shiftId = 0}) {
    if (tasksJson == null) return [];

    final List<Task> result = [];

    if (tasksJson is List) {
      for (int i = 0; i < tasksJson.length; i++) {
        final item = tasksJson[i];
        if (item is String) {
          // Simple string list: ["Task A", "Task B"]
          result.add(Task(
            taskId: i + 1,
            shiftId: shiftId,
            details: item,
            status: false,
            isFromClient: true,
          ));
        } else if (item is Map) {
          // Object list: [{"name": "Task A", "status": false}, ...]
          final details = (item['name'] ??
                  item['details'] ??
                  item['description'] ??
                  item['task'] ??
                  item['title'] ??
                  'Task ${i + 1}')
              ?.toString();
          final status = item['status'] == true ||
              item['completed'] == true ||
              item['done'] == true;
          result.add(Task(
            taskId: (item['id'] as num?)?.toInt() ?? (i + 1),
            shiftId: shiftId,
            details: details,
            status: status,
            comment: item['comment']?.toString() ?? item['notes']?.toString(),
            taskCode: item['task_code']?.toString() ?? item['code']?.toString(),
            isFromClient: true,
          ));
        }
      }
    } else if (tasksJson is Map) {
      // Object with keys: {"task1": "Task A", "task2": "Task B"}
      int index = 0;
      tasksJson.forEach((key, value) {
        if (value is String) {
          result.add(Task(
            taskId: index + 1,
            shiftId: shiftId,
            details: value,
            status: false,
            isFromClient: true,
          ));
        } else if (value is Map) {
          final details =
              (value['name'] ?? value['details'] ?? value['description'] ?? key)
                  ?.toString();
          final status = value['status'] == true ||
              value['completed'] == true ||
              value['done'] == true;
          result.add(Task(
            taskId: (value['id'] as num?)?.toInt() ?? (index + 1),
            shiftId: shiftId,
            details: details,
            status: status,
            comment: value['comment']?.toString(),
            isFromClient: true,
          ));
        }
        index++;
      });
    }

    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'shift_id': shiftId,
      'details': details,
      'status': status,
      'comment': comment,
      'task_code': taskCode,
    };
  }

  Task copyWith({
    int? taskId,
    int? shiftId,
    String? details,
    bool? status,
    String? comment,
    String? taskCode,
    bool? isFromClient,
    bool? isFromShiftTaskId,
    String? shiftTaskLogStatus,
    String? skipReason,
  }) {
    return Task(
      taskId: taskId ?? this.taskId,
      shiftId: shiftId ?? this.shiftId,
      details: details ?? this.details,
      status: status ?? this.status,
      comment: comment ?? this.comment,
      taskCode: taskCode ?? this.taskCode,
      isFromClient: isFromClient ?? this.isFromClient,
      isFromShiftTaskId: isFromShiftTaskId ?? this.isFromShiftTaskId,
      shiftTaskLogStatus: shiftTaskLogStatus ?? this.shiftTaskLogStatus,
      skipReason: skipReason ?? this.skipReason,
    );
  }
}
