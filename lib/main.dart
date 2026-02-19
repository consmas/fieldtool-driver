import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/utils/logger.dart';
import 'features/offline/hive_boxes.dart';
import 'features/tracking/service/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<Map>(HiveBoxes.statusQueue);
  await Hive.openBox<Map>(HiveBoxes.trackingPings);
  await Hive.openBox<Map>(HiveBoxes.evidenceQueue);
  await Hive.openBox<Map>(HiveBoxes.preTripQueue);
  await Hive.openBox<Map>(HiveBoxes.maintenanceSnapshotCache);
  await BackgroundServiceInitializer.initialize();

  FlutterError.onError = (details) {
    Logger.e('Flutter framework error', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) {
    Logger.e('Widget build error', details.exception, details.stack);
    return Material(
      color: const Color(0xFFFFEBEE),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            kDebugMode
                ? 'Widget Error:\n${details.exceptionAsString()}'
                : 'Something went wrong.',
            style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
          ),
        ),
      ),
    );
  };

  runApp(const ProviderScope(child: ConsMasApp()));
}
