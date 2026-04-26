import 'package:flutter/material.dart';
import '../models/shift.dart';
import '../models/employee.dart';

// ─────────────────────────────────────────────
// SHARED SHIFT CARD WIDGET
// ─────────────────────────────────────────────

class IndividualShiftCard extends StatelessWidget {
  final Shift shift;
  final Employee employee;
  final bool isClockedIn;
  final bool isClockingIn;
  final bool isClockingOut;
  final VoidCallback onViewTasks;
  final VoidCallback? onViewDetails;
  final VoidCallback? onClockIn;
  final VoidCallback? onClockOut;

  const IndividualShiftCard({
    super.key,
    required this.shift,
    required this.employee,
    this.isClockedIn = false,
    this.isClockingIn = false,
    this.isClockingOut = false,
    required this.onViewTasks,
    this.onViewDetails,
    this.onClockIn,
    this.onClockOut,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = shift.statusColor;
    final statusText = shift.statusDisplayText;
    final formattedDate = shift.clockFormattedDate;
    final timeRangeWithDuration = shift.clockFormattedTimeRangeWithDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Bar based on status
            Container(height: 6, color: statusColor),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Status Badge & ID
                  Row(
                    children: [
                      _buildStatusBadge(statusText, statusColor),
                      const SizedBox(width: 10),
                      if (shift.isBlockChild)
                        _buildTypeBadge('Visit inside Block', Colors.purple)
                      else if (shift.isStandalone)
                        _buildTypeBadge('Standalone Visit', Colors.indigo),
                      const Spacer(),
                      Text(
                        '#${shift.shiftId}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Client Info Section
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.person_outline_rounded, 
                          color: Colors.blue.shade700, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shift.clientName ?? 'Unknown Client',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E),
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              shift.department ?? 'Care Service',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            if (shift.client?.phoneMain != null && shift.client!.phoneMain!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.phone_rounded, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    shift.client!.phoneMain!,
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // DateTime Row
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem(
                            Icons.calendar_today_rounded,
                            formattedDate,
                            'Date',
                          ),
                        ),
                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade100),
                        Expanded(
                          child: _buildInfoItem(
                            Icons.access_time_rounded,
                            timeRangeWithDuration,
                            'Time Slot',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      if (!isClockedIn && onClockIn != null)
                        Expanded(
                          child: _buildActionButton(
                            onPressed: isClockingIn ? null : onClockIn,
                            label: 'Clock In',
                            icon: Icons.play_arrow_rounded,
                            color: const Color(0xFF1A73E8),
                            isLoading: isClockingIn,
                          ),
                        )
                      else if (isClockedIn && onClockOut != null)
                        Expanded(
                          child: _buildActionButton(
                            onPressed: isClockingOut ? null : onClockOut,
                            label: 'Clock Out',
                            icon: Icons.stop_rounded,
                            color: const Color(0xFFD32F2F),
                            isLoading: isClockingOut,
                          ),
                        ),
                      if ((!isClockedIn && onClockIn != null) || 
                          (isClockedIn && onClockOut != null))
                        const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          onPressed: onViewTasks,
                          label: 'View Tasks',
                          icon: Icons.assignment_rounded,
                          color: const Color(0xFF1A1A2E),
                          isSecondary: true,
                        ),
                      ),
                    ],
                  ),
                  if (onViewDetails != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: onViewDetails,
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: const Text('View Client Details', 
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.blue.shade100),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF1A73E8)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    required Color color,
    bool isSecondary = false,
    bool isLoading = false,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isSecondary ? Colors.white : color,
        borderRadius: BorderRadius.circular(12),
        border: isSecondary ? Border.all(color: Colors.grey.shade200) : null,
        boxShadow: isSecondary ? null : [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: isSecondary ? color : Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: isSecondary ? color : Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: isSecondary ? color : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Same style as IndividualShiftCard but for block-child shifts.
/// Clock In is removed as per requirement.
class PremiumShiftCard extends StatelessWidget {
  final Shift shift;
  final Employee employee;
  final VoidCallback onViewTasks;
  final VoidCallback? onViewDetails;

  const PremiumShiftCard({
    super.key,
    required this.shift,
    required this.employee,
    required this.onViewTasks,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return IndividualShiftCard(
      shift: shift,
      employee: employee,
      onViewTasks: onViewTasks,
      onViewDetails: onViewDetails,
    );
  }
}

class ShiftStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ShiftStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
