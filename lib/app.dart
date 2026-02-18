import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/offline/sync_manager.dart';
import 'router/app_router.dart';
import 'ui_kit/theme/app_theme.dart';

class ConsMasApp extends ConsumerWidget {
  const ConsMasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(syncManagerProvider);
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'ConsMas FieldTool Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
