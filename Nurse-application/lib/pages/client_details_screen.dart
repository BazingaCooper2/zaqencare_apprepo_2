import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/care_plan_service.dart';

/// ✅ ClientDetailsScreen
/// Fetches and displays full client profile from client_final table.
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Client Details',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadClient, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_client == null) {
      return Center(
        child: Text('Client not found',
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
      );
    }

    final c = _client!;
    final fullName = '${c['first_name'] ?? ''} ${c['last_name'] ?? ''}'.trim();
    final preferredName = c['preferred_name'] as String?;
    final displayName = preferredName != null && preferredName.isNotEmpty
        ? preferredName
        : fullName;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar + name header
          _ClientHeader(name: displayName, client: c),
          const SizedBox(height: 16),

          // Contact Info
          _InfoSection(
            title: 'Contact Information',
            icon: Icons.contact_phone_outlined,
            color: colorScheme.primary,
            children: [
              _InfoRow(label: 'Phone', value: c['phone_main']),
              _InfoRow(label: 'Alt Phone', value: c['phone_other']),
              _InfoRow(label: 'Email', value: c['email']),
              _InfoRow(
                  label: 'Preferred Contact', value: c['communication_method']),
            ],
          ),

          // Address
          _InfoSection(
            title: 'Address',
            icon: Icons.location_on_outlined,
            color: Colors.orange,
            children: [
              _InfoRow(label: 'Address', value: c['address']),
              _InfoRow(label: 'Line 2', value: c['address_line2']),
              _InfoRow(label: 'City', value: c['city']),
              _InfoRow(label: 'Province', value: c['province']),
              _InfoRow(label: 'Postal Code', value: c['zip']),
              _InfoRow(label: 'Country', value: c['country']),
            ],
          ),

          // Medical
          _InfoSection(
            title: 'Medical Information',
            icon: Icons.medical_information_outlined,
            color: Colors.red.shade400,
            children: [
              _InfoRow(
                  label: 'Primary Diagnosis', value: c['primary_diagnosis']),
              _InfoRow(label: 'Risks', value: c['risks']),
              _InfoRow(label: 'Service Type', value: c['service_type']),
              _InfoRow(label: 'Doctor', value: c['doctor']),
              _InfoRow(label: 'Nurse', value: c['nurse']),
              if (c['wheelchair_user'] == true)
                const _BoolBadge(
                    label: 'Wheelchair User', icon: Icons.accessible),
              if (c['has_catheter'] == true)
                const _BoolBadge(
                    label: 'Has Catheter',
                    icon: Icons.medical_services_outlined),
              if (c['requires_oxygen'] == true)
                const _BoolBadge(label: 'Requires Oxygen', icon: Icons.air),
            ],
          ),

          // Medical Notes (JSONB)
          if (_hasJsonContent(c['medical_notes']))
            _JsonSection(
              title: 'Medical Notes',
              icon: Icons.notes_outlined,
              color: Colors.purple.shade300,
              data: c['medical_notes'],
            ),

          // Instructions
          if (_hasValue(c['instructions']))
            _InfoSection(
              title: 'Care Instructions',
              icon: Icons.assignment_outlined,
              color: colorScheme.secondary,
              children: [
                _InfoRow(value: c['instructions']),
              ],
            ),

          // Emergency Contacts (JSONB)
          if (_hasJsonContent(c['emergency_contacts']))
            _EmergencyContactsSection(data: c['emergency_contacts']),

          // Coordinator
          _InfoSection(
            title: 'Coordinator',
            icon: Icons.support_agent_outlined,
            color: Colors.teal,
            children: [
              _InfoRow(
                  label: 'Coordinator', value: c['client_coordinator_name']),
              _InfoRow(label: 'Notes', value: c['coordinator_notes']),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  bool _hasJsonContent(dynamic v) {
    if (v == null) return false;
    if (v is Map) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return decoded.isNotEmpty;
        if (decoded is List) return decoded.isNotEmpty;
      } catch (_) {}
    }
    return false;
  }
}

// ─────────────────────────────────────────────
// CLIENT HEADER
// ─────────────────────────────────────────────

class _ClientHeader extends StatelessWidget {
  final String name;
  final Map<String, dynamic> client;

  const _ClientHeader({required this.name, required this.client});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final imageUrl = client['image_url'] as String?;
    final gender = client['gender'] as String?;
    final status = client['status'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 36,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
            backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                ? NetworkImage(imageUrl)
                : null,
            child: imageUrl == null || imageUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (gender != null && gender.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    gender,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                ],
                if (status != null && status.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// INFO SECTION
// ─────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _InfoSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Filter out rows with no value
    final visible =
        children.where((w) => w is! _InfoRow || w.value != null).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: visible),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// INFO ROW
// ─────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String? label;
  final dynamic value;

  const _InfoRow({this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (value == null || value.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            SizedBox(
              width: 120,
              child: Text(
                label!,
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value.toString(),
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// BOOL BADGE
// ─────────────────────────────────────────────

class _BoolBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _BoolBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade400, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                color: Colors.red.shade400,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// JSON SECTION (medical notes, etc.)
// ─────────────────────────────────────────────

class _JsonSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final dynamic data;

  const _JsonSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.data,
  });

  String _stringify(dynamic v) {
    if (v is String) return v;
    if (v is Map || v is List) {
      return const JsonEncoder.withIndent('  ').convert(v);
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              _stringify(data),
              style: TextStyle(
                  color: colorScheme.onSurface, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// EMERGENCY CONTACTS SECTION
// ─────────────────────────────────────────────

class _EmergencyContactsSection extends StatelessWidget {
  final dynamic data;

  const _EmergencyContactsSection({required this.data});

  List<Map<String, dynamic>> _parse() {
    try {
      if (data is List) {
        return (data as List).whereType<Map<String, dynamic>>().toList();
      }
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final contacts = _parse();
    if (contacts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.emergency_outlined, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text(
                  'Emergency Contacts',
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          ...contacts.asMap().entries.map((e) {
            final idx = e.key;
            final contact = e.value;
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact ${idx + 1}${contact['name'] != null ? ': ${contact['name']}' : ''}',
                    style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  if (contact['relationship'] != null)
                    _InfoRow(
                        label: 'Relationship', value: contact['relationship']),
                  if (contact['phone'] != null)
                    _InfoRow(label: 'Phone', value: contact['phone']),
                  if (contact['email'] != null)
                    _InfoRow(label: 'Email', value: contact['email']),
                  const SizedBox(height: 8),
                  if (idx < contacts.length - 1)
                    Divider(height: 1, color: colorScheme.outlineVariant),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
