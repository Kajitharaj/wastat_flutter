// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tracker_service.dart';
import '../services/bridge_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<TrackerService, BridgeService>(
      builder: (ctx, tracker, bridge, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppTheme.bgSecondary,
            title: const Text('Settings'),
          ),
          body: ListView(
            children: [
              // ── Bridge status card ─────────────────────
              _buildBridgeCard(ctx, bridge),

              _SectionHeader('Tracking'),
              _SettingsTile(
                icon: Icons.wifi_tethering,
                title: 'Enable Tracking',
                subtitle: tracker.isRunning ? 'Tracking is active' : 'Tracking is paused',
                trailing: Switch(
                  value: tracker.isRunning,
                  onChanged: (v) => v ? tracker.startTracking() : tracker.stopTracking(),
                  activeColor: AppTheme.primaryGreen,
                ),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Online Notifications',
                subtitle: 'Notify when contact comes online',
                trailing: Switch(
                  value: tracker.notificationsEnabled,
                  onChanged: tracker.setNotificationsEnabled,
                  activeColor: AppTheme.primaryGreen,
                ),
              ),

              _SectionHeader('About'),
              _SettingsTile(
                icon: Icons.school_outlined,
                title: 'Educational Project',
                subtitle: 'University assignment — WhatsApp status tracker',
                trailing: const Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 18),
              ),
              _SettingsTile(
                icon: Icons.code_outlined,
                title: 'Tech Stack',
                subtitle: 'Flutter · Node.js · Baileys · SQLite · fl_chart',
              ),
              _SettingsTile(
                icon: Icons.lightbulb_outline,
                title: 'How It Works',
                subtitle: 'See architecture documentation',
                onTap: () => _showHowItWorks(ctx),
              ),

              _SectionHeader('Data'),
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear All Data',
                subtitle: 'Remove all contacts and logs',
                iconColor: Colors.red,
                titleColor: Colors.red,
                onTap: () => _confirmClearAll(ctx, tracker),
              ),

              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'WaStat v1.0.0\nFor Educational Use Only',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 12, height: 1.7),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBridgeCard(BuildContext context, BridgeService bridge) {
    final isWaConnected = bridge.waState == WhatsAppState.connected;
    final isBridgeConnected = bridge.bridgeState == BridgeState.connected;

    Color cardColor;
    IconData cardIcon;
    String statusText;
    Color statusColor;

    if (isWaConnected) {
      cardColor = AppTheme.onlineColor.withOpacity(0.08);
      cardIcon = Icons.wifi_tethering;
      statusText = 'Live — WhatsApp Connected';
      statusColor = AppTheme.onlineColor;
    } else if (isBridgeConnected) {
      cardColor = AppTheme.awayColor.withOpacity(0.08);
      cardIcon = Icons.wifi_tethering_error;
      statusText = 'Bridge OK — WhatsApp not paired';
      statusColor = AppTheme.awayColor;
    } else if (bridge.isConfigured) {
      cardColor = Colors.red.withOpacity(0.08);
      cardIcon = Icons.wifi_off;
      statusText = 'Bridge unreachable';
      statusColor = Colors.red;
    } else {
      cardColor = AppTheme.bgCard;
      cardIcon = Icons.wifi_tethering_off;
      statusText = 'Not configured';
      statusColor = AppTheme.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(cardIcon, color: statusColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bridge Connection',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(statusText,
                    style: TextStyle(color: statusColor, fontSize: 12)),
                if (bridge.connectedPhone != null) ...[
                  const SizedBox(height: 2),
                  Text('+${bridge.connectedPhone}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Navigate to Bridge tab (index 3)
              // Find the MainScaffold and switch tab
              _switchToBridgeTab(context);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: statusColor.withOpacity(0.15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              bridge.isConfigured ? 'Manage' : 'Setup',
              style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _switchToBridgeTab(BuildContext context) {
    // Pop back to root and switch to Bridge tab
    // The simplest way is to use a callback or navigator
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Architecture',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'How all the pieces connect',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),

              // Architecture diagram as text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: const Text(
                  'WhatsApp Servers\n'
                  '       │  presence events\n'
                  '       ▼\n'
                  'Node.js Bridge  (your VPS)\n'
                  '  └─ Baileys WebSocket client\n'
                  '  └─ REST API  :3000\n'
                  '  └─ WS Server :8080\n'
                  '       │  real-time events\n'
                  '       ▼\n'
                  'Flutter App  (this app)\n'
                  '  └─ BridgeService (WebSocket)\n'
                  '  └─ TrackerService\n'
                  '  └─ SQLite database',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 24),
              _HowItWorksSection(step: '1', title: 'Baileys (Node.js)',
                  body: 'Opens a WebSocket to wss://web.whatsapp.com using the '
                      'Noise protocol. After QR scan, it\'s a fully authenticated '
                      'WhatsApp linked device.'),
              _HowItWorksSection(step: '2', title: 'Presence Subscription',
                  body: 'For each tracked contact, the bridge calls '
                      'sock.presenceSubscribe(jid). WhatsApp then sends '
                      '"available"/"unavailable" events whenever that contact '
                      'opens or closes the app.'),
              _HowItWorksSection(step: '3', title: 'Bridge → Flutter',
                  body: 'Presence events are forwarded over a WebSocket to your '
                      'Flutter app in real time. The BridgeService receives them '
                      'and passes them to TrackerService.'),
              _HowItWorksSection(step: '4', title: 'Logging & Analytics',
                  body: 'TrackerService timestamps every event, calculates session '
                      'durations, and stores everything in SQLite. Charts and '
                      'statistics are computed from this local database.'),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.awayColor.withOpacity(0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppTheme.awayColor, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Monitoring someone\'s WhatsApp status without consent '
                        'may violate privacy laws. This is for educational purposes only.',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context, TrackerService tracker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Clear All Data?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This will permanently remove all contacts and their entire history.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final c in [...tracker.contacts]) {
                await tracker.deleteContact(c.id);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All data cleared'),
                    backgroundColor: AppTheme.bgElevated,
                  ),
                );
              }
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(title.toUpperCase(),
        style: const TextStyle(
            color: AppTheme.primaryGreen,
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: (iconColor ?? AppTheme.primaryGreen).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? AppTheme.primaryGreen, size: 20),
      ),
      title: Text(title,
          style: TextStyle(
              color: titleColor ?? AppTheme.textPrimary,
              fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: AppTheme.textTertiary)
              : null),
      onTap: onTap,
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  final String step, title, body;
  const _HowItWorksSection(
      {required this.step, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerService>(
      builder: (ctx, tracker, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppTheme.bgSecondary,
            title: const Text('Settings'),
          ),
          body: ListView(
            children: [
              _SectionHeader('Tracking'),
              _SettingsTile(
                icon: Icons.wifi_tethering,
                title: 'Enable Tracking',
                subtitle: tracker.isRunning
                    ? 'Tracking is active'
                    : 'Tracking is paused',
                trailing: Switch(
                  value: tracker.isRunning,
                  onChanged: (v) {
                    if (v) {
                      tracker.startTracking();
                    } else {
                      tracker.stopTracking();
                    }
                  },
                  activeColor: AppTheme.primaryGreen,
                ),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Online Notifications',
                subtitle: 'Notify when contact comes online',
                trailing: Switch(
                  value: tracker.notificationsEnabled,
                  onChanged: tracker.setNotificationsEnabled,
                  activeColor: AppTheme.primaryGreen,
                ),
              ),

              _SectionHeader('About'),
              _SettingsTile(
                icon: Icons.school_outlined,
                title: 'Educational Project',
                subtitle: 'University assignment — WhatsApp status tracker',
                trailing: const Icon(Icons.info_outline,
                    color: AppTheme.textSecondary, size: 18),
              ),
              _SettingsTile(
                icon: Icons.code_outlined,
                title: 'Tech Stack',
                subtitle: 'Flutter · SQLite · fl_chart · Provider',
                trailing: null,
              ),
              _SettingsTile(
                icon: Icons.lightbulb_outline,
                title: 'How It Works',
                subtitle: 'See in-app documentation',
                onTap: () => _showHowItWorks(ctx),
              ),

              _SectionHeader('Data'),
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear All Data',
                subtitle: 'Remove all contacts and logs',
                iconColor: Colors.red,
                titleColor: Colors.red,
                onTap: () => _confirmClearAll(ctx, tracker),
              ),

              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'WaStat v1.0.0\nFor Educational Use Only',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('How WaStat Works',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 20),
              _HowItWorksSection(
                step: '1',
                title: 'WhatsApp Web Protocol',
                body:
                    'Real WaStat apps connect to WhatsApp Web via WebSocket '
                    '(wss://web.whatsapp.com). The connection uses the Noise '
                    'protocol for end-to-end encryption, then authenticates '
                    'using a QR code scan from your phone.',
              ),
              _HowItWorksSection(
                step: '2',
                title: 'Presence Subscriptions',
                body:
                    'After connecting, the app subscribes to "presence" events '
                    'for each tracked contact. WhatsApp broadcasts a presence '
                    'update (available/unavailable) whenever a contact '
                    'opens or closes the app.',
              ),
              _HowItWorksSection(
                step: '3',
                title: 'Real-time Logging',
                body:
                    'Each presence event is timestamped and stored locally. '
                    'The app records the exact time a contact came online, '
                    'and calculates session duration when they go offline.',
              ),
              _HowItWorksSection(
                step: '4',
                title: 'This App (Simulation)',
                body:
                    'For this educational project, real WebSocket connections '
                    'are replaced with a simulation engine that generates '
                    'realistic presence patterns. The architecture is identical '
                    'to a production app — replace _simulatePresence() in '
                    'tracker_service.dart with real callbacks to connect live data.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.awayColor.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppTheme.awayColor, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Note: Monitoring someone\'s WhatsApp status without '
                        'consent may be restricted by privacy laws in your region. '
                        'This project is for educational purposes only.',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context, TrackerService tracker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Clear All Data?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This will permanently remove all contacts and their entire activity history. This cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final contact in [...tracker.contacts]) {
                await tracker.deleteContact(contact.id);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All data cleared'),
                    backgroundColor: AppTheme.bgElevated,
                  ),
                );
              }
            },
            child: const Text('Clear All',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primaryGreen,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (iconColor ?? AppTheme.primaryGreen).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            color: iconColor ?? AppTheme.primaryGreen, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right,
                  color: AppTheme.textTertiary)
              : null),
      onTap: onTap,
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  final String step;
  final String title;
  final String body;

  const _HowItWorksSection({
    required this.step,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
