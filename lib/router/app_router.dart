import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/trips/presentation/trips_list_page.dart';
import '../features/trips/presentation/trip_detail_page.dart';
import '../features/trips/presentation/pre_trip_form_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final isLoggingIn = state.matchedLocation == '/login';

      if (authState.status == AuthStatus.unknown) {
        return isLoggingIn ? null : '/login';
      }

      if (authState.status == AuthStatus.unauthenticated) {
        return isLoggingIn ? null : '/login';
      }

      if (authState.status == AuthStatus.authenticated && isLoggingIn) {
        return '/trips';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripsListPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final tripId = int.parse(state.pathParameters['id']!);
              return TripDetailPage(tripId: tripId);
            },
            routes: [
              GoRoute(
                path: 'pre-trip',
                builder: (context, state) {
                  final tripId = int.parse(state.pathParameters['id']!);
                  return PreTripFormPage(tripId: tripId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
