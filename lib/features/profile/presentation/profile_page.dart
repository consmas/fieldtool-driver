import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/token_storage.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../offline/hive_boxes.dart';
import '../../offline/presentation/offline_sync_queue_page.dart';
import '../../notifications/presentation/notifications_inbox_page.dart';
import '../../notifications/presentation/notification_preferences_page.dart';
import '../../fuel/presentation/vehicle_fuel_log_page.dart';
import '../../fuel/presentation/fuel_insights_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  static const _prefPushNotifications = 'profile_push_notifications';
  static const _prefBiometricUnlock = 'profile_biometric_unlock';
  static const _prefAutoSyncMobile = 'profile_auto_sync_mobile';

  bool _pushNotifications = true;
  bool _biometricUnlock = false;
  bool _autoSyncMobile = true;
  bool _loading = true;
  bool _offline = false;
  int? _userId;
  DateTime? _tokenExpiry;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadPrefs(), _loadTokenInfo(), _initConnectivity()]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _pushNotifications = prefs.getBool(_prefPushNotifications) ?? true;
    _biometricUnlock = prefs.getBool(_prefBiometricUnlock) ?? false;
    _autoSyncMobile = prefs.getBool(_prefAutoSyncMobile) ?? true;
  }

  Future<void> _loadTokenInfo() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    if (token == null || token.isEmpty) return;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      final sub = claims['sub']?.toString();
      final exp = claims['exp'];
      _userId = int.tryParse(sub ?? '');
      if (exp is int) {
        _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(
          exp * 1000,
          isUtc: true,
        ).toLocal();
      }
    } catch (_) {}
  }

  Future<void> _initConnectivity() async {
    final current = await Connectivity().checkConnectivity();
    _offline = !current.any((r) => r != ConnectivityResult.none);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _offline = !results.any((r) => r != ConnectivityResult.none);
      });
    });
  }

  int get _pendingSyncCount {
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
    if (Hive.isBoxOpen(HiveBoxes.fuelLogsQueue)) {
      count += Hive.box<Map>(HiveBoxes.fuelLogsQueue).length;
    }
    return count;
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _openSyncQueue() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OfflineSyncQueuePage()),
    );
    if (!mounted) return;
    setState(() {});
  }

  String _sessionExpiryText() {
    if (_tokenExpiry == null) return 'Unavailable';
    final t = _tokenExpiry!;
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
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
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _bootstrap,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      SectionCard(
                        title: 'Driver Account',
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primaryBlue,
                                child: Text(
                                  (_userId == null ? 'DR' : 'D$_userId')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Driver #${_userId ?? '—'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _offline ? 'Offline' : 'Online',
                                      style: TextStyle(
                                        color: _offline
                                            ? AppColors.errorRed
                                            : AppColors.successGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          InfoRow(
                            label: 'Session expires',
                            value: _sessionExpiryText(),
                          ),
                          InfoRow(
                            label: 'Pending sync items',
                            value: _pendingSyncCount.toString(),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionCard(
                        title: 'Preferences',
                        children: [
                          SwitchListTile.adaptive(
                            value: _pushNotifications,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Push Notifications'),
                            subtitle: const Text(
                              'Receive dispatch and trip update alerts.',
                            ),
                            onChanged: (value) async {
                              setState(() => _pushNotifications = value);
                              await _saveBool(_prefPushNotifications, value);
                            },
                          ),
                          SwitchListTile.adaptive(
                            value: _biometricUnlock,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Biometric Unlock'),
                            subtitle: const Text(
                              'Use fingerprint/face unlock when available.',
                            ),
                            onChanged: (value) async {
                              setState(() => _biometricUnlock = value);
                              await _saveBool(_prefBiometricUnlock, value);
                            },
                          ),
                          SwitchListTile.adaptive(
                            value: _autoSyncMobile,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Auto Sync on Mobile Data'),
                            subtitle: const Text(
                              'Allow automatic queue uploads without Wi-Fi.',
                            ),
                            onChanged: (value) async {
                              setState(() => _autoSyncMobile = value);
                              await _saveBool(_prefAutoSyncMobile, value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SectionCard(
                        title: 'Actions',
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openSyncQueue,
                              icon: const Icon(Icons.sync),
                              label: const Text('Open Offline Sync Queue'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationsInboxPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.notifications_outlined),
                              label: const Text('Open Notifications Inbox'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationPreferencesPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune_outlined),
                              label: const Text('Notification Preferences'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const VehicleFuelLogPage(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.local_gas_station_outlined,
                              ),
                              label: const Text('Log Vehicle Fuel (Off-Trip)'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const FuelInsightsPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.insights_outlined),
                              label: const Text('Fuel Efficiency Insights'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .logout();
                              },
                              icon: const Icon(Icons.logout),
                              label: const Text('Sign Out'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
