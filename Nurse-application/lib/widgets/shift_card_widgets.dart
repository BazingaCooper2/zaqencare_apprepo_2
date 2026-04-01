import 'package:flutter/material.dart';
import '../models/shift.dart';
import '../models/employee.dart';

// ─────────────────────────────────────────────
// SHARED SHIFT CARD WIDGET (used in Dashboard + BlockSlots)
// ─────────────────────────────────────────────

class IndividualShiftCard extends StatelessWidget {
  final Shift shift;
  final Employee employee;
  final bool isClockedIn;
  final bool isClockingIn;
  final bool isClockingOut;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;
  final VoidCallback onViewTasks;
  final VoidCallback? onViewDetails;

  const IndividualShiftCard({
    super.key,
    required this.shift,
    required this.employee,
    required this.isClockedIn,
    required this.isClockingIn,
    required this.isClockingOut,
    required this.onClockIn,
    required this.onClockOut,
    required this.onViewTasks,
    this.onViewDetails,
  });

  Color _statusColor(String? status) {
    switch (status?.toLowerCase().replaceAll(' ', '_')) {
      case 'scheduled':
        return Colors.orange;
      case 'in_progress':
        return const Color(0xFF64FFDA);
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(shift.shiftStatus);
    final isCompleted = shift.shiftStatus?.toLowerCase() == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2D50), Color(0xFF162040)],
        ),
        border: Border.all(
          color: isClockedIn
              ? const Color(0xFF64FFDA).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: client name + status badge
            Row(
              children: [
                const Icon(Icons.person, color: Color(0xFF64FFDA), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shift.clientName ?? 'Client',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ShiftStatusBadge(
                    label: shift.statusDisplayText, color: statusColor),
              ],
            ),
            const SizedBox(height: 10),

            // Date + time row
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: Color(0xFF8892B0), size: 15),
                const SizedBox(width: 6),
                Text(
                  shift.date ?? '',
                  style: const TextStyle(
                      color: Color(0xFF8892B0), fontSize: 13),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.access_time,
                    color: Color(0xFF8892B0), size: 15),
                const SizedBox(width: 6),
                Text(
                  shift.formattedTimeRange,
                  style: const TextStyle(
                      color: Color(0xFF8892B0), fontSize: 13),
                ),
              ],
            ),

            if (shift.isBlockChild) ...[
              const SizedBox(height: 6),
              const ShiftInfoChip(
                  label: 'Block Shift', icon: Icons.grid_view),
            ],

            const SizedBox(height: 16),

            if (!isCompleted) ...[
              Row(
                children: [
                  if (onViewDetails != null)
                    ShiftActionButton(
                      label: 'Details',
                      icon: Icons.info_outline,
                      color: const Color(0xFF8892B0),
                      onTap: onViewDetails!,
                    ),
                  const SizedBox(width: 8),
                  ShiftActionButton(
                    label: 'Tasks',
                    icon: Icons.checklist,
                    color: const Color(0xFFCCD6F6),
                    onTap: onViewTasks,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: isClockedIn
                        ? ShiftClockButton(
                            label: 'Clock Out',
                            icon: Icons.logout,
                            color: const Color(0xFFFF6B6B),
                            loading: isClockingOut,
                            onTap: onClockOut,
                          )
                        : ShiftClockButton(
                            label: 'Clock In',
                            icon: Icons.login,
                            color: const Color(0xFF64FFDA),
                            loading: isClockingIn,
                            onTap: onClockIn,
                          ),
                  ),
                ],
              ),
            ] else ...[
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text('Shift Completed',
                      style: TextStyle(color: Colors.green, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              ShiftActionButton(
                label: 'View Tasks',
                icon: Icons.checklist,
                color: const Color(0xFF8892B0),
                onTap: onViewTasks,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED MINI-WIDGETS
// ─────────────────────────────────────────────

class ShiftStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ShiftStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class ShiftInfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const ShiftInfoChip({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFBB86FC), size: 14),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(color: Color(0xFFBB86FC), fontSize: 12)),
      ],
    );
  }
}

class ShiftActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const ShiftActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class ShiftClockButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const ShiftClockButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
