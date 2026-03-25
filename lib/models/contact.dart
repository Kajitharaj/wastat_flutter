// lib/models/contact.dart
import 'dart:convert';

class TrackedContact {
  final String id;
  final String name;
  final String phoneNumber;
  final String? avatarPath;
  final String? note;
  bool isTracking;
  bool isCurrentlyOnline;
  DateTime? lastSeen;
  DateTime addedAt;
  int totalSessions;
  int totalOnlineMinutes;

  TrackedContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.avatarPath,
    this.note,
    this.isTracking = true,
    this.isCurrentlyOnline = false,
    this.lastSeen,
    required this.addedAt,
    this.totalSessions = 0,
    this.totalOnlineMinutes = 0,
  });

  TrackedContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? avatarPath,
    String? note,
    bool? isTracking,
    bool? isCurrentlyOnline,
    DateTime? lastSeen,
    DateTime? addedAt,
    int? totalSessions,
    int? totalOnlineMinutes,
  }) {
    return TrackedContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarPath: avatarPath ?? this.avatarPath,
      note: note ?? this.note,
      isTracking: isTracking ?? this.isTracking,
      isCurrentlyOnline: isCurrentlyOnline ?? this.isCurrentlyOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      addedAt: addedAt ?? this.addedAt,
      totalSessions: totalSessions ?? this.totalSessions,
      totalOnlineMinutes: totalOnlineMinutes ?? this.totalOnlineMinutes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'avatarPath': avatarPath,
      'note': note,
      'isTracking': isTracking ? 1 : 0,
      'isCurrentlyOnline': isCurrentlyOnline ? 1 : 0,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'addedAt': addedAt.millisecondsSinceEpoch,
      'totalSessions': totalSessions,
      'totalOnlineMinutes': totalOnlineMinutes,
    };
  }

  factory TrackedContact.fromMap(Map<String, dynamic> map) {
    return TrackedContact(
      id: map['id'] as String,
      name: map['name'] as String,
      phoneNumber: map['phoneNumber'] as String,
      avatarPath: map['avatarPath'] as String?,
      note: map['note'] as String?,
      isTracking: (map['isTracking'] as int) == 1,
      isCurrentlyOnline: (map['isCurrentlyOnline'] as int) == 1,
      lastSeen: map['lastSeen'] != null ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen'] as int) : null,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      totalSessions: map['totalSessions'] as int? ?? 0,
      totalOnlineMinutes: map['totalOnlineMinutes'] as int? ?? 0,
    );
  }

  static TrackedContact empty() {
    return TrackedContact(
      id: '',
      name: '',
      phoneNumber: '',
      avatarPath: null,
      note: null,
      isTracking: false,
      isCurrentlyOnline: false,
      lastSeen: null,
      addedAt: DateTime.now(),
      totalSessions: 0,
      totalOnlineMinutes: 0,
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  String get formattedLastSeen {
    if (lastSeen == null) return 'Never seen';
    final now = DateTime.now();
    final diff = now.difference(lastSeen!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${lastSeen!.day}/${lastSeen!.month}/${lastSeen!.year}';
  }

  String get formattedTotalTime {
    if (totalOnlineMinutes < 60) return '${totalOnlineMinutes}m';
    final hours = totalOnlineMinutes ~/ 60;
    final mins = totalOnlineMinutes % 60;
    if (hours < 24) return '${hours}h ${mins}m';
    final days = hours ~/ 24;
    final remHours = hours % 24;
    return '${days}d ${remHours}h';
  }
}
