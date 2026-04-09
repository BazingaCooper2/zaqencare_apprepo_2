import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionManager {
  static int? empId;
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<String> getFullName() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 'Nurse';

    try {
      final response = await _supabase
          .from('employee')
          .select('first_name, last_name')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        final first = response['first_name'] ?? '';
        final last = response['last_name'] ?? '';
        return '$first $last'.trim();
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching full name: $e');
    }
    return 'Nurse';
  }

  static Future<int?> getEmpId() async {
    if (empId != null) return empId;
    return await getOrCreateEmployeeLink();
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
            .update({'user_id': userId}).eq('emp_id', id);

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
