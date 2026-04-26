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

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFE8F0EE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Standard Blue Gradient Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zaq AI Assistant',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                        ),
                        Text(
                          'Online • Typically replies instantly',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Modern Horizontal FAQ Chips
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: FAQData.getFAQQuestions().map((question) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ActionChip(
                        label: Text(
                          question,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A73E8)),
                        ),
                        onPressed: () => _onFAQSelected(question),
                        backgroundColor: const Color(0xFFF0F4FF),
                        side: BorderSide(color: const Color(0xFF1A73E8).withOpacity(0.1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Message List
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) return const _TypingIndicator();
                  return _ChatBubble(message: _messages[index]);
                },
              ),
            ),

            // Premium Bottom Input Field
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                ],
              ),
              child: Row(
                children: [
                   Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: _isLoading ? null : _sendMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : () => _sendMessage(_messageController.text),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF1A73E8).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    String? selectedLeaveType = 'Sick';

    const leaveTypes = [
      'Sick',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          title: const Text('Call in Sick',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E))),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Leave Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedLeaveType,
                    style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 15, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Select leave type',
                      filled: true,
                      fillColor: const Color(0xFFF8F9FB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    items: leaveTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                    onChanged: (value) => setDialogState(() => selectedLeaveType = value),
                  ),
                  const SizedBox(height: 20),
                  const Text('Select Duration', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimePickerTile(
                          label: 'From Date',
                          value: "${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}",
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: fromDate, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (picked != null) setDialogState(() { fromDate = picked; if (toDate.isBefore(fromDate)) toDate = fromDate; });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDateTimePickerTile(
                          label: 'To Date',
                          value: "${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}",
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: toDate, firstDate: fromDate, lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (picked != null) setDialogState(() => toDate = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimePickerTile(
                          label: 'Start Time',
                          value: "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}",
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: startTime);
                            if (picked != null) setDialogState(() => startTime = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDateTimePickerTile(
                          label: 'End Time',
                          value: "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}",
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: endTime);
                            if (picked != null) setDialogState(() => endTime = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Reason for Leave', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'e.g., Personal emergency, Sick...',
                      filled: true,
                      fillColor: const Color(0xFFF8F9FB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Your Signature', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8F9FB)),
                    child: Column(
                      children: [
                        SizedBox(height: 120, child: Signature(controller: signatureController, backgroundColor: Colors.transparent)),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF1A73E8)), label: const Text('Clear', style: TextStyle(color: Color(0xFF1A73E8))), onPressed: () => signatureController.clear()),
                              TextButton.icon(icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF1A73E8)), label: const Text('Save', style: TextStyle(color: Color(0xFF1A73E8))), onPressed: () async {
                                final signature = await signatureController.toPngBytes();
                                if (signature != null) {
                                  setDialogState(() => signatureImage = signature);
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signature saved!')));
                                }
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (signatureImage != null) ...[
                    const SizedBox(height: 12),
                    const Text('Preview:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Center(child: Container(height: 60, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade100), borderRadius: BorderRadius.circular(8)), child: Image.memory(signatureImage!))),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    signatureController.dispose();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final reason = reasonController.text.trim();
                            if (selectedLeaveType == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Please select a leave type')));
                              return;
                            }
                            if (reason.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Please provide a reason')));
                              return;
                            }
                            if (signatureImage == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Please provide your signature')));
                              return;
                            }
                            setDialogState(() => isSubmitting = true);
                            try {
                              final supabase = Supabase.instance.client;
                              final timestamp =
                                  DateTime.now().millisecondsSinceEpoch;
                              final fileName =
                                  'sick_leave_signature_$timestamp.png';
                              await supabase.storage
                                  .from('sick_leave_signatures')
                                  .uploadBinary(fileName, signatureImage!);
                              final publicUrl = supabase.storage
                                  .from('sick_leave_signatures')
                                  .getPublicUrl(fileName);
                              if (context.mounted) Navigator.of(context).pop();
                              signatureController.dispose();
                              final fromStr =
                                  "${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}";
                              final toStr =
                                  "${toDate.year}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}";
                              final startStr =
                                  "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00";
                              final endStr =
                                  "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00";
                               String dbLeaveType = 'Sick';
                              if (selectedLeaveType == 'Leave of Absence') {
                                dbLeaveType = 'LOA';
                              } else if (selectedLeaveType == 'Vacation') {
                                dbLeaveType = 'vacation';
                              }
                              await _sendMessageWithSignature(
                                  'I need to take ${selectedLeaveType ?? "leave"} from $fromStr $startStr to $toStr $endStr. Reason: $reason',
                                  publicUrl,
                                  leaveStartDate: fromStr,
                                  leaveEndDate: toStr,
                                  startTime: startStr,
                                  endTime: endStr,
                                  leaveType: dbLeaveType);
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Request',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimePickerTile({required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8F9FB)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        title: const Text('Cancel/Change Shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Provide the shift details you wish to change:', style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
              const SizedBox(height: 20),
              _buildModernTextField(controller: startTimeController, label: 'Current Start Time', hint: 'e.g., 9am or 9:00'),
              const SizedBox(height: 12),
              _buildModernTextField(controller: endTimeController, label: 'Current End Time', hint: 'e.g., 5pm or 17:00'),
              const SizedBox(height: 12),
              _buildModernTextField(controller: reasonController, label: 'Reason', hint: 'Why change this shift?', maxLines: 3),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    final start = startTimeController.text.trim();
                    final end = endTimeController.text.trim();
                    Navigator.of(context).pop();
                    _sendMessage('I cannot do the shift from $start to $end. Reason: $reason');
                  },
                  child: const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({required TextEditingController controller, required String label, required String hint, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  void _showDelayDialog() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        title: const Text('Delay in Arrival', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Please provide a reason for the delay:', style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
            const SizedBox(height: 20),
            _buildModernTextField(controller: reasonController, label: 'Reason', hint: 'e.g., Traffic, Personal emergency...', maxLines: 3),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    Navigator.of(context).pop();
                    _sendMessage('I will be late for my shift. Reason: $reason');
                  },
                  child: const Text('Submit Delay', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          title: const Text('Select Shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Please select the shift timing:', style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Shift>(
                    isExpanded: true,
                    value: selectedShift,
                    style: const TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w600, fontSize: 15),
                    items: shifts.map((shift) => DropdownMenuItem<Shift>(value: shift, child: Text(shift.formattedTimeRange))).toList(),
                    onChanged: (value) => setState(() => selectedShift = value),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                    onPressed: () => Navigator.of(context).pop(selectedShift),
                    child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              const Expanded(child: Text('End Shift Early', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E)))),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.grey), onPressed: () { signatureController.dispose(); Navigator.of(context).pop(); }),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildShiftSummaryCard(shift),
                  const SizedBox(height: 20),
                  const Text('End Time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  _buildDateTimePickerTile(
                    label: 'Actual End Time',
                    value: selectedEndTime != null ? selectedEndTime!.format(context) : 'Tap to select',
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: selectedEndTime ?? TimeOfDay.now());
                      if (picked != null) setDialogState(() => selectedEndTime = picked);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('End confirmation requested. Please sign below.', style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
                  const SizedBox(height: 16),
                  const Text('Signature', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8F9FB)),
                    child: Column(
                      children: [
                        SizedBox(height: 120, child: Signature(controller: signatureController, backgroundColor: Colors.transparent)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: () => signatureController.clear(), child: const Text('Clear Signature', style: TextStyle(color: Colors.grey, fontSize: 12))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(onPressed: () { signatureController.dispose(); Navigator.of(context).pop(); }, child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                    onPressed: isSubmitting ? null : () async {
                      if (selectedEndTime == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select end time'))); return; }
                      if (signatureController.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign to confirm'))); return; }
                      final signature = await signatureController.toPngBytes();
                      if (signature == null) return;
                      _submitShiftChangeRequest(
                        requestType: 'client_booking_ended_early',
                        shift: shift,
                        reason: 'Client booking ended early at ${selectedEndTime!.format(context)}',
                        signatureImage: signature,
                        newShiftStatus: 'completed',
                        actualEndTime: selectedEndTime,
                        setLoading: (loading) => setDialogState(() => isSubmitting = loading),
                      );
                    },
                    child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Confirm End Shift', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftSummaryCard(Shift shift) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, size: 20, color: Color(0xFF1A73E8)),
              const SizedBox(width: 8),
              Expanded(child: Text(shift.clientName ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1A1A2E)))),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryItem(Icons.work_outline_rounded, 'Program', shift.clientServiceType ?? 'N/A'),
          const SizedBox(height: 8),
          _buildSummaryItem(Icons.schedule_rounded, 'Timing', shift.formattedTimeRange),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 8),
              const Text('Status: ', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _getStatusColor(shift.shiftStatus), borderRadius: BorderRadius.circular(6)),
                child: Text(_formatStatus(shift.shiftStatus).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)))),
      ],
    );
  }

  Future<void> _showClientIssueConfirmationDialog(String issueType) async {
    setState(() => _isLoading = true);
    final shifts = await _fetchTodayShifts();
    setState(() => _isLoading = false);

    if (shifts.isEmpty) {
      if (mounted) {
        setState(() => _messages.add(ChatMessage(text: 'No shifts scheduled for today', isBot: true, timestamp: DateTime.now())));
        _scrollToBottom();
        _saveChatHistory();
      }
      return;
    }

    Shift? selectedShift = await _showShiftSelectionDialog(shifts);
    if (selectedShift == null || !mounted) return;

    final shiftObj = selectedShift;
    final signatureController = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
    bool isSubmitting = false;

    String dialogMessage = issueType == 'Client cancelled'
        ? 'Client cancelled at the door. Please sign then continue.'
        : '$issueType. Please sign below to confirm status.';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Expanded(child: Text(issueType, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Color(0xFF1A1A2E)))),
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.grey), onPressed: () { signatureController.dispose(); Navigator.of(context).pop(); }),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildShiftSummaryCard(shiftObj),
                  const SizedBox(height: 20),
                  Text(dialogMessage, style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
                  const SizedBox(height: 16),
                  const Text('Signature', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8F9FB)),
                    child: Column(
                      children: [
                        SizedBox(height: 120, child: Signature(controller: signatureController, backgroundColor: Colors.transparent)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: () => signatureController.clear(), child: const Text('Clear Signature', style: TextStyle(color: Colors.grey, fontSize: 12))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(onPressed: () { signatureController.dispose(); Navigator.of(context).pop(); }, child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                    onPressed: isSubmitting ? null : () async {
                      if (signatureController.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign to confirm'))); return; }
                      final signature = await signatureController.toPngBytes();
                      if (signature == null) return;
                      String requestTypeCode = issueType == 'Client not home' ? 'client_not_home' : issueType == 'Client cancelled' ? 'client_cancelled' : 'other';
                      _submitShiftChangeRequest(
                        requestType: requestTypeCode,
                        shift: shiftObj,
                        reason: issueType,
                        signatureImage: signature,
                        newShiftStatus: 'cancelled',
                        setLoading: (loading) => setDialogState(() => isSubmitting = loading),
                      );
                    },
                    child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Confirm ${issueType.split(' ').last}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
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
    final isBot = message.isBot;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) ...[
            Container(
              margin: const EdgeInsets.only(top: 4),
              child: const CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFF0D47A1),
                child: Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isBot ? Colors.white : null,
                gradient: isBot
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isBot ? Radius.zero : const Radius.circular(20),
                  bottomRight: isBot ? const Radius.circular(20) : Radius.zero,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: isBot ? Border.all(color: Colors.grey.shade100) : null,
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isBot ? const Color(0xFF1A1A2E) : Colors.white,
                  fontSize: 14,
                  fontWeight: isBot ? FontWeight.w500 : FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (!isBot) ...[
            const SizedBox(width: 10),
            Container(
              margin: const EdgeInsets.only(top: 4),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white,
                child: Icon(Icons.person_rounded, size: 16, color: Colors.grey.shade400),
              ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            child: const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF0D47A1),
              child: Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
              ],
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: SizedBox(
              width: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (index) {
                  return Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(color: Color(0xFF1A73E8), shape: BoxShape.circle),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
