// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/tracker_service.dart';
import 'services/bridge_service.dart';
import 'services/background_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:                    Colors.transparent,
      statusBarIconBrightness:           Brightness.light,
      systemNavigationBarColor:          AppTheme.bgPrimary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Register WorkManager callback dispatcher (must be called before initialize)
  await BackgroundService.initialize();

  // Init bridge (loads saved config from secure storage)
  final bridgeService = BridgeService();
  await bridgeService.initialize();

  // Init tracker, attach bridge if already configured
  final trackerService = TrackerService();
  await trackerService.initialize(
    bridge: bridgeService.isConfigured ? bridgeService : null,
  );

  // Register WorkManager periodic task if bridge is configured.
  // This replaces the old foreground service — no persistent notification.
  if (bridgeService.isConfigured) {
    await BackgroundService.start();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bridgeService),
        ChangeNotifierProvider.value(value: trackerService),
      ],
      child: WaStatApp(
        bridge:  bridgeService,
        tracker: trackerService,
      ),
    ),
  );
}

class WaStatApp extends StatefulWidget {
  final BridgeService  bridge;
  final TrackerService tracker;

  const WaStatApp({
    super.key,
    required this.bridge,
    required this.tracker,
  });

  @override
  State<WaStatApp> createState() => _WaStatAppState();
}

class _WaStatAppState extends State<WaStatApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Lifecycle transitions ──────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {

      // App is fully visible and interactive
      case AppLifecycleState.resumed:
        debugPrint('[App] Lifecycle: resumed');
        widget.bridge.onAppForeground();
        widget.tracker.onAppForeground();   // triggers history sync
        break;

      // App is partially visible (notification shade, split-screen) or
      // transitioning — treat like background to be safe
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Don't disconnect yet — wait for paused
        break;

      // App is fully backgrounded
      case AppLifecycleState.paused:
        debugPrint('[App] Lifecycle: paused → disconnecting WS');
        widget.bridge.onAppBackground();
        widget.tracker.onAppBackground();
        break;

      // App process was detached (killed). Nothing to clean up here.
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                  'WaStat – Status Tracker',
      debugShowCheckedModeBanner: false,
      theme:                  AppTheme.darkTheme,
      home:                   const MainScaffold(),
    );
  }
}
