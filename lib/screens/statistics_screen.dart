// lib/screens/statistics_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/tracker_service.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<TrackerService>(
      builder: (ctx, tracker, _) {
        final contacts = tracker.contacts;
        final sorted = [...contacts]
          ..sort((a, b) => b.totalSessions.compareTo(a.totalSessions));

        return Scaffold(
          backgroundColor: AppTheme.bgPrimary,
          appBar: AppBar(
            backgroundColor: AppTheme.bgSecondary,
            title: const Text('Statistics'),
          ),
          body: contacts.isEmpty
              ? _buildEmpty()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOverviewCards(tracker),
                      const SizedBox(height: 20),
                      _buildLeaderboard(sorted),
                      const SizedBox(height: 20),
                      _buildOnlineTimeChart(sorted.take(5).toList()),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 60, color: AppTheme.textTertiary),
          SizedBox(height: 16),
          Text('No data yet',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('Add contacts and start tracking\nto see statistics here',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOverviewCards(TrackerService tracker) {
    final contacts = tracker.contacts;
    final totalSessions =
        contacts.fold(0, (sum, c) => sum + c.totalSessions);
    final totalMinutes =
        contacts.fold(0, (sum, c) => sum + c.totalOnlineMinutes);
    final onlineNow = tracker.onlineCount;

    return Row(
      children: [
        Expanded(
          child: _BigStatCard(
            value: '$onlineNow',
            label: 'Online Now',
            icon: Icons.wifi,
            color: AppTheme.onlineColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigStatCard(
            value: '$totalSessions',
            label: 'Total Sessions',
            icon: Icons.repeat_rounded,
            color: AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigStatCard(
            value: _formatMins(totalMinutes),
            label: 'Total Online',
            icon: Icons.timer_rounded,
            color: AppTheme.accentTeal,
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboard(List<TrackedContact> sorted) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: AppTheme.awayColor, size: 20),
              SizedBox(width: 8),
              Text('Most Active Contacts',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...sorted.take(5).toList().asMap().entries.map(
                (e) => _LeaderboardRow(
                  rank: e.key + 1,
                  contact: e.value,
                ),
              ),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('No data yet',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOnlineTimeChart(List<TrackedContact> top5) {
    if (top5.isEmpty) return const SizedBox.shrink();

    final maxVal = top5
        .map((c) => c.totalOnlineMinutes)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();

    if (maxVal == 0) return const SizedBox.shrink();

    final groups = top5.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value.totalOnlineMinutes.toDouble(),
            color: AppTheme.primaryGreen,
            width: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxVal * 1.2,
              color: AppTheme.bgElevated,
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top 5 by Online Time (minutes)',
              style: TextStyle(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxVal * 1.2,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i >= 0 && i < top5.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              top5[i].name.split(' ').first,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 10),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: groups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMins(int mins) {
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    if (h < 24) return '${h}h';
    return '${h ~/ 24}d';
  }
}

class _BigStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _BigStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final TrackedContact contact;

  const _LeaderboardRow({required this.rank, required this.contact});

  @override
  Widget build(BuildContext context) {
    final rankColors = {
      1: const Color(0xFFFFD700),
      2: const Color(0xFFC0C0C0),
      3: const Color(0xFFCD7F32),
    };
    final rankColor = rankColors[rank] ?? AppTheme.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500)),
                Text('${contact.totalSessions} sessions',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                contact.formattedTotalTime,
                style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w700),
              ),
              if (contact.isCurrentlyOnline)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.onlineColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Online',
                      style: TextStyle(
                          color: AppTheme.onlineColor, fontSize: 10)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
