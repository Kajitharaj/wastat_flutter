// lib/widgets/contact_card.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';

class ContactCard extends StatefulWidget {
  final TrackedContact contact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ContactCard({super.key, required this.contact, required this.onTap, this.onLongPress});

  @override
  State<ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends State<ContactCard> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        splashColor: AppTheme.primaryGreen.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 12),
              Expanded(child: _buildInfo()),
              _buildRight(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: _avatarBgColor,
          child: Text(
            widget.contact.initials,
            style: TextStyle(color: _avatarTextColor, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        // Online indicator dot
        Positioned(
          right: 0,
          bottom: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: widget.contact.isCurrentlyOnline ? AppTheme.onlineColor : AppTheme.bgElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.bgPrimary, width: 2),
              boxShadow: widget.contact.isCurrentlyOnline
                  ? [BoxShadow(color: AppTheme.onlineColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)]
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.contact.name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            if (!widget.contact.isTracking)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'PAUSED',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(widget.contact.phoneNumber, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              widget.contact.isCurrentlyOnline ? Icons.circle : Icons.access_time_outlined,
              size: 11,
              color: widget.contact.isCurrentlyOnline ? AppTheme.onlineColor : AppTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              widget.contact.isCurrentlyOnline ? 'Online now' : widget.contact.formattedLastSeen,
              style: TextStyle(
                color: widget.contact.isCurrentlyOnline ? AppTheme.onlineColor : AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: widget.contact.isCurrentlyOnline ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRight() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sessions count
        Text(
          '${widget.contact.totalSessions}',
          style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Text('sessions', style: TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
        const SizedBox(height: 4),
        Text(widget.contact.formattedTotalTime, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }

  Color get _avatarBgColor {
    final colors = [
      const Color(0xFF1B4F72),
      const Color(0xFF1A5276),
      const Color(0xFF154360),
      const Color(0xFF0E6655),
      const Color(0xFF1D8348),
      const Color(0xFF7D6608),
      const Color(0xFF6E2F1A),
      const Color(0xFF4A235A),
      const Color(0xFF1A237E).withOpacity(0.8),
    ];
    return colors[widget.contact.name.codeUnitAt(0) % colors.length];
  }

  Color get _avatarTextColor {
    return Colors.white.withOpacity(0.9);
  }
}
