import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final baseUrl = 'https://asbfhxdomvclwsrekdxi.supabase.co/rest/v1';
  final key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFzYmZoeGRvbXZjbHdzcmVrZHhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMjI3OTUsImV4cCI6MjA2OTg5ODc5NX0.0VzbWIc-uxIDhI03g04n8HSPRQ_p01UTJQ1sg8ggigU';
  
  final headers = {
    'apikey': key,
    'Authorization': 'Bearer $key',
  };

  print('Checking Shift #2007 specifically...');
  final r = await http.get(Uri.parse('$baseUrl/shift?shift_id=eq.2007&select=*'), headers: headers);
  print('Result: ${r.body}');
}
