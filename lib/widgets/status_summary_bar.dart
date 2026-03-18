// lib/widgets/status_summary_bar.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusSummaryBar extends StatelessWidget {
  final int totalTracked;
  final int onlineCount;
  final bool isRunning;

  const StatusSummaryBar({
    super.key,
    required this.totalTracked,
    required this.onlineCount,
    required this.isRunning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? AppTheme.primaryGreen.withOpacity(0.3)
              : AppTheme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          _StatChip(
            value: '$onlineCount',
            label: 'Online',
            color: AppTheme.onlineColor,
            icon: Icons.circle,
          ),
          _divider(),
          _StatChip(
            value: '${totalTracked - onlineCount}',
            label: 'Offline',
            color: AppTheme.offlineColor,
            icon: Icons.radio_button_unchecked,
          ),
          _divider(),
          _StatChip(
            value: '$totalTracked',
            label: 'Tracked',
            color: AppTheme.accentTeal,
            icon: Icons.people_outline,
          ),
          const Spacer(),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isRunning
                  ? AppTheme.primaryGreen.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRunning
                    ? AppTheme.primaryGreen.withOpacity(0.4)
                    : AppTheme.textTertiary.withOpacity(0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isRunning)
                  _PulsingDot()
                else
                  const Icon(Icons.pause_circle_outline,
                      size: 10, color: AppTheme.textTertiary),
                const SizedBox(width: 5),
                Text(
                  isRunning ? 'Tracking' : 'Paused',
                  style: TextStyle(
                    color: isRunning
                        ? AppTheme.primaryGreen
                        : AppTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 30,
      color: AppTheme.dividerColor,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppTheme.primaryGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
