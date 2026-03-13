/// Centralized Supabase table name constants.
/// Use these constants everywhere instead of raw string literals.
/// This makes future table renames a single-line change.
class Tables {
  Tables._(); // Prevent instantiation

  /// Primary employee table (migrated from 'employee')
  static const String employee = 'employee_final';

  /// Primary client table (migrated from 'client' → 'client_staging' → 'client_final')
  static const String client = 'client_final';

  // ──────────────────────────────────────────────────────────────
  // Tables that must NOT be changed — kept here for documentation
  // ──────────────────────────────────────────────────────────────
  static const String shift = 'shift';
  static const String dailyShift = 'daily_shift';
  static const String timeLogs = 'time_logs';
  static const String tasks = 'tasks';
  static const String shiftOffers = 'shift_offers';
  static const String shiftChangeRequests = 'shift_change_requests';
  static const String leaves = 'leaves';
  static const String injuryReports = 'injury_reports';
  static const String incidentReports = 'incident_reports';
  static const String hazardNearMissReports = 'hazard_near_miss_reports';
  static const String supervisors = 'supervisors';
}
