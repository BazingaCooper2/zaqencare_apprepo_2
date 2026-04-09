import '../main.dart';
import 'package:intl/intl.dart';

class AnalyticsService {
  static Future<Map<String, dynamic>> getPerformanceMetrics(dynamic empId) async {
    try {
      // 1. Fetch all records from analytics_daily for this employee
      
      // Total Hours, Overtime, Completed Shifts, Shift Distribution, Tasks Completed
      final allResponse = await supabase
          .from('analytics_daily')
          .select('total_hours, overtime_hours, completed_shifts, inprogress_shifts, cancelled_shifts, tasks_completed')
          .eq('emp_id', empId);

      double totalHours = 0;
      double overtimeHours = 0;
      int completedShifts = 0;
      int inProgressShifts = 0;
      int cancelledShifts = 0;
      int tasksCompleted = 0;

      for (var row in allResponse) {
        totalHours += (row['total_hours'] ?? 0).toDouble();
        overtimeHours += (row['overtime_hours'] ?? 0).toDouble();
        completedShifts += (row['completed_shifts'] ?? 0) as int;
        inProgressShifts += (row['inprogress_shifts'] ?? 0) as int;
        cancelledShifts += (row['cancelled_shifts'] ?? 0) as int;
        tasksCompleted += (row['tasks_completed'] ?? 0) as int;
      }

      // 2. This Month Hours
      final now = DateTime.now();
      final monthResponse = await supabase
          .from('analytics_daily')
          .select('total_hours')
          .eq('emp_id', empId)
          .eq('month', now.month)
          .eq('year', now.year);

      double monthlyHours = 0;
      for (var row in monthResponse) {
        monthlyHours += (row['total_hours'] ?? 0).toDouble();
      }

      // 3. Weekly Activity Chart
      // Get the last 7 days from analytics_daily
      final sevenDaysAgo = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 6)));
      final weeklyResponse = await supabase
          .from('analytics_daily')
          .select('date, total_hours')
          .eq('emp_id', empId)
          .gte('date', sevenDaysAgo)
          .order('date', ascending: true);

      return {
        'totalHours': totalHours,
        'overtimeHours': overtimeHours,
        'monthlyHours': monthlyHours,
        'completedShifts': completedShifts,
        'tasksCompleted': tasksCompleted,
        'shiftDistribution': {
          'completed': completedShifts,
          'in_progress': inProgressShifts,
          'cancelled': cancelledShifts,
        },
        'weeklyActivity': weeklyResponse,
      };
    } catch (e) {
      print('Error fetching performance metrics: $e');
      rethrow;
    }
  }
}
