import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nurse_tracking_app/services/email_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nurse_tracking_app/services/chatbot_service.dart';
import 'package:nurse_tracking_app/services/session.dart';
import 'package:nurse_tracking_app/models/shift.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/faq_data.dart';
import '../constants/tables.dart';

class ChatbotModal extends StatefulWidget {
  const ChatbotModal({super.key});

  @override
  State<ChatbotModal> createState() => _ChatbotModalState();
}

class _ChatbotModalState extends State<ChatbotModal> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      text: 'Hello! I\'m Zaq. How can I help you today?',
      isBot: true,
      timestamp: DateTime.now(),
    ));
  }

  Future<String> _getStorageKey() async {
    final empId = await SessionManager.getEmpId();
    return 'chatbot_history_${empId ?? "guest"}';
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getStorageKey();
    final stored = prefs.getString(key);
    if (stored != null) {
      final decoded = jsonDecode(stored) as List<dynamic>;
      setState(() {
        _messages.clear();
        _messages.addAll(decoded.map((e) => ChatMessage(
              text: e['text'],
              isBot: e['isBot'],
              timestamp: DateTime.parse(e['timestamp']),
            )));
      });
      // Auto-scroll to the bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } else {
      // Only add welcome message if no saved history exists
      setState(() {
        _addWelcomeMessage();
      });
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getStorageKey();
    final encoded = jsonEncode(_messages
        .map((m) => {
              'text': m.text,
              'isBot': m.isBot,
              'timestamp': m.timestamp.toIso8601String(),
            })
        .toList());
    await prefs.setString(key, encoded);
  }

  /// Clears chat history for the current employee.
  /// Call this from your logout flow (e.g., SessionManager.clearSession()) if needed.
  // ignore: unused_element
  Future<void> _clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _getStorageKey();
    await prefs.remove(key);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty || _isLoading) return;

    // Add user message
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isBot: false,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();
    await _saveChatHistory();

    // Check for intents that require UI interaction
    final intent = ChatbotService.detectIntent(message);

    if (intent.type == IntentType.clientBookingEndedEarly) {
      setState(() {
        _isLoading = false;
      });
      _showClientBookingEndedEarlyDialog();
      return;
    }

    if (intent.type == IntentType.clientNotHome) {
      setState(() {
        _isLoading = false;
      });
      _showClientIssueConfirmationDialog('Client not home');
      return;
    }

    if (intent.type == IntentType.clientCancelled) {
      setState(() {
        _isLoading = false;
      });
      _showClientIssueConfirmationDialog('Client cancelled');
      return;
    }

    if (intent.type == IntentType.callInSick) {
      setState(() {
        _isLoading = false;
      });
      _showLeaveRequestDialog();
      return;
    }

    // Get employee ID
    final empId = await SessionManager.getEmpId();

    // Process message
    final response = await ChatbotService.processMessage(message, empId);

    // Add bot response
    setState(() {
      _messages.add(ChatMessage(
        text: response,
        isBot: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = false;
    });
    _scrollToBottom();
    await _saveChatHistory();
  }

  Future<void> _sendMessageWithSignature(
      String message, String signatureUrl, {
        String? leaveStartDate,
        String? leaveEndDate,
        String? startTime,
        String? endTime,
        String? leaveType,
      }) async {
    if (message.trim().isEmpty || _isLoading) return;

    // Add user message
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isBot: false,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();
    await _saveChatHistory();

    // Get employee ID
    final empId = await SessionManager.getEmpId();

    // Process message with signature URL
    final response = await ChatbotService.processMessageWithSignature(
      message,
      empId,
      signatureUrl,
      leaveStartDate: leaveStartDate,
      leaveEndDate: leaveEndDate,
      startTime: startTime,
      endTime: endTime,
      leaveType: leaveType,
      intentOverride: 'call_in_sick',
    );

    // Add bot response
    setState(() {
      _messages.add(ChatMessage(
        text: response,
        isBot: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = false;
    });
    _scrollToBottom();
    await _saveChatHistory();
  }

  void _onFAQSelected(String question) async {
    debugPrint('FAQ Selected: $question');
    // Find the FAQ to check if it has an action
    final faq = FAQData.faqs.firstWhere(
      (f) => f['question'] == question,
      orElse: () => {'question': question},
    );

    final action = faq['action'];
    debugPrint('FAQ Action: $action');

    if (action == 'leave') {
      _showLeaveRequestDialog();
    } else if (action == 'shift_change') {
      _showShiftChangeDialog();
    } else if (action == 'client_issue') {
      debugPrint('Client Issue Action triggered');
      // Check which client issue it is
      if (question == 'Client booking ended early') {
        debugPrint('Calling _showClientBookingEndedEarlyDialog');
        _showClientBookingEndedEarlyDialog();
      } else if (question == 'Client not home' ||
          question == 'Client cancelled') {
        _showClientIssueConfirmationDialog(question);
      } else {
        _sendMessage(question);
      }
    } else if (action == 'delay') {
      _showDelayDialog();
    } else {
      _sendMessage(question);
    }
  }

  void _showLeaveRequestDialog() {
    final reasonController = TextEditingController();
    final signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    DateTime fromDate = DateTime.now();
    DateTime toDate = DateTime.now();
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    Uint8List? signatureImage;
    bool isSubmitting = false;
    String? selectedLeaveType;

    const leaveTypes = [
      'Sick',
      'Vacation',
      'Leave of Absence',
      'Float',
      'Bereavement',
      'Day in Lieu of Public Holiday',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Call in Sick'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Leave Type Dropdown ──────────────────────────────────
                  const Text('Leave Type:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedLeaveType,
                    decoration: InputDecoration(
                      hintText: 'Select leave type',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    items: leaveTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedLeaveType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // ── Leave Duration ───────────────────────────────────────
                  const Text('Select Leave Duration:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: fromDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 30)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                fromDate = picked;
                                if (toDate.isBefore(fromDate)) {
                                  toDate = fromDate;
                                }
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('From Date',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  "${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: toDate,
                              firstDate: fromDate,
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                toDate = picked;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('To Date',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  "${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: startTime,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                startTime = picked;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Start Time',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: endTime,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                endTime = picked;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('End Time',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Please provide a reason for calling in sick:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'e.g., Personal emergency, Family matter...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text('Please provide your signature:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      minHeight: 150,
                      maxHeight: 200,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: Signature(
                            controller: signatureController,
                            backgroundColor: Colors.grey.shade100,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Clear'),
                              onPressed: () => signatureController.clear(),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.save_alt),
                              label: const Text('Save'),
                              onPressed: () async {
                                final signature =
                                    await signatureController.toPngBytes();
                                if (signature != null) {
                                  setDialogState(() {
                                    signatureImage = signature;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Signature saved!')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '⚠️ Please tap "Save" to confirm your signature before submitting.',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (signatureImage != null) ...[
                    const SizedBox(height: 8),
                    const Text('Signature preview:'),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 80,
                      child: Image.memory(signatureImage!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                signatureController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final reason = reasonController.text.trim();
                      if (selectedLeaveType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please select a leave type')),
                        );
                        return;
                      }
                      if (reason.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please provide a reason')),
                        );
                        return;
                      }
                      if (signatureImage == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please provide your signature')),
                        );
                        return;
                      }

                      // Set loading state
                      setDialogState(() {
                        isSubmitting = true;
                      });

                      // Upload signature to Supabase Storage
                      try {
                        final supabase = Supabase.instance.client;
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = 'sick_leave_signature_$timestamp.png';

                        // Try to upload the signature
                        try {
                          await supabase.storage
                              .from('sick_leave_signatures')
                              .uploadBinary(fileName, signatureImage!);
                        } catch (storageError) {
                          final errorStr = storageError.toString();

                          // Handle different storage errors
                          if (errorStr.contains('Bucket not found') ||
                              errorStr.contains('404')) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Storage Bucket Missing'),
                                  content: const Text(
                                    'The storage bucket "sick_leave_signatures" does not exist.\n\n'
                                    'Please create it in Supabase:\n'
                                    '1. Go to Supabase Dashboard → Storage\n'
                                    '2. Click "New bucket"\n'
                                    '3. Name: sick_leave_signatures\n'
                                    '4. Make it Public\n'
                                    '5. Click "Create bucket"\n\n'
                                    'Then try again.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return;
                          } else if (errorStr.contains('row-level security') ||
                              errorStr.contains('RLS') ||
                              errorStr.contains('403') ||
                              errorStr.contains('Unauthorized')) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Storage Permission Error'),
                                  content: const Text(
                                    'The storage bucket has Row-Level Security (RLS) enabled.\n\n'
                                    'To fix this:\n\n'
                                    'Option 1 (Recommended):\n'
                                    '1. Go to Supabase Dashboard → Storage\n'
                                    '2. Find "sick_leave_signatures" bucket\n'
                                    '3. Click the bucket → Settings\n'
                                    '4. Toggle "Public bucket" to ON\n'
                                    '5. Save\n\n'
                                    'Option 2 (If you need RLS):\n'
                                    'Go to Storage → Policies and create a policy that allows INSERT for authenticated users.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return;
                          }
                          rethrow;
                        }

                        // Get public URL
                        final publicUrl = supabase.storage
                            .from('sick_leave_signatures')
                            .getPublicUrl(fileName);

                        debugPrint('✅ Signature uploaded: $publicUrl');

                        // Close dialog and dispose controller
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        signatureController.dispose();

                        // Send message with reason, signature URL, and dates
                        final fromStr =
                            "${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}";
                        final toStr =
                            "${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}";
                        final startStr =
                            "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00";
                        final endStr =
                            "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00";

                        await _sendMessageWithSignature(
                          'I need to take ${selectedLeaveType ?? "leave"} from $fromStr $startStr to $toStr $endStr. Reason: $reason',
                          publicUrl,
                          leaveStartDate: fromStr,
                          leaveEndDate: toStr,
                          startTime: startStr,
                          endTime: endStr,
                          leaveType: selectedLeaveType,
                        );
                      } catch (e) {
                        debugPrint('Error in call in sick: $e');
                        setDialogState(() {
                          isSubmitting = false;
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showShiftChangeDialog() {
    final reasonController = TextEditingController();
    final startTimeController = TextEditingController();
    final endTimeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel/Change Shift'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Please provide the shift details you want to change:'),
              const SizedBox(height: 16),
              TextField(
                controller: startTimeController,
                decoration: const InputDecoration(
                  labelText: 'Current Start Time',
                  hintText: 'e.g., 9am or 9:00',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endTimeController,
                decoration: const InputDecoration(
                  labelText: 'Current End Time',
                  hintText: 'e.g., 5pm or 17:00',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why do you need to change this shift?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              final start = startTimeController.text.trim();
              final end = endTimeController.text.trim();
              Navigator.of(context).pop();
              _sendMessage(
                  'I cannot do the shift from $start to $end. Reason: $reason');
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _showDelayDialog() {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delay in Arrival'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for the delay:'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g., Traffic, Personal emergency...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              Navigator.of(context).pop();
              _sendMessage('I will be late for my shift. Reason: $reason');
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<List<Shift>> _fetchTodayShifts() async {
    try {
      final empId = await SessionManager.getEmpId();
      if (empId == null) return [];

      final supabase = Supabase.instance.client;
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final response = await supabase
          .from('shift')
          .select('*')
          .eq('emp_id', empId)
          .eq('date', todayStr)
          .inFilter('shift_status', [
        'scheduled',
        'Scheduled',
        'in_progress',
        'In Progress',
        'clocked_in',
        'Clocked in'
      ]).order('shift_start_time', ascending: true);

      final shifts = <Shift>[];
      for (var s in (response as List)) {
        final shiftData = Map<String, dynamic>.from(s);
        final updatedShiftData = await _ensureClientDetails(shiftData);
        shifts.add(Shift.fromJson(updatedShiftData));
      }
      return shifts;
    } catch (e) {
      debugPrint('Error fetching today\'s shifts: $e');
      return [];
    }
  }

  Future<Shift?> _showShiftSelectionDialog(List<Shift> shifts) async {
    Shift? selectedShift = shifts.first;

    return await showDialog<Shift>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Please select the shift timings:'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Shift>(
                    isExpanded: true,
                    value: selectedShift,
                    items: shifts.map((shift) {
                      return DropdownMenuItem<Shift>(
                        value: shift,
                        child: Text(
                           shift.formattedTimeRange,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedShift = value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(selectedShift),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }


  Future<Map<String, dynamic>> _ensureClientDetails(
      Map<String, dynamic> shiftData) async {
    // If client data already embedded from the join, remap fields
    if (shiftData['client'] != null && shiftData['client'] is Map) {
      final c = shiftData['client'] as Map<String, dynamic>;
      // Remap to the keys Shift.fromJson expects
      final rawName = c['name'] as String?;
      final first = c['first_name'] as String? ?? '';
      final last = c['last_name'] as String? ?? '';
      shiftData['client_name'] =
          rawName?.isNotEmpty == true ? rawName : '$first $last'.trim();
      shiftData['client_service_type'] =
          c['service_type'] ?? c['individual_service'] ?? c['groups'];
      // Build address from client_final fields
      final parts = <String>[
        if ((c['address'] as String?)?.isNotEmpty == true)
          c['address'] as String,
        if ((c['city'] as String?)?.isNotEmpty == true) c['city'] as String,
        if ((c['province'] as String?)?.isNotEmpty == true)
          c['province'] as String,
      ];
      shiftData['client_location'] = parts.isNotEmpty ? parts.join(', ') : null;
      return shiftData;
    }

    // No embedded client — fetch manually
    if (shiftData['client_id'] != null && shiftData['client_name'] == null) {
      try {
        final supabase = Supabase.instance.client;
        final clientRes = await supabase
            .from(Tables.client)
            .select(
                'id, name, first_name, last_name, address, city, province, service_type, individual_service')
            .eq('id', shiftData['client_id'])
            .single();

        final rawName = clientRes['name'] as String?;
        final first = clientRes['first_name'] as String? ?? '';
        final last = clientRes['last_name'] as String? ?? '';
        shiftData['client_name'] =
            rawName?.isNotEmpty == true ? rawName : '$first $last'.trim();
        shiftData['client_service_type'] = clientRes['service_type'] ??
            clientRes['individual_service'] ??
            clientRes['groups'];
        shiftData['client'] = clientRes;

        final parts = <String>[
          if ((clientRes['address'] as String?)?.isNotEmpty == true)
            clientRes['address'] as String,
          if ((clientRes['city'] as String?)?.isNotEmpty == true)
            clientRes['city'] as String,
          if ((clientRes['province'] as String?)?.isNotEmpty == true)
            clientRes['province'] as String,
        ];
        shiftData['client_location'] =
            parts.isNotEmpty ? parts.join(', ') : null;
      } catch (e) {
        debugPrint('Error fetching client details: $e');
      }
    }
    return shiftData;
  }


  Future<void> _submitShiftChangeRequest({
    required String requestType,
    required Shift shift,
    required String reason,
    required Uint8List signatureImage,
    required String newShiftStatus,
    required Function(bool) setLoading,
    TimeOfDay? actualEndTime,
  }) async {
    setLoading(true);
    try {
      final supabase = Supabase.instance.client;
      final empId = await SessionManager.getEmpId();

      // 1. Upload Signature
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'shift_change_signature_${shift.shiftId}_$timestamp.png';
      String? signatureUrl;

      try {
        await supabase.storage
            .from(
                'sick_leave_signatures') // Reusing bucket as per existing code
            .uploadBinary(fileName, signatureImage);
        signatureUrl = supabase.storage
            .from('sick_leave_signatures')
            .getPublicUrl(fileName);
      } catch (e) {
        debugPrint('Error uploading signature: $e');
        // Continue without signature URL if upload fails, but we have image for email
      }

      // 2. Insert into shift_change_requests
      await supabase.from('shift_change_requests').insert({
        'emp_id': empId,
        'original_shift_id': shift.shiftId,
        'request_type': requestType,
        'reason': reason,
        'status': 'pending',
        'signature_url': signatureUrl,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 3. Update Shift Status (Clock Out & End Early/Cancel)
      final nowUtc = DateTime.now().toUtc();

      // Build the update map
      final shiftUpdateMap = <String, dynamic>{
        'clock_out': nowUtc.toIso8601String(),
        'shift_status': newShiftStatus,
        'shift_progress_note': '$requestType: $reason',
      };

      // If an actual end time was provided, update shift_end_time
      if (actualEndTime != null) {
        final endTimeStr =
            '${actualEndTime.hour.toString().padLeft(2, '0')}:${actualEndTime.minute.toString().padLeft(2, '0')}:00';
        shiftUpdateMap['shift_end_time'] = endTimeStr;
      }

      await supabase
          .from('shift')
          .update(shiftUpdateMap)
          .eq('shift_id', shift.shiftId);

      // 4. Clock out from time_logs if exists
      // We need to find the active time log for this user
      final activeLog = await supabase
          .from('time_logs')
          .select('id, clock_in_time')
          .eq('emp_id', empId!)
          .filter('clock_out_time', 'is', null)
          .maybeSingle();

      if (activeLog != null) {
        final clockInTime = DateTime.parse(activeLog['clock_in_time']);
        final totalHours = (nowUtc.difference(clockInTime).inMinutes / 60.0)
            .toStringAsFixed(2);

        await supabase.from('time_logs').update({
          'clock_out_time': nowUtc.toIso8601String(),
          'total_hours': double.parse(totalHours),
          'updated_at': nowUtc.toIso8601String(),
        }).eq('id', activeLog['id']);
      }

      // 5. Send Email to the correct supervisor
      // Fetch employee details + supervisor
      final employeeRes = await supabase
          .from(Tables.employee)
          .select('first_name, last_name, supervisor_id')
          .eq('emp_id', empId)
          .single();
      final employeeName =
          '${employeeRes['first_name']} ${employeeRes['last_name'] ?? ''}'
              .trim();

      // Look up supervisor email
      String? supervisorEmail;
      final supervisorId = employeeRes['supervisor_id'];
      if (supervisorId != null) {
        try {
          final supRes = await supabase
              .from('supervisors')
              .select('email')
              .eq('id', supervisorId)
              .single();
          supervisorEmail = supRes['email'] as String?;
          debugPrint('📧 Supervisor email: $supervisorEmail');
        } catch (e) {
          debugPrint('⚠️ Could not fetch supervisor email: $e');
        }
      }

      await EmailService.sendShiftChangeRequestEmail(
        requestType: requestType.replaceAll('_', ' '),
        clientName: shift.clientName ?? 'Unknown Client',
        shiftDate: shift.date ?? 'Unknown Date',
        shiftTime: shift.formattedTimeRange,
        reason: reason,
        employeeName: employeeName,
        toEmail: supervisorEmail,
        signatureUrl: signatureUrl,
        signatureImage: signatureImage,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog

        // Add bot success message directly
        setState(() {
          _messages.add(ChatMessage(
            text: 'Shift has been updated and supervisor has been notified',
            isBot: true,
            timestamp: DateTime.now(),
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        await _saveChatHistory();
      }
    } catch (e) {
      debugPrint('Error submitting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setLoading(false);
      }
    }
  }

  void _showClientBookingEndedEarlyDialog() async {
    setState(() => _isLoading = true);
    final shifts = await _fetchTodayShifts();
    setState(() => _isLoading = false);

    if (shifts.isEmpty) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: 'No shifts scheduled for today',
            isBot: true,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    Shift? selectedShift = await _showShiftSelectionDialog(shifts);

    if (selectedShift != null && mounted) {
      _showEndShiftConfirmationDialog(selectedShift);
    }
  }

  String _formatStatus(String? status) {
    if (status == null) return "N/A";
    if (status == 'in_progress') return "In Progress";
    if (status == 'scheduled') return "Scheduled";
    if (status == 'completed') return "Completed";
    return status
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Color _getStatusColor(String? status) {
    if (status == 'in_progress') return Colors.green;
    if (status == 'scheduled') return Colors.blue;
    if (status == 'completed') return Colors.grey;
    return Colors.blueGrey;
  }

  void _showEndShiftConfirmationDialog(Shift shift) {
    final signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    bool isSubmitting = false;
    TimeOfDay? selectedEndTime;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(child: Text('End Shift Early')),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  signatureController.dispose();
                  Navigator.of(context).pop();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Client: ${shift.clientName}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Program: ${shift.clientServiceType ?? "N/A"}'),
                        const SizedBox(height: 4),
                        Text('Time: ${shift.formattedTimeRange}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Status: ',
                                style: TextStyle(fontWeight: FontWeight.w500)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(shift.shiftStatus),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatStatus(shift.shiftStatus),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Time input for when the shift actually ended
                  const Text(
                    'What time did the shift end?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedEndTime ?? TimeOfDay.now(),
                        helpText: 'SELECT END TIME',
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedEndTime = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedEndTime != null
                              ? Colors.blue.shade300
                              : Colors.grey.shade400,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: selectedEndTime != null
                            ? Colors.blue.shade50
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            color: selectedEndTime != null
                                ? Colors.blue.shade600
                                : Colors.grey.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedEndTime != null
                                  ? selectedEndTime!.format(context)
                                  : 'Tap to select end time',
                              style: TextStyle(
                                fontSize: 15,
                                color: selectedEndTime != null
                                    ? Colors.black87
                                    : Colors.grey.shade500,
                                fontWeight: selectedEndTime != null
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (selectedEndTime != null)
                            Icon(
                              Icons.check_circle,
                              color: Colors.green.shade600,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Client booking ended early. Please sign below to confirm ending your shift now.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text('Signature:'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    height: 150,
                    child: Signature(
                      controller: signatureController,
                      backgroundColor: Colors.grey.shade100,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => signatureController.clear(),
                      child: const Text('Clear Signature'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                signatureController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (selectedEndTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Please select the time the shift ended.')),
                        );
                        return;
                      }

                      if (signatureController.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please sign to confirm.')),
                        );
                        return;
                      }

                      final signature = await signatureController.toPngBytes();
                      if (signature == null) return;

                      _submitShiftChangeRequest(
                        requestType: 'client_booking_ended_early',
                        shift: shift,
                        reason:
                            'Client booking ended early at ${selectedEndTime!.format(context)}',
                        signatureImage: signature,
                        newShiftStatus: 'completed',
                        actualEndTime: selectedEndTime,
                        setLoading: (loading) {
                          setDialogState(() => isSubmitting = loading);
                        },
                      );
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirm End Shift'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientIssueConfirmationDialog(String issueType) async {
    setState(() => _isLoading = true);
    final shifts = await _fetchTodayShifts();
    setState(() => _isLoading = false);

    if (shifts.isEmpty) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: 'No shifts scheduled for today',
            isBot: true,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    Shift? selectedShift = await _showShiftSelectionDialog(shifts);

    if (selectedShift == null || !mounted) return;

    final shiftObj = selectedShift;
    if (!mounted) return;

    final signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    bool isSubmitting = false;

    // Determine dialog title and message based on issue type
    String dialogTitle = issueType;
    String dialogMessage = issueType == 'Client cancelled'
        ? 'Client cancelled at the door. Please sign then continue.'
        : '$issueType. Please sign below to confirm ending your shift now.';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(dialogTitle)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  signatureController.dispose();
                  Navigator.of(context).pop();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Client: ${shiftObj.clientName ?? "N/A"}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Program: ${shiftObj.clientServiceType ?? "N/A"}'),
                        const SizedBox(height: 4),
                        Text('Time: ${shiftObj.formattedTimeRange}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Status: ',
                                style: TextStyle(fontWeight: FontWeight.w500)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(shiftObj.shiftStatus),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatStatus(shiftObj.shiftStatus),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dialogMessage,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text('Signature:'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    height: 150,
                    child: Signature(
                      controller: signatureController,
                      backgroundColor: Colors.grey.shade100,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => signatureController.clear(),
                      child: const Text('Clear Signature'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                signatureController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (signatureController.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please sign to confirm.')),
                        );
                        return;
                      }

                      final signature = await signatureController.toPngBytes();
                      if (signature == null) return;

                      String requestTypeCode = 'other';
                      if (issueType == 'Client not home') {
                        requestTypeCode = 'client_not_home';
                      }
                      if (issueType == 'Client cancelled') {
                        requestTypeCode = 'client_cancelled';
                      }

                      _submitShiftChangeRequest(
                        requestType: requestTypeCode,
                        shift: shiftObj,
                        reason: issueType,
                        signatureImage: signature,
                        newShiftStatus: 'cancelled',
                        setLoading: (loading) {
                          setDialogState(() => isSubmitting = loading);
                        },
                      );
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Confirm ${issueType == 'Client not home' ? 'Not Home' : issueType == 'Client cancelled' ? 'Cancellation' : 'Action'}'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modern Gradient Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF0F2027), const Color(0xFF203A43)]
                        : [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary
                          ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.smart_toy_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zaq',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Always here to help',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // FAQ Chips (Scrollable horizontal list)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.1)),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: FAQData.getFAQQuestions().map((question) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          elevation: 0,
                          label: Text(
                            question,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          onPressed: () => _onFAQSelected(question),
                          backgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.08),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Chat messages
              Flexible(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingIndicator();
                      }

                      final message = _messages[index];
                      return _ChatBubble(message: message);
                    },
                  ),
                ),
              ),

              // Input field area
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type your message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: _sendMessage,
                          enabled: !_isLoading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.send_rounded,
                                color: Colors.white, size: 22),
                        onPressed: _isLoading
                            ? null
                            : () => _sendMessage(_messageController.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isBot;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isBot,
    required this.timestamp,
  });
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBot = message.isBot;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment:
            isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isBot) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(Icons.smart_toy_rounded,
                  size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isBot
                    ? theme.colorScheme.surface
                    : theme.colorScheme.primary,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isBot ? Radius.zero : const Radius.circular(20),
                  bottomRight: isBot ? const Radius.circular(20) : Radius.zero,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isBot
                    ? Border.all(color: Colors.grey.withValues(alpha: 0.2))
                    : null,
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isBot ? theme.colorScheme.onSurface : Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (!isBot) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondary,
              child: const Icon(Icons.person_rounded,
                  size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Icon(Icons.smart_toy_rounded,
                size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SizedBox(
              width: 32,
              height: 12,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(3, (index) {
                    return Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
