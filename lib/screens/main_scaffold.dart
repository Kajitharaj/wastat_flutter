// lib/screens/main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/tracker_service.dart';
import '../services/bridge_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'activity_screen.dart';
import 'statistics_screen.dart';
import 'bridge_setup_screen.dart';
import 'settings_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    ActivityScreen(),
    StatisticsScreen(),
    BridgeSetupScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Consumer<TrackerService>(
      builder: (context, tracker, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            border: Border(
              top: BorderSide(color: AppTheme.dividerColor, width: 1),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppTheme.primaryGreen,
            unselectedItemColor: AppTheme.textSecondary,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: [
              BottomNavigationBarItem(
                icon: _NavIcon(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  isActive: _currentIndex == 0,
                  badge: tracker.onlineCount > 0 ? tracker.onlineCount : null,
                ),
                label: 'Contacts',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.timeline_outlined),
                activeIcon: Icon(Icons.timeline),
                label: 'Activity',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: 'Statistics',
              ),
              BottomNavigationBarItem(
                icon: Consumer<BridgeService>(
                  builder: (_, bridge, __) => _NavIcon(
                    icon: Icons.wifi_tethering_outlined,
                    activeIcon: Icons.wifi_tethering,
                    isActive: _currentIndex == 3,
                    dotColor: bridge.isFullyConnected
                        ? AppTheme.onlineColor
                        : bridge.bridgeState == BridgeState.connected
                            ? AppTheme.awayColor
                            : null,
                  ),
                ),
                label: 'Bridge',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final int? badge;
  final Color? dotColor;

  const _NavIcon({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    this.badge,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(isActive ? activeIcon : icon),
        if (badge != null && badge! > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (dotColor != null)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.bgSecondary, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
