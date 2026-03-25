// lib/screens/contact_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/tracker_service.dart';
import '../models/contact.dart';
import '../models/status_event.dart';
import '../theme/app_theme.dart';

class ContactDetailScreen extends StatefulWidget {
  final String contactId;

  const ContactDetailScreen({super.key, required this.contactId});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<StatusEvent> _events = [];
  Map<int, int> _hourlyDist = {};
  List<Map<String, dynamic>> _dailyData = [];
  bool _loadingLogs = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadData();
    // Refresh every 10s while screen is open
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadData());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tracker = context.read<TrackerService>();
    final events = await tracker.getEventsForContact(widget.contactId, limit: 200);
    final hourly = await tracker.getHourlyDistribution(widget.contactId);
    final daily = await tracker.getDailyOnlineTime(widget.contactId, 14);
    if (mounted) {
      setState(() {
        _events = events;
        _hourlyDist = hourly;
        _dailyData = daily;
        _loadingLogs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerService>(
      builder: (context, tracker, _) {
        final contact = tracker.getContact(widget.contactId);
        if (contact == null) {
          return const Scaffold(body: Center(child: Text('Contact not found')));
        }

        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          body: NestedScrollView(
            headerSliverBuilder: (ctx, scrolled) => [_buildSliverAppBar(contact, tracker)],
            body: TabBarView(
              controller: _tabCtrl,
              children: [_buildLogTab(), _buildStatsTab(contact), _buildChartTab()],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(TrackedContact contact, TrackerService tracker) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppTheme.bgSecondary,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      actions: [
        Switch(
          value: contact.isTracking,
          onChanged: (_) => tracker.toggleTracking(contact.id),
          activeThumbColor: AppTheme.primaryGreen,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: AppTheme.bgSecondary,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              // Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: _avatarColor(contact),
                        child: Text(
                          contact.initials,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: contact.isCurrentlyOnline ? AppTheme.onlineColor : AppTheme.bgElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bgSecondary, width: 2.5),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        contact.name,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(contact.phoneNumber, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 4),
                      _StatusBadge(contact: contact),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabCtrl,
        indicatorColor: AppTheme.primaryGreen,
        labelColor: AppTheme.primaryGreen,
        unselectedLabelColor: AppTheme.textSecondary,
        tabs: const [
          Tab(text: 'Activity Log'),
          Tab(text: 'Statistics'),
          Tab(text: 'Charts'),
        ],
      ),
    );
  }

  // ── Activity Log Tab ─────────────────────────────────────
  Widget _buildLogTab() {
    if (_loadingLogs) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
    }

    if (_events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: AppTheme.textTertiary),
            SizedBox(height: 12),
            Text('No activity recorded yet', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    // Group events by date
    final grouped = <String, List<StatusEvent>>{};
    for (final e in _events) {
      final key = e.formattedDate;
      grouped.putIfAbsent(key, () => []).add(e);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: grouped.length,
      itemBuilder: (ctx, i) {
        final date = grouped.keys.elementAt(i);
        final dayEvents = grouped[date]!;
        return _DayGroup(date: date, events: dayEvents);
      },
    );
  }

  // ── Statistics Tab ────────────────────────────────────────
  Widget _buildStatsTab(TrackedContact contact) {
    final avgSession = contact.totalSessions > 0 ? (contact.totalOnlineMinutes / contact.totalSessions).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _StatsGrid(
            items: [
              _StatItem('Total Sessions', '${contact.totalSessions}', Icons.repeat, AppTheme.primaryGreen),
              _StatItem('Total Online', contact.formattedTotalTime, Icons.timer_outlined, AppTheme.accentTeal),
              _StatItem('Avg Session', '${avgSession}m', Icons.av_timer, AppTheme.awayColor),
              _StatItem(
                'Tracking Since',
                DateFormat('MMM d, y').format(contact.addedAt),
                Icons.calendar_today_outlined,
                AppTheme.offlineColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildHourlyCard(),
        ],
      ),
    );
  }

  Widget _buildHourlyCard() {
    if (_hourlyDist.isEmpty) {
      return const SizedBox.shrink();
    }

    // Find peak hour
    int peakHour = 0;
    int peakCount = 0;
    for (final e in _hourlyDist.entries) {
      if (e.value > peakCount) {
        peakCount = e.value;
        peakHour = e.key;
      }
    }

    final amPm = peakHour < 12 ? 'AM' : 'PM';
    final hour12 = peakHour == 0 ? 12 : (peakHour > 12 ? peakHour - 12 : peakHour);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Most Active Hours',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('Peak: $hour12:00 $amPm', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          _HourlyBarChart(data: _hourlyDist),
        ],
      ),
    );
  }

  // ── Charts Tab ────────────────────────────────────────────
  Widget _buildChartTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [_buildDailyLineChart(), const SizedBox(height: 16), _buildOnlinePieCard()]),
    );
  }

  Widget _buildDailyLineChart() {
    if (_dailyData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
        child: const Center(
          child: Text('Not enough data yet', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < _dailyData.length; i++) {
      final totalSecs = (_dailyData[i]['totalSeconds'] as int?) ?? 0;
      spots.add(FlSpot(i.toDouble(), (totalSecs / 60).roundToDouble()));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Online Time (minutes)',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          const Text('Last 14 days', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: 30,
                  getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.dividerColor, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) =>
                          Text('${v.toInt()}m', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                    ),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppTheme.primaryGreen,
                    barWidth: 2.5,
                    belowBarData: BarAreaData(show: true, color: AppTheme.primaryGreen.withOpacity(0.1)),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 3,
                        color: AppTheme.primaryGreen,
                        strokeWidth: 1.5,
                        strokeColor: AppTheme.bgCard,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlinePieCard() {
    final onlineEvents = _events.where((e) => e.status == StatusType.online).length;
    final offlineEvents = _events.where((e) => e.status == StatusType.offline).length;

    if (onlineEvents == 0 && offlineEvents == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Event Distribution',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 35,
                      sections: [
                        PieChartSectionData(
                          value: onlineEvents.toDouble(),
                          color: AppTheme.onlineColor,
                          radius: 30,
                          title: '$onlineEvents',
                          titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        PieChartSectionData(
                          value: offlineEvents.toDouble(),
                          color: AppTheme.bgElevated,
                          radius: 30,
                          title: '$offlineEvents',
                          titleStyle: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(color: AppTheme.onlineColor, label: 'Online events', count: onlineEvents),
                    const SizedBox(height: 12),
                    _LegendItem(color: AppTheme.bgElevated, label: 'Offline events', count: offlineEvents),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(TrackedContact contact) {
    final colors = [
      const Color(0xFF1B4F72),
      const Color(0xFF0E6655),
      const Color(0xFF7D6608),
      const Color(0xFF4A235A),
      const Color(0xFF1A237E),
    ];
    return colors[contact.name.codeUnitAt(0) % colors.length];
  }
}

// ── Sub-widgets ───────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final TrackedContact contact;
  const _StatusBadge({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: contact.isCurrentlyOnline ? AppTheme.onlineColor.withOpacity(0.15) : AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: contact.isCurrentlyOnline
              ? AppTheme.onlineColor.withOpacity(0.5)
              : AppTheme.textTertiary.withOpacity(0.3),
        ),
      ),
      child: Text(
        contact.isCurrentlyOnline ? 'Online Now' : contact.formattedLastSeen,
        style: TextStyle(
          color: contact.isCurrentlyOnline ? AppTheme.onlineColor : AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  final String date;
  final List<StatusEvent> events;
  const _DayGroup({required this.date, required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            date,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...events.map((e) => _EventTile(event: e)),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final StatusEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isOnline = event.status == StatusType.online;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: isOnline ? AppTheme.onlineColor : AppTheme.offlineColor, width: 3)),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.login : Icons.logout,
            size: 16,
            color: isOnline ? AppTheme.onlineColor : AppTheme.offlineColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isOnline ? 'Came online' : 'Went offline',
              style: TextStyle(
                color: isOnline ? AppTheme.onlineColor : AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (event.exactLastSeen != null)
            Text(
              event.formattedLastSeenTime,
              style: const TextStyle(color: Color.fromARGB(255, 29, 156, 235), fontSize: 12),
            ),
          const SizedBox(width: 8),
          if (event.durationSeconds != null && event.durationSeconds! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(8)),
              child: Text(event.formattedDuration, style: const TextStyle(color: AppTheme.accentTeal, fontSize: 11)),
            ),
          const SizedBox(width: 8),
          Text(event.formattedTime, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _StatsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: items.map((item) => _StatCard(item: item)).toList(),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatItem(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final _StatItem item;
  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const Spacer(),
          Text(
            item.value,
            style: TextStyle(color: item.color, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(item.label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _HourlyBarChart extends StatelessWidget {
  final Map<int, int> data;
  const _HourlyBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b).toDouble();

    final groups = List.generate(24, (h) {
      return BarChartGroupData(
        x: h,
        barRods: [
          BarChartRodData(
            toY: (data[h] ?? 0).toDouble(),
            color: AppTheme.primaryGreen,
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
      );
    });

    return SizedBox(
      height: 120,
      child: BarChart(
        BarChartData(
          maxY: maxVal > 0 ? maxVal * 1.2 : 5,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                getTitlesWidget: (v, _) => Text(
                  v == 0
                      ? '12am'
                      : v == 6
                      ? '6am'
                      : v == 12
                      ? '12pm'
                      : '6pm',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9),
                ),
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: groups,
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _LegendItem({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            Text(
              '$count events',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
