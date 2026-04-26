import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/tables.dart';

class SessionManager {
  static int? _empId;
  static Map<String, dynamic>? _employeeData;
  static SupabaseClient get _supabase => Supabase.instance.client;

  static const String _keyEmpId = 'logged_in_emp_id';

  /// ✅ Get the logged-in employee ID
  static Future<int?> getEmpId() async {
    if (_empId != null) return _empId;
    
    final prefs = await SharedPreferences.getInstance();
    _empId = prefs.getInt(_keyEmpId);
    return _empId;
  }

  /// ✅ Save specific employee session
  static Future<void> saveSession(Map<String, dynamic> employee) async {
    final prefs = await SharedPreferences.getInstance();
    _empId = employee['emp_id'] as int;
    _employeeData = employee;
    await prefs.setInt(_keyEmpId, _empId!);
    debugPrint('✅ Manual session saved for emp_id: $_empId');
  }

  /// ✅ Clear session on logout
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmpId);
    _empId = null;
    _employeeData = null;
    debugPrint('🚪 Session cleared');
  }

  /// ✅ Check if any user is logged in
  static Future<bool> isLoggedIn() async {
    final id = await getEmpId();
    return id != null;
  }

  /// ✅ Fetch full name of the logged-in employee
  static Future<String> getFullName() async {
    final id = await getEmpId();
    if (id == null) return 'Nurse';

    try {
      if (_employeeData != null && _employeeData!['emp_id'] == id) {
        final first = _employeeData!['first_name'] ?? '';
        final last = _employeeData!['last_name'] ?? '';
        return '$first $last'.trim();
      }

      final response = await _supabase
          .from(Tables.employee)
          .select('first_name, last_name')
          .eq('emp_id', id)
          .maybeSingle();

      if (response != null) {
        _employeeData = response;
        final first = response['first_name'] ?? '';
        final last = response['last_name'] ?? '';
        return '$first $last'.trim();
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching full name: $e');
    }
    return 'Nurse';
  }

  /// ✅ Legacy method kept for compatibility but refactored
  static Future<int> getOrCreateEmployeeLink() async {
    final id = await getEmpId();
    if (id != null) return id;
    throw Exception("User not logged in");
  }

  /// ✅ Helper to get current employee data
  static Future<Map<String, dynamic>?> getEmployeeData() async {
    final id = await getEmpId();
    if (id == null) return null;

    if (_employeeData != null && _employeeData!['emp_id'] == id) {
      return _employeeData;
    }

    try {
      final response = await _supabase
          .from(Tables.employee)
          .select()
          .eq('emp_id', id)
          .maybeSingle();
      
      _employeeData = response;
      return response;
    } catch (e) {
      debugPrint('⚠️ Error fetching employee data: $e');
      return null;
    }
  }
}
