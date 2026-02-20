import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/list_items.dart';
import '../../driver_hub/data/driver_hub_repository.dart';
import '../../fuel/data/fuel_repository.dart';
import '../../incidents/data/incidents_repository.dart';
import '../../offline/hive_boxes.dart';
import '../../tracking/data/tracking_repository.dart';
import '../../trips/data/trips_repository.dart';

class OfflineSyncQueuePage extends ConsumerStatefulWidget {
  const OfflineSyncQueuePage({super.key});

  @override
  ConsumerState<OfflineSyncQueuePage> createState() =>
      _OfflineSyncQueuePageState();
}

class _OfflineSyncQueuePageState extends ConsumerState<OfflineSyncQueuePage> {
  final List<String> _syncLog = [];
  final Map<String, SyncStatus> _statusByEntry = {};
  final Map<String, int> _attemptsByEntry = {};
  late final Box<Map> _statusBox;
  late final Box<Map> _mediaBox;
  late final Box<Map> _preTripBox;
  late final Box<Map> _pingBox;
  late final Box<Map> _fuelBox;
  late final Box<Map> _driverDocsBox;
  late final Box<Map> _incidentDraftsBox;
  late final Box<Map> _incidentEvidenceBox;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOffline = false;
  bool _retryAllRunning = false;

  @override
  void initState() {
    super.initState();
    _statusBox = Hive.box<Map>(HiveBoxes.statusQueue);
    _mediaBox = Hive.box<Map>(HiveBoxes.evidenceQueue);
    _preTripBox = Hive.box<Map>(HiveBoxes.preTripQueue);
    _pingBox = Hive.box<Map>(HiveBoxes.trackingPings);
    _fuelBox = Hive.box<Map>(HiveBoxes.fuelLogsQueue);
    _driverDocsBox = Hive.box<Map>(HiveBoxes.driverDocumentsUploadQueue);
    _incidentDraftsBox = Hive.box<Map>(HiveBoxes.incidentDraftsQueue);
    _incidentEvidenceBox = Hive.box<Map>(HiveBoxes.incidentEvidenceQueue);
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
    _connectivitySub?.cancel();
    super.dispose();
  }

  List<_QueueEntry> _entriesForBox(Box<Map> box, _QueueKind kind) {
    final entries = <_QueueEntry>[];
    for (final key in box.keys) {
      final payload = box.get(key);
      if (payload == null) continue;
      final id = '$kind:$key';
      entries.add(
        _QueueEntry(
          id: id,
          key: key,
          kind: kind,
          payload: Map<String, dynamic>.from(payload),
        ),
      );
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<void> _retryEntry(_QueueEntry entry) async {
    final tripsRepo = ref.read(tripsRepositoryProvider);
    final trackingRepo = ref.read(trackingRepositoryProvider);
    final fuelRepo = ref.read(fuelRepositoryProvider);
    final incidentsRepo = ref.read(incidentsRepositoryProvider);

    setState(() => _statusByEntry[entry.id] = SyncStatus.syncing);
    _addLog('Syncing ${entry.title} (${entry.kind.label})');

    try {
      switch (entry.kind) {
        case _QueueKind.status:
          await tripsRepo.replayStatus(
            tripId: entry.payload['trip_id'] as int,
            status: entry.payload['status'] as String,
          );
          await _statusBox.delete(entry.key);
          break;
        case _QueueKind.media:
          await tripsRepo.replayQueuedMedia(entry.payload);
          await _mediaBox.delete(entry.key);
          break;
        case _QueueKind.preTrip:
          await tripsRepo.replayQueuedPreTrip(entry.payload);
          await _preTripBox.delete(entry.key);
          break;
        case _QueueKind.ping:
          await trackingRepo.postLocationPing(
            tripId: entry.payload['trip_id'] as int,
            lat: (entry.payload['lat'] as num).toDouble(),
            lng: (entry.payload['lng'] as num).toDouble(),
            speed: (entry.payload['speed'] as num?)?.toDouble() ?? 0,
            heading: (entry.payload['heading'] as num?)?.toDouble() ?? 0,
            recordedAt: DateTime.parse(entry.payload['recorded_at'] as String),
          );
          await _pingBox.delete(entry.key);
          break;
        case _QueueKind.fuel:
          await fuelRepo.replayQueuedFuelLog(entry.payload);
          await _fuelBox.delete(entry.key);
          break;
        case _QueueKind.driverDoc:
          await ref
              .read(driverHubRepositoryProvider)
              .replayQueuedDocumentUpload(entry.payload);
          await _driverDocsBox.delete(entry.key);
          break;
        case _QueueKind.incidentDraft:
          await incidentsRepo.replayQueuedIncidentDraft(entry.payload);
          await _incidentDraftsBox.delete(entry.key);
          break;
        case _QueueKind.incidentEvidence:
          await incidentsRepo.replayQueuedIncidentEvidence(entry.payload);
          await _incidentEvidenceBox.delete(entry.key);
          break;
      }
      setState(() {
        _statusByEntry[entry.id] = SyncStatus.synced;
        _attemptsByEntry.remove(entry.id);
      });
      _addLog('Synced ${entry.title}');
    } catch (e) {
      setState(() {
        _statusByEntry[entry.id] = SyncStatus.failed;
        _attemptsByEntry[entry.id] = (_attemptsByEntry[entry.id] ?? 0) + 1;
      });
      _addLog('Failed ${entry.title}: $e');
    }
  }

  Future<void> _forceRetryAll() async {
    if (_retryAllRunning || _isOffline) return;
    setState(() => _retryAllRunning = true);
    _addLog('Force retry all started');

    try {
      final statusEntries = _entriesForBox(_statusBox, _QueueKind.status);
      for (final entry in statusEntries) {
        await _retryEntry(entry);
      }

      final preTripEntries = _entriesForBox(_preTripBox, _QueueKind.preTrip);
      for (final entry in preTripEntries) {
        await _retryEntry(entry);
      }

      final mediaEntries = _entriesForBox(_mediaBox, _QueueKind.media);
      for (final entry in mediaEntries) {
        await _retryEntry(entry);
      }

      final fuelEntries = _entriesForBox(_fuelBox, _QueueKind.fuel);
      for (final entry in fuelEntries) {
        await _retryEntry(entry);
      }

      final docEntries = _entriesForBox(_driverDocsBox, _QueueKind.driverDoc);
      for (final entry in docEntries) {
        await _retryEntry(entry);
      }

      final incidentDraftEntries = _entriesForBox(
        _incidentDraftsBox,
        _QueueKind.incidentDraft,
      );
      for (final entry in incidentDraftEntries) {
        await _retryEntry(entry);
      }

      final incidentEvidenceEntries = _entriesForBox(
        _incidentEvidenceBox,
        _QueueKind.incidentEvidence,
      );
      for (final entry in incidentEvidenceEntries) {
        await _retryEntry(entry);
      }

      final pingEntries = _entriesForBox(_pingBox, _QueueKind.ping);
      for (final entry in pingEntries) {
        await _retryEntry(entry);
      }
      _addLog('Force retry all completed');
    } finally {
      if (mounted) setState(() => _retryAllRunning = false);
    }
  }

  void _addLog(String message) {
    final stamp = DateTime.now().toLocal().toString();
    _syncLog.insert(0, '[$stamp] $message');
    if (_syncLog.length > 100) {
      _syncLog.removeRange(100, _syncLog.length);
    }
  }

  int get _totalPending =>
      _statusBox.length +
      _mediaBox.length +
      _preTripBox.length +
      _pingBox.length +
      _fuelBox.length +
      _driverDocsBox.length +
      _incidentDraftsBox.length +
      _incidentEvidenceBox.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Sync Queue')),
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
              if (_isOffline) OfflineBanner(queueCount: _totalPending),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final p1 = _entriesForBox(_statusBox, _QueueKind.status);
                    final p2 = [
                      ..._entriesForBox(_preTripBox, _QueueKind.preTrip),
                      ..._entriesForBox(_mediaBox, _QueueKind.media),
                      ..._entriesForBox(_fuelBox, _QueueKind.fuel),
                      ..._entriesForBox(_driverDocsBox, _QueueKind.driverDoc),
                      ..._entriesForBox(
                        _incidentDraftsBox,
                        _QueueKind.incidentDraft,
                      ),
                      ..._entriesForBox(
                        _incidentEvidenceBox,
                        _QueueKind.incidentEvidence,
                      ),
                    ];
                    final p3 = _entriesForBox(_pingBox, _QueueKind.ping);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.neutral200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Overall Status',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  _totalPending == 0
                                      ? 'All items synced.'
                                      : '$_totalPending pending items in offline queue',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AlertBanner(
                            type: AlertType.info,
                            message:
                                'Items sync in order: Status changes → Media/Fuel uploads → Location pings',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SyncQueueSection(
                            title: 'Status Changes',
                            priority: 1,
                            items: p1
                                .map((e) => _buildQueueItem(context, e))
                                .toList(),
                          ),
                          SyncQueueSection(
                            title: 'Media Uploads',
                            priority: 2,
                            items: p2
                                .map((e) => _buildQueueItem(context, e))
                                .toList(),
                          ),
                          SyncQueueSection(
                            title: 'Location Pings',
                            priority: 3,
                            items: p3
                                .map((e) => _buildQueueItem(context, e))
                                .toList(),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.neutral200),
                            ),
                            child: ExpansionTile(
                              title: const Text('View Sync Log'),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                AppSpacing.md,
                                0,
                                AppSpacing.md,
                                AppSpacing.md,
                              ),
                              children: [
                                if (_syncLog.isEmpty)
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('No sync events yet.'),
                                  )
                                else
                                  ..._syncLog
                                      .take(30)
                                      .map(
                                        (line) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              line,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  (_isOffline ||
                                      _retryAllRunning ||
                                      _totalPending == 0)
                                  ? null
                                  : _forceRetryAll,
                              icon: _retryAllRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentOrangeDark,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md,
                                ),
                              ),
                              label: const Text('Force Retry All'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SyncQueueItem _buildQueueItem(BuildContext context, _QueueEntry entry) {
    final status = _statusByEntry[entry.id] ?? SyncStatus.queued;
    final attempts = _attemptsByEntry[entry.id] ?? 0;
    final subtitle = attempts >= 3
        ? 'Failed after 3 attempts. Tap to retry manually.'
        : '${entry.meta} · ${entry.timestampLabel}';

    return SyncQueueItem(
      name: entry.title,
      subtitle: subtitle,
      icon: entry.kind.icon,
      syncStatus: status,
      onRetry: () => _retryEntry(entry),
    );
  }
}

enum _QueueKind {
  status('Status'),
  preTrip('Pre-Trip'),
  media('Media'),
  ping('Ping'),
  fuel('Fuel'),
  driverDoc('Driver Doc'),
  incidentDraft('Incident Draft'),
  incidentEvidence('Incident Evidence');

  const _QueueKind(this.label);
  final String label;

  IconData get icon => switch (this) {
    _QueueKind.status => Icons.compare_arrows,
    _QueueKind.preTrip => Icons.fact_check_outlined,
    _QueueKind.media => Icons.photo_outlined,
    _QueueKind.ping => Icons.my_location_outlined,
    _QueueKind.fuel => Icons.local_gas_station_outlined,
    _QueueKind.driverDoc => Icons.description_outlined,
    _QueueKind.incidentDraft => Icons.report_outlined,
    _QueueKind.incidentEvidence => Icons.photo_camera_back_outlined,
  };
}

class _QueueEntry {
  const _QueueEntry({
    required this.id,
    required this.key,
    required this.kind,
    required this.payload,
  });

  final String id;
  final dynamic key;
  final _QueueKind kind;
  final Map<String, dynamic> payload;

  DateTime get timestamp {
    final raw = payload['created_at'] ?? payload['recorded_at'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String get timestampLabel {
    final t = timestamp.toLocal();
    if (t.millisecondsSinceEpoch == 0) return 'Time n/a';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  String get title {
    final tripId = payload['trip_id']?.toString() ?? '-';
    return switch (kind) {
      _QueueKind.status => 'Trip #$tripId status: ${payload['status']}',
      _QueueKind.preTrip => 'Trip #$tripId pre-trip payload',
      _QueueKind.media => _mediaTitle(tripId),
      _QueueKind.ping => 'Trip #$tripId location ping',
      _QueueKind.fuel => _fuelTitle(tripId),
      _QueueKind.driverDoc =>
        'Driver doc upload: ${payload['title'] ?? payload['type'] ?? 'document'}',
      _QueueKind.incidentDraft =>
        'Incident draft: ${payload['title'] ?? payload['incident_type'] ?? 'incident'}',
      _QueueKind.incidentEvidence =>
        'Incident #${payload['incident_id'] ?? '-'} evidence',
    };
  }

  String get meta {
    final sizeBytes = _estimateSizeBytes(payload);
    final sizeLabel = _formatBytes(sizeBytes);
    return sizeLabel;
  }

  String _mediaTitle(String tripId) {
    final type = payload['type']?.toString();
    if (type == 'attachments') return 'Trip #$tripId attachment batch';
    if (type == 'evidence') {
      final kind = payload['kind']?.toString().replaceAll('_', ' ');
      return 'Trip #$tripId evidence: ${kind ?? 'photo'}';
    }
    return 'Trip #$tripId media payload';
  }

  String _fuelTitle(String tripId) {
    final scope = payload['scope']?.toString() ?? 'trip';
    if (scope == 'vehicle') {
      final vehicleId = payload['vehicle_id']?.toString() ?? '-';
      return 'Vehicle #$vehicleId fuel log';
    }
    return 'Trip #$tripId fuel log';
  }

  int _estimateSizeBytes(Map<String, dynamic> map) {
    var bytes = 0;
    for (final entry in map.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value;
      if (key.endsWith('_path') && value is String && value.isNotEmpty) {
        final file = File(value);
        if (file.existsSync()) {
          bytes += file.lengthSync();
        }
      }
    }
    if (bytes > 0) return bytes;
    return utf8.encode(jsonEncode(map)).length;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}
