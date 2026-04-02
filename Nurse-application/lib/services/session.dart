import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionManager {
  static int? empId;
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<void> saveSession(Map<String, dynamic> employee) async {
    final prefs = await SharedPreferences.getInstance();
    empId = employee['emp_id'];
    await prefs.setInt('emp_id', employee['emp_id']);
    await prefs.setString('first_name', employee['first_name']);
    await prefs.setString('last_name', employee['last_name']);
    await prefs.setString('email', employee['email']);
    await prefs.setString('designation', employee['designation'] ?? '');
    await prefs.setString('image_url', employee['image_url'] ?? '');
  }

  static Future<String> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getString('first_name') ?? '';
    final last = prefs.getString('last_name') ?? '';
    return '$first $last'.trim();
  }

  static Future<int?> getEmpId() async {
    if (empId != null) return empId;
    final prefs = await SharedPreferences.getInstance();
    empId = prefs.getInt('emp_id');
    return empId;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    empId = null;
  }

  /// ✅ Automatically link Logged-in User to Employee Table
  static Future<int> getOrCreateEmployeeLink() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    final userId = user.id;
    final userEmail = user.email;

    print("🔐 AUTH USER ID: $userId");
    print("📧 AUTH EMAIL: $userEmail");

    // Step 1: Check if already linked
    final List<dynamic> existingEmployee = await _supabase
        .from('employee')
        .select('emp_id')
        .eq('user_id', userId)
        .limit(1);

    if (existingEmployee.isNotEmpty) {
      final id = existingEmployee.first['emp_id'] as int;
      empId = id;
      print("✅ Employee already linked. emp_id: $id");
      return id;
    }

    // Step 2: Find employee by email
    final List<dynamic> employeeByEmail = await _supabase
        .from('employee')
        .select('emp_id, user_id')
        .eq('email', userEmail!)
        .limit(1);

    int id;

    if (employeeByEmail.isNotEmpty) {
      // Employee exists → link it
      id = employeeByEmail.first['emp_id'] as int;
      final existingUserId = employeeByEmail.first['user_id'];

      if (existingUserId == null || existingUserId != userId) {
        await _supabase
            .from('employee')
            .update({'user_id': userId})
            .eq('emp_id', id);

        print("🔗 Employee linked to this auth user. emp_id: $id");
      }
    } else {
      // Step 3: Create new employee automatically
      final newEmployee = await _supabase
          .from('employee')
          .insert({
            'email': userEmail,
            'first_name': 'New',
            'last_name': 'User',
            'user_id': userId,
            'designation': 'employee'
          })
          .select()
          .single();

      id = newEmployee['emp_id'];
      print("🆕 New employee created. emp_id: $id");
    }

    empId = id;
    print("✅ Session EMP ID set: $empId");

    return id;
  }
}
