import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import '../main.dart';
import '../services/session.dart';
import '../services/email_service.dart';

class HazardNearMissForm extends StatefulWidget {
  const HazardNearMissForm({super.key});

  @override
  State<HazardNearMissForm> createState() => _HazardNearMissFormState();
}

class _HazardNearMissFormState extends State<HazardNearMissForm> {
  final _formKey = GlobalKey<FormState>();

  // Part 1: Report Completed By
  final _telephoneController = TextEditingController();
  final _supervisorController = TextEditingController();
  final _locationController = TextEditingController(); // Incident Location
  final _hazardStatementController = TextEditingController();
  final _immediateActionController = TextEditingController();
  final _reasonForDelayController = TextEditingController();

  // Part 2: Individuals Involved
  final _workersController = TextEditingController();
  final _clientsController = TextEditingController();
  final _othersController = TextEditingController();

  // Part 5: Signature
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _signatureImage;
  String? _uploadedSignatureUrl;

  // Part 6: Witness Remarks
  final _witnessNameController = TextEditingController();
  final _witnessRemarksController = TextEditingController();

  // Dates and Times
  DateTime? _incidentDate;
  TimeOfDay? _incidentTime;
  DateTime? _reportedDate;
  TimeOfDay? _reportedTime;

  String? _hazardRating;
  List<String> _selectedHazardTypes = [];
  bool _documentedOnBoard = false;
  bool _isSubmitting = false;

  final List<String> _hazardRatingOptions = ['SERIOUS', 'MINOR_NEAR_MISS'];

  // Expanded Hazard Types based on common forms
  final List<String> _hazardTypeOptions = [
    'Biological',
    'Chemical',
    'Client Action',
    'Energy',
    'Environmental',
    'Ergonomic/Work Design',
    'Material Handling',
    'Mechanical',
    'Physical',
    'Violence',
    'Work Practices',
    'Slip/Trip/Fall', // Kept generic ones too just in case
    'Equipment Malfunction',
    'Fire Hazard',
    'Electrical',
    'Other',
  ];

  @override
  void dispose() {
    _telephoneController.dispose();
    _supervisorController.dispose();
    _locationController.dispose();
    _hazardStatementController.dispose();
    _immediateActionController.dispose();
    _reasonForDelayController.dispose();
    _workersController.dispose();
    _clientsController.dispose();
    _othersController.dispose();
    _witnessNameController.dispose();
    _witnessRemarksController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isReportedDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isReportedDate) {
          _reportedDate = picked;
        } else {
          _incidentDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isReportedTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isReportedTime) {
          _reportedTime = picked;
        } else {
          _incidentTime = picked;
        }
      });
    }
  }

  Future<String?> _uploadSignatureToSupabase(Uint8List signatureBytes) async {
    try {
      final supabase = Supabase.instance.client;
      final fileName =
          'hazard_sig_${DateTime.now().millisecondsSinceEpoch}.png';

      // Using injury_signatures bucket as it exists for signatures
      await supabase.storage
          .from('injury_signatures')
          .uploadBinary(fileName, signatureBytes);

      final publicUrl =
          supabase.storage.from('injury_signatures').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading signature: $e');
      return null;
    }
  }

  String _val(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? 'N/A' : text;
  }

  Future<void> _submitForm() async {
    print("SUBMITTING HAZARD REPORT SESSION: ${Supabase.instance.client.auth.currentSession}");
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) {
        if (mounted) {
          context.showSnackBar('You must be logged in to submit a report.',
              isError: true);
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Upload signature if exists
      if (_signatureImage != null) {
        final uploadedUrl = await _uploadSignatureToSupabase(_signatureImage!);
        if (uploadedUrl != null) {
          _uploadedSignatureUrl = uploadedUrl;
        }
      }

      final fullName = await SessionManager.getFullName();
      final reporterName = fullName.isEmpty ? 'N/A' : fullName;

      final data = {
        'emp_id': empId,
        'reported_date': _reportedDate != null ? DateFormat('yyyy-MM-dd').format(_reportedDate!) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'reported_time': _reportedTime != null 
          ? '${_reportedTime!.hour.toString().padLeft(2, '0')}:${_reportedTime!.minute.toString().padLeft(2, '0')}:00' 
          : DateFormat('HH:mm:ss').format(DateTime.now()),
        'incident_date': _incidentDate != null ? DateFormat('yyyy-MM-dd').format(_incidentDate!) : null,
        'incident_time': _incidentTime != null ? '${_incidentTime!.hour.toString().padLeft(2, '0')}:${_incidentTime!.minute.toString().padLeft(2, '0')}:00' : null,
        'incident_location': _val(_locationController),
        'documented_on_hazard_board': _documentedOnBoard,
        'delay_reason': _val(_reasonForDelayController),
        'hazard_rating': _hazardRating ?? 'N/A',
        'hazard_types': _selectedHazardTypes.isEmpty ? ['N/A'] : _selectedHazardTypes,
        'hazard_statement': _val(_hazardStatementController),
        'hazard_details': _val(_hazardStatementController),
        'immediate_action': _val(_immediateActionController),
        'phone': int.tryParse(_telephoneController.text.trim()),
        'supervisor_notified': _val(_supervisorController),
        'workers_involved': _val(_workersController),
        'clients_involved': _val(_clientsController),
        'others_involved': _val(_othersController),
        'witness_name': _val(_witnessNameController),
        'witness_statement': _val(_witnessRemarksController),
        'reporter_signature': _uploadedSignatureUrl != null ? {'url': _uploadedSignatureUrl} : null,
        'reporter_name': reporterName,
        'status': 'Submitted',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Insert into Supabase
      final response = await supabase.from('hazard_near_miss_reports').insert(data).select();
      
      print("🚀 Hazard Insert Result: $response");
      debugPrint('✅ Hazard report successfully inserted into Supabase');

      // Send email notification (passing distinct fields for better formatting)
      final emailSent = await EmailService.sendHazardReportEmail(
        incidentDate: _incidentDate != null ? DateFormat('yyyy-MM-dd').format(_incidentDate!) : 'N/A',
        incidentTime: _incidentTime != null ? '${_incidentTime!.hour.toString().padLeft(2, '0')}:${_incidentTime!.minute.toString().padLeft(2, '0')}' : 'N/A',
        location: _val(_locationController),
        hazardRating: _hazardRating ?? 'N/A',
        hazardTypes: _selectedHazardTypes.isEmpty ? ['N/A'] : _selectedHazardTypes,
        hazardStatement: _val(_hazardStatementController),
        immediateAction: _val(_immediateActionController),
        // New fields for email
        telephone: _telephoneController.text.trim(),
        supervisor: _supervisorController.text.trim(),
        dateReported: _reportedDate != null
            ? DateFormat('yyyy-MM-dd').format(_reportedDate!)
            : 'N/A',
        timeReported: _reportedTime != null
            ? (mounted ? _reportedTime!.format(context) : 'N/A')
            : 'N/A',
        reasonForDelay: _reasonForDelayController.text.trim(),
        involvedWorkers: _workersController.text.trim(),
        involvedClients: _clientsController.text.trim(),
        involvedOthers: _othersController.text.trim(),
        witnessName: _witnessNameController.text.trim(),
        witnessRemarks: _witnessRemarksController.text.trim(),
        signatureUrl: _uploadedSignatureUrl,
        signatureImage: _signatureImage,
      );

      if (mounted) {
        if (emailSent) {
          context.showSnackBar('✅ Hazard report submitted & email sent');
        } else {
          context.showSnackBar('⚠️ Report saved but failed to send email');
        }
      }

      _resetForm();
    } catch (e) {
      if (mounted) {
        context.showSnackBar('❌ Failed to submit report: $e', isError: true);
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _telephoneController.clear();
    _supervisorController.clear();
    _locationController.clear();
    _hazardStatementController.clear();
    _immediateActionController.clear();
    _reasonForDelayController.clear();
    _workersController.clear();
    _clientsController.clear();
    _othersController.clear();
    _witnessNameController.clear();
    _witnessRemarksController.clear();
    _signatureController.clear();
    setState(() {
      _incidentDate = null;
      _incidentTime = null;
      _reportedDate = null;
      _reportedTime = null;
      _hazardRating = null;
      _selectedHazardTypes = [];
      _documentedOnBoard = false;
      _signatureImage = null;
      _uploadedSignatureUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('PART 1: REPORT COMPLETED BY'),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _telephoneController,
            label: 'Telephone Number',
            icon: Icons.phone_rounded,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _supervisorController,
            label: 'Supervisor/Designate reported to',
            icon: Icons.person_search_rounded,
          ),
          const SizedBox(height: 16),

          // Row 3: Date Reported & Time
          Row(
            children: [
              Expanded(
                  child: _buildDateTimePicker(
                      context, 'Date Reported', true, true)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDateTimePicker(
                      context, 'Time Reported', false, true)),
            ],
          ),
          const SizedBox(height: 16),

          // Row 4: Date Incident & Time
          Row(
            children: [
              Expanded(
                  child: _buildDateTimePicker(
                      context, 'Date of Incident', true, false)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDateTimePicker(
                      context, 'Time of Incident', false, false)),
            ],
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _locationController,
            label: 'Location of Incident',
            icon: Icons.place_rounded,
          ),
          const SizedBox(height: 16),

          _buildTextField(
            controller: _reasonForDelayController,
            label: 'Reason for delay (if any)',
            required: false,
          ),

          const SizedBox(height: 32),
          _buildSectionHeader('PART 2: INDIVIDUALS INVOLVED'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _workersController,
              label: 'Workers Involved',
              required: false,
              icon: Icons.group_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _clientsController,
              label: 'Clients Involved',
              required: false,
              icon: Icons.person_outline_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _othersController,
              label: 'Other Individuals',
              required: false,
              icon: Icons.info_outline_rounded),

          const SizedBox(height: 32),
          _buildSectionHeader('PART 3: HAZARD RATING'),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Select Hazard Rating',
            value: _hazardRating,
            options: _hazardRatingOptions,
            onChanged: (value) => setState(() => _hazardRating = value),
            formatter: (value) => value.replaceAll('_', ' '),
          ),

          const SizedBox(height: 32),
          _buildSectionHeader('PART 4: TYPE OF HAZARD'),
          const SizedBox(height: 16),
          _buildHazardTypesSelector(),

          const SizedBox(height: 32),
          _buildSectionHeader('PART 5: STATEMENT OF HAZARD'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _hazardStatementController,
            label: 'Statement of Hazard/Incident',
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _immediateActionController,
            label: 'Immediate Action Taken',
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Signature
          const Text('Reporter Signature',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Signature(
                    controller: _signatureController,
                    height: 150,
                    backgroundColor: Colors.white,
                  ),
                  Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 20, color: Colors.red),
                          label: const Text('Clear', style: TextStyle(color: Colors.red)),
                          onPressed: () => _signatureController.clear(),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF1A73E8)),
                          label: const Text('Save Signature', style: TextStyle(color: Color(0xFF1A73E8))),
                          onPressed: () async {
                            final signature = await _signatureController.toPngBytes();
                            if (signature != null) {
                              setState(() => _signatureImage = signature);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Signature captured!')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_signatureImage != null) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                SizedBox(width: 8),
                Text('Signature ready', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
              ],
            ),
          ],

          const SizedBox(height: 32),
          _buildSectionHeader('PART 6: WITNESS REMARKS'),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _witnessNameController,
            label: 'Witness Name',
            required: false,
            icon: Icons.person_pin_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _witnessRemarksController,
            label: 'Remarks / Statement',
            maxLines: 3,
            required: false,
          ),

          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: CheckboxListTile(
              title: const Text('Documented on Hazard Board', 
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              value: _documentedOnBoard,
              onChanged: (value) => setState(() => _documentedOnBoard = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF1A73E8),
            ),
          ),

          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        border: const Border(left: BorderSide(color: Color(0xFF1A73E8), width: 4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1A73E8),
          fontWeight: FontWeight.w900,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDateTimePicker(
      BuildContext context, String label, bool isDate, bool isReported) {
    final valDate = isReported ? _reportedDate : _incidentDate;
    final valTime = isReported ? _reportedTime : _incidentTime;

    String text = 'Tap to select';
    if (isDate) {
      if (valDate != null) text = DateFormat('yyyy-MM-dd').format(valDate);
    } else {
      if (valTime != null) text = valTime.format(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => isDate
              ? _selectDate(context, isReported)
              : _selectTime(context, isReported),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(isDate ? Icons.calendar_today_rounded : Icons.access_time_rounded,
                  size: 18, color: const Color(0xFF1A1A2E)),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w500))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool required = true,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: icon != null ? Icon(icon, size: 20, color: const Color(0xFF1A1A2E)) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 1.5)),
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required Function(String?) onChanged,
    String Function(String)? formatter,
  }) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: options
          .map((option) => DropdownMenuItem(
                value: option,
                child: Text(formatter != null ? formatter(option) : option),
              ))
          .toList(),
      onChanged: onChanged,
      validator: null, // Removed validation requirement
    );
  }

  Widget _buildHazardTypesSelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _hazardTypeOptions.map((type) {
          final isSelected = _selectedHazardTypes.contains(type);
          return FilterChip(
            label: Text(type),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedHazardTypes.add(type);
                } else {
                  _selectedHazardTypes.remove(type);
                }
              });
            },
            selectedColor: Colors.blue.shade100,
            checkmarkColor: Colors.blue.shade700,
          );
        }).toList(),
      ),
    );
  }
}
