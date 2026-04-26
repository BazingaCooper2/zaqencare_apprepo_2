import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:signature/signature.dart';
import '../main.dart';
import '../services/session.dart';
import '../services/email_service.dart';

class EmployeeInjuryForm extends StatefulWidget {
  const EmployeeInjuryForm({super.key});

  @override
  State<EmployeeInjuryForm> createState() => _EmployeeInjuryFormState();
}

class _EmployeeInjuryFormState extends State<EmployeeInjuryForm> {
  final _formKey = GlobalKey<FormState>();

  // PART 1: REPORT COMPLETED BY
  final _supervisorReportedToController = TextEditingController();
  final _reasonForDelayController = TextEditingController();
  DateTime? _dateReported;

  // PART 2: PERSONAL DATA
  final _employeeNameController =
      TextEditingController(); // Manual override or auto-filled
  final _employeePhoneController = TextEditingController();
  final _employeeEmailController = TextEditingController();
  final _employeeAddressController = TextEditingController();
  bool _returnToWorkPackageTaken = false;

  // PART 3: INJURY DETAILS
  DateTime? _injuryDate;
  TimeOfDay? _injuryTime;
  TimeOfDay? _timeLeftWork;
  final _programController = TextEditingController();
  final _locationController = TextEditingController();
  final _clientInvolvedController = TextEditingController(); // Name and phone

  // PART 4: BODY PARTS (Checkbox state)
  final Map<String, bool> _bodyParts = {
    'Head': false,
    'Teeth': false,
    'Upper Back': false,
    'Lower Back': false,
    'Shoulder': false,
    'Wrist': false,
    'Hip': false,
    'Ankle': false,
    'Face': false,
    'Neck': false,
    'Fingers': false,
    'Eye': false,
    'Chest': false,
    'Abdomen': false,
    'Elbow': false,
    'Ears': false,
    'Pelvis': false,
    'Forearm': false,
    'Lower Legs': false,
    'Other': false
  };
  final _otherBodyPartController = TextEditingController();

  // PART 5: INJURY DETAILS DESCRIPTION
  final _descriptionController =
      TextEditingController(); // "Describe what happened..."

  // PART 6: WITNESS REMARKS
  final _witnessNameController = TextEditingController();
  final _witnessPhoneController = TextEditingController();

  // PART 7: HCP DETAILS (If medical attention required)
  bool _medicalAttentionRequired = false;
  final _hcpNameController = TextEditingController();
  final _hcpAddressController = TextEditingController();
  final _hcpPhoneController = TextEditingController();
  bool _broughtFafForm = false;

  // Signature
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _signatureImage;
  String? _uploadedSignatureUrl;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _supervisorReportedToController.dispose();
    _reasonForDelayController.dispose();
    _employeeNameController.dispose();
    _employeePhoneController.dispose();
    _employeeEmailController.dispose();
    _employeeAddressController.dispose();
    _programController.dispose();
    _locationController.dispose();
    _clientInvolvedController.dispose();
    _otherBodyPartController.dispose();
    _descriptionController.dispose();
    _witnessNameController.dispose();
    _witnessPhoneController.dispose();
    _hcpNameController.dispose();
    _hcpAddressController.dispose();
    _hcpPhoneController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isReported) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isReported) {
          _dateReported = picked;
        } else {
          _injuryDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isLeftWork) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isLeftWork) {
          _timeLeftWork = picked;
        } else {
          _injuryTime = picked;
        }
      });
    }
  }

  Future<String?> _uploadSignatureToSupabase(Uint8List signatureBytes) async {
    try {
      final supabase = Supabase.instance.client;
      final fileName =
          'injury_sig_${DateTime.now().millisecondsSinceEpoch}.png';
      await supabase.storage
          .from('injury_signatures')
          .uploadBinary(fileName, signatureBytes);
      return supabase.storage.from('injury_signatures').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Error uploading signature: $e');
      return null;
    }
  }

  Future<void> _submitForm() async {
    print("SUBMITTING INJURY REPORT SESSION: ${Supabase.instance.client.auth.currentSession}");
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) {
        if (mounted) {
          context.showSnackBar('You must be logged in.', isError: true);
        }
        setState(() => _isSubmitting = false);
        return;
      }

      if (_signatureImage != null) {
        _uploadedSignatureUrl =
            await _uploadSignatureToSupabase(_signatureImage!);
      }

      final bodyPartsList =
          _bodyParts.entries.where((e) => e.value).map((e) => e.key).toList();
      final bodyPartsMap = <String, dynamic>{for (var e in bodyPartsList) e: true};
      
      if (_otherBodyPartController.text.trim().isNotEmpty) {
        bodyPartsMap['Other_Details'] = _otherBodyPartController.text.trim();
      }

      String _val(TextEditingController c) {
        final text = c.text.trim();
        return text.isEmpty ? 'N/A' : text;
      }

      final fullName = await SessionManager.getFullName();
      final reporterName = fullName.isEmpty ? 'N/A' : fullName;

      final data = {
        'emp_id': empId,
        'date': _injuryDate != null ? DateFormat('yyyy-MM-dd').format(_injuryDate!) : DateFormat('yyyy-MM-dd').format(DateTime.now()), // required 'date' field
        'injury_date': _injuryDate != null ? DateFormat('yyyy-MM-dd').format(_injuryDate!) : null,
        'injury_time': _injuryTime != null ? '${_injuryTime!.hour.toString().padLeft(2, '0')}:${_injuryTime!.minute.toString().padLeft(2, '0')}:00' : null,
        'reported_date': _dateReported != null ? DateFormat('yyyy-MM-dd').format(_dateReported!) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'delay_reason': _val(_reasonForDelayController),
        'program': _val(_programController),
        'location': _val(_locationController),
        'description': _val(_descriptionController),
        'injured_body_parts': bodyPartsMap,
        'medical_attention_required': _medicalAttentionRequired,
        'rtw_package_taken': _returnToWorkPackageTaken,
        'time_left_work': _timeLeftWork != null ? '${_timeLeftWork!.hour.toString().padLeft(2, '0')}:${_timeLeftWork!.minute.toString().padLeft(2, '0')}:00' : null,
        'client_involved': _val(_clientInvolvedController),
        'witness_name': _val(_witnessNameController),
        'witness_phone': _val(_witnessPhoneController),
        'hcp_name': _val(_hcpNameController),
        'hcp_address': _val(_hcpAddressController),
        'hcp_phone': _val(_hcpPhoneController),
        'faf_form_brought': _broughtFafForm,
        'signature_url': _uploadedSignatureUrl,
        'employee_signature': _uploadedSignatureUrl != null ? {'url': _uploadedSignatureUrl} : null,
        'reporter_name': reporterName,
        'emp_name': _val(_employeeNameController),
        'emp_phone': _val(_employeePhoneController),
        'emp_email': _val(_employeeEmailController),
        'emp_address': _val(_employeeAddressController),
        'reported_to_supervisor_name': _val(_supervisorReportedToController),
        'status': 'Submitted',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Insert into Supabase with .select()
      final response = await supabase.from('injury_reports').insert(data).select();
      
      print("🚀 Injury Insert Result: $response");
      debugPrint('✅ Injury report successfully inserted into Supabase');

      final emailSent = await EmailService.sendInjuryReportEmail(
        injuryDate: _injuryDate != null ? DateFormat('yyyy-MM-dd').format(_injuryDate!) : 'N/A',
        injuryTime: _injuryTime != null
            ? (mounted ? _injuryTime!.format(context) : 'N/A')
            : 'N/A',
        program: _val(_programController),
        description: _val(_descriptionController),
        bodyParts: bodyPartsList,
        medicalAttentionRequired: _medicalAttentionRequired,
        signatureImage: _signatureImage,
        // Detailed fields
        supervisorReportedTo: _supervisorReportedToController.text.trim(),
        dateReported: _dateReported != null
            ? DateFormat('yyyy-MM-dd').format(_dateReported!)
            : 'N/A',
        employeeName: _employeeNameController.text.trim(),
        employeePhone: _employeePhoneController.text.trim(),
        timeLeftWork: _timeLeftWork != null
            ? (mounted ? _timeLeftWork!.format(context) : 'N/A')
            : 'N/A',
        location: _locationController.text.trim(),
        clientInvolved: _clientInvolvedController.text.trim(),
        witnessName: _witnessNameController.text.trim(),
        hcpDetails: _medicalAttentionRequired
            ? "Name: ${_hcpNameController.text}\nAddress: ${_hcpAddressController.text}\nPhone: ${_hcpPhoneController.text}"
            : "N/A",
      );

      if (mounted) {
        if (emailSent) {
          context.showSnackBar('✅ Report submitted & email sent');
        } else {
          context.showSnackBar('⚠️ Saved but email failed');
        }
      }
      _resetForm();
    } catch (e) {
      if (mounted) context.showSnackBar('❌ Error: $e', isError: true);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _supervisorReportedToController.clear();
    _reasonForDelayController.clear();
    _employeeNameController.clear();
    _employeePhoneController.clear();
    _employeeEmailController.clear();
    _employeeAddressController.clear();
    _programController.clear();
    _locationController.clear();
    _clientInvolvedController.clear();
    _otherBodyPartController.clear();
    _descriptionController.clear();
    _witnessNameController.clear();
    _witnessPhoneController.clear();
    _hcpNameController.clear();
    _hcpAddressController.clear();
    _hcpPhoneController.clear();
    _signatureController.clear();
    setState(() {
      _injuryDate = null;
      _injuryTime = null;
      _dateReported = null;
      _timeLeftWork = null;
      _returnToWorkPackageTaken = false;
      _medicalAttentionRequired = false;
      _broughtFafForm = false;
      _signatureImage = null;
      _uploadedSignatureUrl = null;
      _bodyParts.updateAll((key, value) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFECB3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF856404), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: const Text(
                        'IMMEDIATELY contact and speak to your supervisor/designate.',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Color(0xFF856404), fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Use Emergency Notification System if necessary.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF856404))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('PART 1: REPORT COMPLETED BY'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _supervisorReportedToController,
              label: 'Illness/Injury Reported To (Name)',
              icon: Icons.person_search_rounded),
          const SizedBox(height: 16),
          _buildDateTimePicker(context, 'Date Reported', true, true),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _reasonForDelayController,
              label: 'Reason for delay (if any)',
              required: false),
          const SizedBox(height: 32),
          _buildSectionHeader('PART 2: PERSONAL DATA'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _employeeNameController,
              label: 'Employee Name (Full Name)',
              required: false,
              icon: Icons.badge_outlined),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _employeePhoneController,
              label: 'Telephone Number',
              icon: Icons.phone_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _employeeAddressController,
              label: 'Current Address',
              icon: Icons.home_rounded,
              maxLines: 2),
          const SizedBox(height: 24),
          _buildCheckboxTile(
            title: 'Medical attention required?',
            value: _medicalAttentionRequired,
            onChanged: (v) => setState(() => _medicalAttentionRequired = v ?? false),
          ),
          if (_medicalAttentionRequired) ...[
            const SizedBox(height: 12),
            _buildCheckboxTile(
              title: 'RTW package taken to HCP?',
              value: _returnToWorkPackageTaken,
              onChanged: (v) => setState(() => _returnToWorkPackageTaken = v ?? false),
            ),
          ],
          const SizedBox(height: 32),
          _buildSectionHeader('PART 3: INJURY DETAILS'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildDateTimePicker(
                      context, 'Date of Injury', true, false)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildDateTimePicker(context, 'Time of Injury', false, false)),
            ],
          ),
          const SizedBox(height: 16),
          _buildTimePicker(context, 'Time Left Work', true),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _programController,
              label: 'Associated Program',
              required: false,
              icon: Icons.assignment_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _locationController,
              label: 'Location where injury occurred',
              icon: Icons.place_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _clientInvolvedController,
              label: 'Client Involved (Name & Phone)',
              required: false,
              icon: Icons.person_outline_rounded),
          const SizedBox(height: 32),
          _buildSectionHeader('PART 4: AREA OF INJURY (BODY PART)'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(16)),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _bodyParts.keys.map((key) {
                final isSelected = _bodyParts[key] ?? false;
                return FilterChip(
                  label: Text(key, style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  )),
                  selected: isSelected,
                  onSelected: (v) => setState(() => _bodyParts[key] = v),
                  selectedColor: const Color(0xFF1A73E8),
                  checkmarkColor: Colors.white,
                  backgroundColor: const Color(0xFFF8F9FB),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_bodyParts['Other'] == true)
            _buildTextField(
                controller: _otherBodyPartController,
                label: 'Specify Other Body Part'),
          const SizedBox(height: 32),
          _buildSectionHeader('PART 5: INJURY DESCRIPTION'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _descriptionController,
              label: 'Describe what happened & current conditions',
              maxLines: 4),
          const SizedBox(height: 32),
          _buildSectionHeader('PART 6: WITNESS REMARKS'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _witnessNameController,
              label: 'Witness Name',
              required: false,
              icon: Icons.person_pin_rounded),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _witnessPhoneController,
              label: 'Witness Phone',
              required: false,
              icon: Icons.contact_phone_rounded),
          const SizedBox(height: 32),
          if (_medicalAttentionRequired) ...[
            _buildSectionHeader('PART 7: DETAILS OF ATTENDING HCP'),
            const SizedBox(height: 16),
            _buildTextField(
                controller: _hcpNameController, label: 'Name and Title of HCP', icon: Icons.medical_services_outlined),
            const SizedBox(height: 16),
            _buildTextField(
                controller: _hcpAddressController, label: 'Address of HCP', icon: Icons.map_outlined),
            const SizedBox(height: 16),
            _buildTextField(
                controller: _hcpPhoneController, label: 'Phone Number of HCP', icon: Icons.local_phone_outlined),
            const SizedBox(height: 24),
            _buildCheckboxTile(
              title: 'Did you bring an FAF form?',
              value: _broughtFafForm,
              onChanged: (v) => setState(() => _broughtFafForm = v ?? false),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.attachment_rounded, size: 16, color: Color(0xFF1A73E8)),
                SizedBox(width: 8),
                Expanded(child: Text('Please attach RTW information to this document',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1A73E8)))),
              ],
            ),
            const SizedBox(height: 32),
          ],
          const Text('Declaration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          Text('I confirm that the information provided is true, complete and correct.',
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 20),
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
                Text('Signature captured', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
              ],
            ),
          ],
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
          const SizedBox(height: 40),
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

  Widget _buildTextField(
      {required TextEditingController controller,
      required String label,
      bool required = true,
      int maxLines = 1,
      IconData? icon}) {
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

  Widget _buildDateTimePicker(
      BuildContext context, String label, bool isDate, bool isReported) {
    final val = isDate
        ? (isReported ? _dateReported : _injuryDate)
        : (isReported ? null : _injuryTime);

    String text = 'Tap to select';
    if (val != null) {
      if (val is DateTime) text = DateFormat('yyyy-MM-dd').format(val);
      if (val is TimeOfDay) text = val.format(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => isDate
              ? _selectDate(context, isReported)
              : _selectTime(context, false),
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

  Widget _buildTimePicker(BuildContext context, String label, bool isLeftWork) {
    final val = isLeftWork ? _timeLeftWork : _injuryTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectTime(context, isLeftWork),
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
                const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF1A1A2E)),
                const SizedBox(width: 12),
                Expanded(child: Text(val?.format(context) ?? 'Tap to select', style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w500))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required bool value,
    required Function(bool?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: CheckboxListTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        value: value,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: const Color(0xFF1A73E8),
      ),
    );
  }
}
