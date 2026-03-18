// lib/models/status_event.dart

enum StatusType { online, offline }

class StatusEvent {
  final String id;
  final String contactId;
  final StatusType status;
  final DateTime timestamp;
  final int? durationSeconds; // duration of previous online session (when going offline)

  StatusEvent({
    required this.id,
    required this.contactId,
    required this.status,
    required this.timestamp,
    this.durationSeconds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contactId': contactId,
      'status': status == StatusType.online ? 'online' : 'offline',
      'timestamp': timestamp.millisecondsSinceEpoch,
      'durationSeconds': durationSeconds,
    };
  }

  factory StatusEvent.fromMap(Map<String, dynamic> map) {
    return StatusEvent(
      id: map['id'] as String,
      contactId: map['contactId'] as String,
      status: (map['status'] as String) == 'online'
          ? StatusType.online
          : StatusType.offline,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      durationSeconds: map['durationSeconds'] as int?,
    );
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDate = DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (eventDate == today) return 'Today';
    if (eventDate == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds == 0) return '';
    final d = durationSeconds!;
    if (d < 60) return '${d}s';
    final m = d ~/ 60;
    final s = d % 60;
    if (m < 60) return '${m}m ${s}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h ${rm}m';
  }
}

class DailyStats {
  final DateTime date;
  final int onlineSessions;
  final int totalOnlineMinutes;
  final List<HourlyData> hourlyBreakdown;

  DailyStats({
    required this.date,
    required this.onlineSessions,
    required this.totalOnlineMinutes,
    required this.hourlyBreakdown,
  });
}

class HourlyData {
  final int hour;
  final int onlineMinutes;

  HourlyData({required this.hour, required this.onlineMinutes});
}
