import 'package:flutter/material.dart';
import '../widgets/hazard_near_miss_form.dart';
import '../widgets/incident_report_form_widget.dart';
import '../widgets/employee_injury_form.dart';

class UnifiedReportsForm extends StatefulWidget {
  const UnifiedReportsForm({super.key});

  @override
  State<UnifiedReportsForm> createState() => _UnifiedReportsFormState();
}

class _UnifiedReportsFormState extends State<UnifiedReportsForm> {
  String? _selectedReportType;

  final List<String> _reportTypes = [
    'Hazard / Near Miss',
    'Incident Report',
    'Employee Injury / Illness',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F0EE),
      appBar: AppBar(
        title: const Text('Submit Report',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: -0.3)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Type',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedReportType,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.assignment_turned_in_rounded,
                            color: Color(0xFF1A73E8)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 1.5),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      hint: const Text('Select form to fill'),
                      items: _reportTypes
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedReportType = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Display the selected form
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _selectedReportType == null
                  ? Container(
                      key: const ValueKey('empty'),
                      padding: const EdgeInsets.symmetric(
                          vertical: 60, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0EE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.post_add_rounded,
                              size: 48,
                              color: Color(0xFF1A73E8),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Ready to File',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Select a report category above to begin filling out the form.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      key: ValueKey(_selectedReportType),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: _buildSelectedForm(),
                        ),
                      ),
                    ),
            ),
            // Extra padding at bottom
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedForm() {
    switch (_selectedReportType) {
      case 'Hazard / Near Miss':
        return const HazardNearMissForm();
      case 'Incident Report':
        return const IncidentReportFormWidget();
      case 'Employee Injury / Illness':
        return const EmployeeInjuryForm();
      default:
        return const SizedBox.shrink();
    }
  }
}
