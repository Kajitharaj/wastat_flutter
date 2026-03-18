// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/tracker_service.dart';
import 'services/bridge_service.dart';
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
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgPrimary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // 1. Init bridge (loads saved config, reconnects if already configured)
  final bridgeService = BridgeService();
  await bridgeService.initialize();

  // 2. Init tracker, attach bridge if it's already configured
  final trackerService = TrackerService();
  await trackerService.initialize(
    bridge: bridgeService.isConfigured ? bridgeService : null,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bridgeService),
        ChangeNotifierProvider.value(value: trackerService),
      ],
      child: const WaStatApp(),
    ),
  );
}

class WaStatApp extends StatelessWidget {
  const WaStatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaStat – Status Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScaffold(),
    );
  }
}
