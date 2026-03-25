// lib/screens/activity_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tracker_service.dart';
import '../services/database_service.dart';
import '../models/status_event.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _db = DatabaseService();
  List<_ActivityEntry> _activities = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadActivities();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _loadActivities());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    final tracker  = context.read<TrackerService>();
    final contacts = tracker.contacts;
    final entries  = <_ActivityEntry>[];

    for (final contact in contacts) {
      final events = await _db.getEventsForContact(
        contact.id,
        limit: 20,
        since: DateTime.now().subtract(const Duration(days: 1)),
      );
      for (final e in events) {
        entries.add(_ActivityEntry(contact: contact, event: e));
      }
    }

    entries.sort((a, b) => b.event.timestamp.compareTo(a.event.timestamp));

    if (mounted) {
      setState(() {
        _activities = entries.take(100).toList();
        _loading    = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSecondary,
        title: const Text('Activity Feed'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadActivities),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : _activities.isEmpty
              ? _buildEmpty()
              : _buildFeed(),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline, size: 52, color: AppTheme.textTertiary),
          SizedBox(height: 16),
          Text('No activity in the last 24 hours',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
          SizedBox(height: 8),
          Text('Events will appear here as contacts come\nonline and offline',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _activities.length,
      separatorBuilder: (_, __) => const Divider(
        color: AppTheme.dividerColor, height: 1, indent: 70,
      ),
      itemBuilder: (ctx, i) => _ActivityTile(entry: _activities[i]),
    );
  }
}

class _ActivityEntry {
  final TrackedContact contact;
  final StatusEvent event;
  _ActivityEntry({required this.contact, required this.event});
}

class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;
  const _ActivityTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isOnline = entry.event.status == StatusType.online;
    final contact  = entry.contact;

    // FIX 11: For offline events, show exactLastSeen (WhatsApp's authoritative
    // offline time). For online events there is no lastSeen — fall back to
    // formattedTime (bridge recording timestamp), which is accurate enough.
    final timeLabel = (!isOnline && entry.event.exactLastSeen != null)
        ? entry.event.formattedLastSeenTime
        : entry.event.formattedTime;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _avatarBg(contact),
            child: Text(
              contact.initials,
              style: const TextStyle(
                color:      Colors.white,
                fontWeight: FontWeight.w700,
                fontSize:   13,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width:  16,
              height: 16,
              decoration: BoxDecoration(
                color:  isOnline ? AppTheme.onlineColor : AppTheme.bgElevated,
                shape:  BoxShape.circle,
                border: Border.all(color: AppTheme.bgPrimary, width: 2),
              ),
              child: Icon(
                isOnline ? Icons.arrow_upward : Icons.arrow_downward,
                size:  8,
                color: isOnline ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14),
          children: [
            TextSpan(
              text:  contact.name,
              style: const TextStyle(
                color:      AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text:  isOnline ? ' came online' : ' went offline',
              style: TextStyle(
                color: isOnline ? AppTheme.onlineColor : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Text(
              timeLabel,
              style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
            ),
            if (!isOnline &&
                entry.event.durationSeconds != null &&
                entry.event.durationSeconds! > 0) ...[
              const Text(' · ',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
              Text(
                'Online for ${entry.event.formattedDuration}',
                style: const TextStyle(color: AppTheme.accentTeal, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      trailing: Text(
        entry.event.formattedDate,
        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
      ),
    );
  }

  Color _avatarBg(TrackedContact contact) {
    final colors = [
      const Color(0xFF1B4F72),
      const Color(0xFF0E6655),
      const Color(0xFF7D6608),
      const Color(0xFF4A235A),
      const Color(0xFF1A237E),
      const Color(0xFF6E2F1A),
    ];
    return colors[contact.name.codeUnitAt(0) % colors.length];
  }
}
