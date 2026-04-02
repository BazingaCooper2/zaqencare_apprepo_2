import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import '../main.dart';
import '../services/session.dart';
import '../services/email_service.dart';

class IncidentReportFormWidget extends StatefulWidget {
  const IncidentReportFormWidget({super.key});

  @override
  State<IncidentReportFormWidget> createState() =>
      _IncidentReportFormWidgetState();
}

class _IncidentReportFormWidgetState extends State<IncidentReportFormWidget> {
  final _formKey = GlobalKey<FormState>();

  // PART 1: REPORT COMPLETED BY
  final _jobTitleController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController =
      TextEditingController(); // Optional as strictly likely auth email but good to ask
  final _supervisorReportedToController = TextEditingController();
  final _locationController =
      TextEditingController(); // Reuse for Work Location/Incident Location

  // Dates/Times
  DateTime? _dateReported;
  TimeOfDay? _timeReported;
  DateTime? _incidentDate;
  TimeOfDay? _incidentTime;

  // PART 2: INDIVIDUALS INVOLVED
  final _workersController = TextEditingController();
  final _clientsController =
      TextEditingController(); // Also doubles for "client involved"
  final _othersController = TextEditingController();

  // Witnesses
  final _witnessNameController = TextEditingController();
  final _witnessTitleController = TextEditingController();
  final _witnessContactController = TextEditingController();

  // PART 3: STATEMENT OF INCIDENT (Detailed Questions)
  // Maps to incident_description
  final _incidentDescriptionController =
      TextEditingController(); // "What was the incident?"
  final _whoReportedController =
      TextEditingController(); // "Who reported the incident?"
  final _whatStatedController =
      TextEditingController(); // "What exactly did they state?"
  final _personalObservationController =
      TextEditingController(); // "What did you personally see/hear/note?"

  // Maps to sequence_of_events
  final _sequenceController =
      TextEditingController(); // "Sequence of events leading up to incident"

  // Maps to client_condition
  bool _painExpressed = false; // "Did client express pain/discomfort?"
  final _clientConditionController =
      TextEditingController(); // "Client's condition (alert, injured...)"

  // Maps to immediate_actions
  final _immediateActionsController =
      TextEditingController(); // "Actions taken immediately"
  final _whoInformedController = TextEditingController(); // "Who was informed?"

  // Maps to medical_attention_required (boolean + details separate if needed, usually boolean is enough but "Did anyone get hurt" is detail)
  final _injuryDetailsController =
      TextEditingController(); // "Did anyone get hurt or require medical attention details"

  // Environmental Hazards
  bool _environmentalHazards = false; // "Were there environmental hazards present?"

  // Signature
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  Uint8List? _signatureImage;
  String? _uploadedSignatureUrl;

  bool _medicalAttentionRequired = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _jobTitleController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _supervisorReportedToController.dispose();
    _locationController.dispose();
    _workersController.dispose();
    _clientsController.dispose();
    _othersController.dispose();
    _witnessNameController.dispose();
    _witnessTitleController.dispose();
    _witnessContactController.dispose();
    _incidentDescriptionController.dispose();
    _whoReportedController.dispose();
    _whatStatedController.dispose();
    _personalObservationController.dispose();
    _sequenceController.dispose();
    _clientConditionController.dispose();
    _immediateActionsController.dispose();
    _whoInformedController.dispose();
    _injuryDetailsController.dispose();
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
          _incidentDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isReported) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        if (isReported) {
          _timeReported = picked;
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
          'incident_sig_${DateTime.now().millisecondsSinceEpoch}.png';

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

  Future<void> _submitForm() async {
    print("SUBMITTING REPORT SESSION: ${Supabase.instance.client.auth.currentSession}");
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      if (SessionManager.empId == null) {
        if (mounted) {
          context.showSnackBar('You must be logged in to submit a report.',
              isError: true);
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Upload signature
      if (_signatureImage != null) {
        final uploadedUrl = await _uploadSignatureToSupabase(_signatureImage!);
        if (uploadedUrl != null) {
          _uploadedSignatureUrl = uploadedUrl;
        }
      }

      // Debug session info before insert
      print("CURRENT USER: ${supabase.auth.currentUser}");
      print("CURRENT SESSION: ${supabase.auth.currentSession}");
      print("SESSION USER ID: ${supabase.auth.currentUser?.id}");
      print("EMP ID BEING SENT: ${SessionManager.empId}");

      String _val(TextEditingController c) {
        final text = c.text.trim();
        return text.isEmpty ? 'N/A' : text;
      }

      final fullName = await SessionManager.getFullName();
      final reporterName = fullName.isEmpty ? 'N/A' : fullName;

      final data = {
        'emp_id': SessionManager.empId,
        'job_title': _val(_jobTitleController),
        'work_location': _val(_locationController),
        'supervisor_name': _val(_supervisorReportedToController),
        'incident_date': _incidentDate != null ? DateFormat('yyyy-MM-dd').format(_incidentDate!) : null,
        'incident_time': _incidentTime != null ? '${_incidentTime!.hour.toString().padLeft(2, '0')}:${_incidentTime!.minute.toString().padLeft(2, '0')}:00' : null,
        'incident_location': _val(_locationController),
        'who_reported': _val(_whoReportedController),
        'incident_description': _val(_incidentDescriptionController),
        'sequence_of_events': _val(_sequenceController),
        'client_condition': _val(_clientConditionController),
        'pain_expressed': _painExpressed,
        'medical_attention_required': _medicalAttentionRequired,
        'environmental_hazards': _environmentalHazards,
        'immediate_actions': _val(_immediateActionsController),
        'who_was_informed': _val(_whoInformedController),
        'reporter_name': reporterName,
        'telephone': int.tryParse(_telephoneController.text.trim()),
        'email': _val(_emailController),
        'supervisor_notified': _val(_supervisorReportedToController),
        'date_reported': _dateReported != null ? DateFormat('yyyy-MM-dd').format(_dateReported!) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time_reported': _timeReported != null 
          ? '${_timeReported!.hour.toString().padLeft(2, '0')}:${_timeReported!.minute.toString().padLeft(2, '0')}:00' 
          : DateFormat('HH:mm:ss').format(DateTime.now()),
        'workers': _val(_workersController),
        'clients': _val(_clientsController),
        'others': _val(_othersController),
        'withness_name': _val(_witnessNameController),
        'witness_job_title': _val(_witnessTitleController),
        'witness_contact': _val(_witnessContactController),
        'witness_statement': _val(_whatStatedController),
        'personal_observation': _val(_personalObservationController),
        'injuries': _val(_injuryDetailsController),
        'reporter_signature': _uploadedSignatureUrl != null ? {'url': _uploadedSignatureUrl} : null,
        'status': 'Submitted',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Insert into Supabase with .select()
      final response = await supabase.from('incident_reports').insert(data).select();
      
      print("🚀 Incident Insert Result: $response");
      debugPrint('✅ Incident report successfully inserted into Supabase');

      // Send email notification
      final emailSent = await EmailService.sendIncidentReportEmail(
        incidentDate: _incidentDate != null ? DateFormat('yyyy-MM-dd').format(_incidentDate!) : 'N/A',
        incidentTime: _incidentTime != null ? '${_incidentTime!.hour.toString().padLeft(2, '0')}:${_incidentTime!.minute.toString().padLeft(2, '0')}' : 'N/A',
        location: _val(_locationController),
        description: _incidentDescriptionController.text
            .trim(), // Send cleaner main description to email, extras in separate args
        sequenceOfEvents: _sequenceController.text.trim(),
        immediateActions: _immediateActionsController.text.trim(),
        clientCondition: _clientConditionController.text.trim(),
        medicalAttentionRequired: _medicalAttentionRequired,
        // Detailed fields
        jobTitle: _jobTitleController.text.trim(),
        telephone: _telephoneController.text.trim(),
        email: _emailController.text.trim(),
        supervisorReportedTo: _supervisorReportedToController.text.trim(),
        dateReported: _dateReported != null
            ? DateFormat('yyyy-MM-dd').format(_dateReported!)
            : 'N/A',
        timeReported: _timeReported != null
            ? (mounted ? _timeReported!.format(context) : 'N/A')
            : 'N/A',
        workersInvolved: _workersController.text.trim(),
        clientsInvolved: _clientsController.text.trim(),
        othersInvolved: _othersController.text.trim(),
        witnessName: _witnessNameController.text.trim(),
        witnessTitle: _witnessTitleController.text.trim(),
        witnessContact: _witnessContactController.text.trim(),
        whoReported: _whoReportedController.text.trim(),
        whatStated: _whatStatedController.text.trim(),
        personalObs: _personalObservationController.text.trim(),
        painDiscomfort: _painExpressed ? 'Yes' : 'No',
        injuryDetails: _injuryDetailsController.text.trim(),
        hazards: _environmentalHazards ? 'Yes' : 'No',
        whoInformed: _whoInformedController.text.trim(),
        signatureUrl: _uploadedSignatureUrl,
        signatureImage: _signatureImage,
      );

      if (mounted) {
        if (emailSent) {
          context.showSnackBar('✅ Incident report submitted & email sent');
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
    _locationController.clear();
    _jobTitleController.clear();
    _telephoneController.clear();
    _emailController.clear();
    _supervisorReportedToController.clear();
    _workersController.clear();
    _clientsController.clear();
    _othersController.clear();
    _witnessNameController.clear();
    _witnessTitleController.clear();
    _witnessContactController.clear();
    _incidentDescriptionController.clear();
    _whoReportedController.clear();
    _whatStatedController.clear();
    _personalObservationController.clear();
    _sequenceController.clear();
    _clientConditionController.clear();
    _immediateActionsController.clear();
    _whoInformedController.clear();
    _injuryDetailsController.clear();
    _signatureController.clear();
    setState(() {
      _incidentDate = null;
      _incidentTime = null;
      _dateReported = null;
      _timeReported = null;
      _medicalAttentionRequired = false;
      _painExpressed = false;
      _environmentalHazards = false;
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
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade50,
            child: const Text(
              'Please notify the Supervisor/Coordinator of the incident prior to the end of the shift',
              style: TextStyle(
                  color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader('PART 1: REPORT COMPLETED BY'),
          const SizedBox(height: 16),
          // Name is auto-filled usually, but skipped as per previous request to just ensure blanks are there.
          _buildTextField(controller: _jobTitleController, label: 'Job Title'),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _telephoneController,
              label: 'Telephone #',
              icon: Icons.phone),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.email,
              required: false),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _locationController,
              label: 'Work Location / Incident Location',
              icon: Icons.place),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _supervisorReportedToController,
              label: 'Supervisor/Designate reported incident to'),
          const SizedBox(height: 12),
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

          const SizedBox(height: 24),
          _buildSectionHeader('PART 2: INDIVIDUALS INVOLVED'),
          const SizedBox(height: 16),
          _buildTextField(
              controller: _workersController,
              label: 'Workers',
              required: false),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _clientsController,
              label: 'Clients',
              required: false),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _othersController,
              label: 'Other (please identify)',
              required: false),
          const SizedBox(height: 12),
          const Text('Witness Information:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildTextField(
              controller: _witnessNameController,
              label: 'Witness Name',
              required: false),
          const SizedBox(height: 8),
          _buildTextField(
              controller: _witnessTitleController,
              label: 'Witness Job Title',
              required: false),
          const SizedBox(height: 8),
          _buildTextField(
              controller: _witnessContactController,
              label: 'Witness Contact Number',
              required: false),

          const SizedBox(height: 24),
          _buildSectionHeader('PART 3: STATEMENT OF INCIDENT'),
          const SizedBox(height: 4),
          const Text('Do not write down personal opinions.',
              style:
                  TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          const SizedBox(height: 16),

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
              controller: _incidentDescriptionController,
              label: 'What was the incident?',
              maxLines: 3),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _whoReportedController,
              label: 'Who reported the incident? (Client, staff...)'),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _whatStatedController,
              label: 'What exactly did they state?',
              maxLines: 2),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _personalObservationController,
              label: 'What did you personally see/hear/note?',
              maxLines: 2),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _sequenceController,
              label: 'Sequence of events leading up to incident',
              maxLines: 3),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          CheckboxListTile(
            title: const Text('Did the client express pain/discomfort?'),
            value: _painExpressed,
            onChanged: (val) => setState(() => _painExpressed = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _clientConditionController,
              label: 'What was the client\'s condition? (alert, responsive...)',
              maxLines: 2),
          const SizedBox(height: 12),
          CheckboxListTile(
            title:
                const Text('Did anyone get hurt or require medical attention?'),
            value: _medicalAttentionRequired,
            onChanged: (val) =>
                setState(() => _medicalAttentionRequired = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_medicalAttentionRequired)
            _buildTextField(
                controller: _injuryDetailsController,
                label: 'Please provide details of injury/attention required',
                maxLines: 2),

          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Were there environmental hazards present?'),
            value: _environmentalHazards,
            onChanged: (val) => setState(() => _environmentalHazards = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _immediateActionsController,
              label: 'What actions did you take immediately?',
              maxLines: 3),
          const SizedBox(height: 12),
          _buildTextField(
              controller: _whoInformedController,
              label: 'Who was informed? (supervisor, nurse, family)'),

          const SizedBox(height: 24),
          const Text(
              'I confirm that to the best of my knowledge the information contained in this document is true, complete, and correct.',
              style: TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Signature(
                  controller: _signatureController,
                  height: 120,
                  backgroundColor: Colors.grey.shade100,
                ),
                Container(
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.clear, size: 20),
                        label: const Text('Clear'),
                        onPressed: () => _signatureController.clear(),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Save Signature'),
                        onPressed: () async {
                          final signature =
                              await _signatureController.toPngBytes();
                          if (signature != null) {
                            setState(() => _signatureImage = signature);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Signature captured!'),
                                    duration: Duration(seconds: 1)),
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
          if (_signatureImage != null) ...[
            const SizedBox(height: 8),
            const Text('Signature Saved ✅',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit Report', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Colors.grey.shade700,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildDateTimePicker(
      BuildContext context, String label, bool isDate, bool isReported) {
    final valDate = isReported ? _dateReported : _incidentDate;
    final valTime = isReported ? _timeReported : _incidentTime;

    String text = 'Select';
    if (isDate) {
      if (valDate != null) text = DateFormat('yyyy-MM-dd').format(valDate);
    } else {
      if (valTime != null) text = valTime.format(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => isDate
              ? _selectDate(context, isReported)
              : _selectTime(context, isReported),
          child: InputDecorator(
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: Icon(
                  isDate ? Icons.calendar_today : Icons.access_time,
                  size: 20),
            ),
            child: Text(text),
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
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 22) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: null, // Removed validation requirement
    );
  }
}
