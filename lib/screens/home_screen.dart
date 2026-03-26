// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tracker_service.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';
import '../widgets/contact_card.dart';
import '../widgets/status_summary_bar.dart';
import 'add_contact_screen.dart';
import 'contact_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TrackedContact> _filterContacts(List<TrackedContact> contacts) {
    if (_searchQuery.isEmpty) return contacts;
    final q = _searchQuery.toLowerCase();
    return contacts.where((c) => c.name.toLowerCase().contains(q) || c.phoneNumber.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerService>(
      builder: (context, tracker, _) {
        final filtered = _filterContacts(tracker.contacts);
        final onlineContacts = filtered.where((c) => c.isCurrentlyOnline).toList();
        final offlineContacts = filtered.where((c) => !c.isCurrentlyOnline).toList();

        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          appBar: _buildAppBar(tracker),
          floatingActionButton: _buildFAB(tracker),
          body: RefreshIndicator(
            onRefresh: () => _refreshContacts(tracker),
            color: AppTheme.primaryGreen,
            backgroundColor: AppTheme.bgSecondary,
            child: tracker.contacts.isEmpty
                ? _buildEmptyState()
                : _buildContactList(tracker, onlineContacts, offlineContacts),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(TrackerService tracker) {
    return AppBar(
      backgroundColor: AppTheme.bgSecondary,
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                border: InputBorder.none,
                filled: false,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            )
          : Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppTheme.primaryGreen, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.wifi_tethering, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('WaStat'),
              ],
            ),
      actions: [
        if (!_isSearching) ...[
          // Tracking toggle
          GestureDetector(
            onTap: () {
              if (tracker.isRunning) {
                tracker.stopTracking();
              } else {
                tracker.startTracking();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tracker.isRunning ? AppTheme.primaryGreen.withOpacity(0.15) : AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tracker.isRunning ? AppTheme.primaryGreen : AppTheme.textTertiary, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tracker.isRunning ? AppTheme.primaryGreen : AppTheme.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tracker.isRunning ? 'Live' : 'Paused',
                    style: TextStyle(
                      color: tracker.isRunning ? AppTheme.primaryGreen : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _isSearching = true)),
        ] else
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchController.clear();
            }),
          ),
      ],
    );
  }

  Widget _buildFAB(TrackerService tracker) {
    return FloatingActionButton.extended(
      onPressed: () => _openAddContact(tracker),
      backgroundColor: AppTheme.primaryGreen,
      icon: const Icon(Icons.person_add, color: Colors.white),
      label: const Text(
        'Add Contact',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildContactList(TrackerService tracker, List<TrackedContact> online, List<TrackedContact> offline) {
    return CustomScrollView(
      slivers: [
        // Summary bar
        SliverToBoxAdapter(
          child: StatusSummaryBar(
            totalTracked: tracker.trackedCount,
            onlineCount: tracker.onlineCount,
            isRunning: tracker.isRunning,
          ),
        ),

        // Online section
        if (online.isNotEmpty) ...[
          _buildSectionHeader('Online Now', online.length, AppTheme.onlineColor),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => ContactCard(
                contact: online[i],
                onTap: () => _openDetail(online[i]),
                onLongPress: () => _showContactOptions(online[i], tracker),
              ).animate(delay: Duration(milliseconds: i * 50)).fadeIn().slideY(begin: 0.2),
              childCount: online.length,
            ),
          ),
        ],

        // Offline section
        if (offline.isNotEmpty) ...[
          _buildSectionHeader(online.isNotEmpty ? 'Offline' : 'All Contacts', offline.length, AppTheme.offlineColor),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => ContactCard(
                contact: offline[i],
                onTap: () => _openDetail(offline[i]),
                onLongPress: () => _showContactOptions(offline[i], tracker),
              ).animate(delay: Duration(milliseconds: (online.length + i) * 50)).fadeIn().slideY(begin: 0.2),
              childCount: offline.length,
            ),
          ),
        ],

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, Color dotColor) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(color: AppTheme.primaryGreen.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.people_outline, size: 50, color: AppTheme.primaryGreen),
            ),
            const SizedBox(height: 24),
            const Text(
              'No contacts tracked yet',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add contacts to start tracking\ntheir WhatsApp online status',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.9, 0.9)),
      ),
    );
  }

  Future<void> _refreshContacts(TrackerService tracker) async {
    await tracker.syncHistoryFromBridge();
  }

  void _openAddContact(TrackerService tracker) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
  }

  void _openDetail(TrackedContact contact) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ContactDetailScreen(contactId: contact.id)));
  }

  void _showContactOptions(TrackedContact contact, TrackerService tracker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ContactOptionsSheet(
        contact: contact,
        tracker: tracker,
        onDelete: () {
          Navigator.pop(ctx);
          _confirmDelete(contact, tracker);
        },
        onToggle: () {
          Navigator.pop(ctx);
          tracker.toggleTracking(contact.id);
        },
        onDetail: () {
          Navigator.pop(ctx);
          _openDetail(contact);
        },
      ),
    );
  }

  void _confirmDelete(TrackedContact contact, TrackerService tracker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Remove ${contact.name}?'),
        content: const Text(
          'All tracking data for this contact will be permanently deleted.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              tracker.deleteContact(contact.id);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('${contact.name} removed'), backgroundColor: AppTheme.bgElevated));
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ContactOptionsSheet extends StatelessWidget {
  final TrackedContact contact;
  final TrackerService tracker;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onDetail;

  const _ContactOptionsSheet({
    required this.contact,
    required this.tracker,
    required this.onDelete,
    required this.onToggle,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppTheme.textTertiary, borderRadius: BorderRadius.circular(2)),
          ),
          // Contact header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _ContactAvatar(contact: contact, size: 44),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    Text(contact.phoneNumber, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.dividerColor),
          _OptionTile(icon: Icons.analytics_outlined, label: 'View Details & History', onTap: onDetail),
          _OptionTile(
            icon: contact.isTracking ? Icons.pause_circle_outline : Icons.play_circle_outline,
            label: contact.isTracking ? 'Pause Tracking' : 'Resume Tracking',
            onTap: onToggle,
          ),
          _OptionTile(icon: Icons.delete_outline, label: 'Remove Contact', color: Colors.red, onTap: onDelete),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OptionTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(label, style: TextStyle(color: c)),
      onTap: onTap,
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  final TrackedContact contact;
  final double size;

  const _ContactAvatar({required this.contact, required this.size});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppTheme.primaryGreen.withOpacity(0.2),
      child: Text(
        contact.initials,
        style: TextStyle(color: AppTheme.primaryGreen, fontSize: size * 0.35, fontWeight: FontWeight.w700),
      ),
    );
  }
}
