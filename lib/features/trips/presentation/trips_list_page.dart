import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_storage.dart';
import '../../../ui_kit/models/enums.dart' as kit_enums;
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/list_items.dart' as kit_items;
import '../../../ui_kit/widgets/navigation.dart' as kit_nav;
import '../../offline/hive_boxes.dart';
import '../../offline/presentation/offline_sync_queue_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../chat/presentation/general_chat_page.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';
import 'package:hive/hive.dart';

final tripsListProvider = FutureProvider<List<Trip>>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth.status != AuthStatus.authenticated) {
    return [];
  }
  return ref.read(tokenStorageProvider).readToken().then((token) {
    if (token == null || token.isEmpty) {
      return [];
    }
    return ref.read(tripsRepositoryProvider).fetchAssignedTrips();
  });
});

class TripsListPage extends ConsumerStatefulWidget {
  const TripsListPage({super.key});

  @override
  ConsumerState<TripsListPage> createState() => _TripsListPageState();
}

class _TripsListPageState extends ConsumerState<TripsListPage> {
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  bool _isOffline = false;
  int _bottomNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = !results.any((r) => r != ConnectivityResult.none);
      if (mounted) {
        setState(() => _isOffline = offline);
      }
    });
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final offline = !results.any((r) => r != ConnectivityResult.none);
    if (mounted) {
      setState(() => _isOffline = offline);
    }
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    super.dispose();
  }

  List<Trip> _filterTrips(List<Trip> trips, int tabIndex) {
    bool isActive(Trip t) => {
      'assigned',
      'loaded',
      'en_route',
      'arrived',
      'offloaded',
    }.contains(t.status);

    bool isScheduled(Trip t) => {'draft', 'scheduled'}.contains(t.status);

    bool isDone(Trip t) => {'completed', 'cancelled'}.contains(t.status);

    switch (tabIndex) {
      case 0:
        return trips.where(isActive).toList();
      case 1:
        return trips.where(isScheduled).toList();
      case 2:
        return trips.where(isDone).toList();
      default:
        return trips;
    }
  }

  int _pendingQueueCount() {
    var count = 0;
    if (Hive.isBoxOpen(HiveBoxes.statusQueue)) {
      count += Hive.box<Map>(HiveBoxes.statusQueue).length;
    }
    if (Hive.isBoxOpen(HiveBoxes.evidenceQueue)) {
      count += Hive.box<Map>(HiveBoxes.evidenceQueue).length;
    }
    if (Hive.isBoxOpen(HiveBoxes.preTripQueue)) {
      count += Hive.box<Map>(HiveBoxes.preTripQueue).length;
    }
    if (Hive.isBoxOpen(HiveBoxes.trackingPings)) {
      count += Hive.box<Map>(HiveBoxes.trackingPings).length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    if (authState.status == AuthStatus.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authState.status != AuthStatus.authenticated) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    final tripsAsync = ref.watch(tripsListProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: kit_nav.ConsMasAppBar(
          title: 'My Trips',
          subtitle: 'Driver session',
          showBackButton: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.invalidate(tripsListProvider),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
            ),
          ],
        ),
        bottomNavigationBar: kit_nav.ConsMasBottomNavBar(
          currentIndex: _bottomNavIndex,
          pendingSyncCount: _pendingQueueCount(),
          onTap: (index) async {
            if (index == 0) {
              setState(() => _bottomNavIndex = 0);
              return;
            }
            if (index == 1) {
              setState(() => _bottomNavIndex = 1);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeneralChatPage()),
              );
              if (!mounted) return;
              setState(() => _bottomNavIndex = 0);
              return;
            }
            if (index == 2) {
              setState(() => _bottomNavIndex = 2);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OfflineSyncQueuePage(),
                ),
              );
              if (!mounted) return;
              setState(() => _bottomNavIndex = 0);
              return;
            }
            setState(() => _bottomNavIndex = 3);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
            if (!mounted) return;
            setState(() => _bottomNavIndex = 0);
          },
        ),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Column(
              children: [
                if (_isOffline)
                  OfflineBanner(
                    queueCount: _pendingQueueCount(),
                    onRetry: () => ref.invalidate(tripsListProvider),
                  ),
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    tabs: [
                      Tab(text: 'Active'),
                      Tab(text: 'Scheduled'),
                      Tab(text: 'Done'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TripsTabView(
                        tripsAsync: tripsAsync,
                        filter: (list) => _filterTrips(list, 0),
                        onRefresh: () async {
                          ref.invalidate(tripsListProvider);
                          await ref.read(tripsListProvider.future);
                        },
                      ),
                      _TripsTabView(
                        tripsAsync: tripsAsync,
                        filter: (list) => _filterTrips(list, 1),
                        onRefresh: () async {
                          ref.invalidate(tripsListProvider);
                          await ref.read(tripsListProvider.future);
                        },
                      ),
                      _TripsTabView(
                        tripsAsync: tripsAsync,
                        filter: (list) => _filterTrips(list, 2),
                        onRefresh: () async {
                          ref.invalidate(tripsListProvider);
                          await ref.read(tripsListProvider.future);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsTabView extends StatelessWidget {
  const _TripsTabView({
    required this.tripsAsync,
    required this.filter,
    required this.onRefresh,
  });

  final AsyncValue<List<Trip>> tripsAsync;
  final List<Trip> Function(List<Trip>) filter;
  final Future<void> Function() onRefresh;

  kit_enums.TripStatus _mapStatus(String status) {
    switch (status) {
      case 'en_route':
        return kit_enums.TripStatus.enRoute;
      case 'arrived':
        return kit_enums.TripStatus.arrived;
      case 'offloaded':
        return kit_enums.TripStatus.offloaded;
      case 'completed':
        return kit_enums.TripStatus.completed;
      default:
        return kit_enums.TripStatus.assigned;
    }
  }

  String _destinationLabel(Trip trip) {
    String? clean(String? value) {
      final v = value?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    }

    final client = clean(trip.clientName);
    final location =
        clean(trip.destination) ??
        clean(trip.deliveryAddress) ??
        clean(trip.dropoffLocation);
    if (client != null && location != null) {
      final same = client.toLowerCase() == location.toLowerCase();
      return same ? location : '$client - $location';
    }
    return location ?? client ?? 'Destination pending';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: tripsAsync.when(
        data: (allTrips) {
          final trips = filter(allTrips);
          if (trips.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: kit_items.EmptyState(
                    icon: Icons.assignment_late_outlined,
                    title: 'No trips assigned',
                    subtitle:
                        'No trips assigned — pull to refresh or contact dispatch',
                    actionLabel: 'Refresh',
                    action: onRefresh,
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              final eta = trip.estimatedArrivalTime;
              final depart = trip.estimatedDepartureTime;
              String? etaOrDepart;
              if (eta != null) {
                etaOrDepart =
                    'ETA ${TimeOfDay.fromDateTime(eta).format(context)}';
              } else if (depart != null) {
                etaOrDepart =
                    'Depart ${TimeOfDay.fromDateTime(depart).format(context)}';
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: kit_items.TripCard(
                  tripId: 'Trip #${trip.id}',
                  destination: _destinationLabel(trip),
                  origin: trip.pickupLocation,
                  waybill: trip.waybillNumber ?? trip.referenceCode,
                  eta: etaOrDepart,
                  status: _mapStatus(trip.status),
                  onTap: () => context.go('/trips/${trip.id}'),
                ),
              );
            },
          );
        },
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: kit_items.EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load trips',
                subtitle: 'Pull to refresh or contact dispatch',
                actionLabel: 'Try Again',
                action: onRefresh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
