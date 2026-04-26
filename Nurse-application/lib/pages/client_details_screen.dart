import 'package:flutter/material.dart';
import '../services/care_plan_service.dart';

/// ✅ ClientDetailsScreen
/// Displays a premium summary of client/shift details as shown in the modern UI design.
class ClientDetailsScreen extends StatefulWidget {
  final int clientId;

  const ClientDetailsScreen({super.key, required this.clientId});

  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen> {
  final _service = CarePlanService();
  Map<String, dynamic>? _client;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Future<void> _loadClient() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getClientDetails(widget.clientId);
      if (mounted) {
        setState(() {
          _client = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0EE), // Premium light mint background
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A1A2E)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              const Text('Something went wrong', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadClient, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_client == null) return const Center(child: Text('Client not found'));

    final c = _client!;
    final fullName = '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim();
    final address = c['address'] ?? 'Not provided';
    final serviceType = c['service_type'] ?? 'Outreach';
    final status = c['status'] ?? 'Active';

    return Column(
      children: [
        const SizedBox(height: 12),
        // Drag handle for modal feel
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Title
        const Text(
          'Shift Details',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        
        // Status Badge
        _buildStatusBadge(status),
        const SizedBox(height: 48),

        // Detail Rows
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildDetailsRow('Client Name', fullName),
                const SizedBox(height: 24),
                _buildDetailsRow('Phone Number', c['phone_main'] ?? 'Not provided'),
                const SizedBox(height: 24),
                _buildDetailsRow('Location', address),
                const SizedBox(height: 24),
                _buildDetailsRow('Service Type', serviceType),
                const SizedBox(height: 24),
                _buildDetailsRow('Skills Required', 'None specified'),
              ],
            ),
          ),
        ),

        // Primary Action: Close
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD6EBE0), // Light green bg
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFAED581).withOpacity(0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF2E7D32), // Dark green text
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDetailsRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: Colors.grey.shade300, thickness: 0.8),
      ],
    );
  }
}
