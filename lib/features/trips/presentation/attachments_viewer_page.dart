import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../offline/hive_boxes.dart';
import '../data/trips_repository.dart';
import '../domain/trip.dart';

final tripAttachmentsBundleProvider =
    FutureProvider.family<_AttachmentsBundle, int>((ref, tripId) async {
      final repo = ref.read(tripsRepositoryProvider);
      final trip = await repo.fetchTrip(tripId);
      final preTrip = await repo.fetchPreTrip(tripId);
      List<Map<String, dynamic>> evidence = const [];
      try {
        evidence = await repo.fetchTripEvidence(tripId);
      } catch (_) {
        evidence = const [];
      }
      return _AttachmentsBundle(trip: trip, preTrip: preTrip, evidence: evidence);
    });

class AttachmentsViewerPage extends ConsumerStatefulWidget {
  const AttachmentsViewerPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<AttachmentsViewerPage> createState() =>
      _AttachmentsViewerPageState();
}

class _AttachmentsViewerPageState extends ConsumerState<AttachmentsViewerPage> {
  Future<void> _refresh() async {
    ref.invalidate(tripAttachmentsBundleProvider(widget.tripId));
    await ref.read(tripAttachmentsBundleProvider(widget.tripId).future);
  }

  @override
  Widget build(BuildContext context) {
    final asyncBundle = ref.watch(tripAttachmentsBundleProvider(widget.tripId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attachments'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Photos'),
              Tab(text: 'Docs'),
              Tab(text: 'Signatures'),
            ],
          ),
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
            asyncBundle.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (bundle) {
                final mediaQueue = _queuedItems(HiveBoxes.evidenceQueue);
                final preTripQueue = _queuedItems(HiveBoxes.preTripQueue);
                final photos = _buildPhotoItems(bundle, mediaQueue, preTripQueue);
                final docs = _buildDocItems(bundle, mediaQueue, preTripQueue);
                final signatures = _buildSignatureItems(
                  bundle,
                  mediaQueue,
                  preTripQueue,
                );
                return TabBarView(
                  children: [
                    _PhotoTab(
                      items: photos,
                      onOpen: _openPreview,
                      onRetry: _retryQueuedItem,
                      onShare: _shareItem,
                      onRefresh: _refresh,
                    ),
                    _DocTab(
                      items: docs,
                      onRetry: _retryQueuedItem,
                      onShare: _shareItem,
                    ),
                    _SignatureTab(
                      items: signatures,
                      onOpen: _openPreview,
                      onRetry: _retryQueuedItem,
                      onShare: _shareItem,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_QueueItem> _queuedItems(String boxName) {
    final box = Hive.box<Map>(boxName);
    final type = boxName == HiveBoxes.preTripQueue
        ? _QueueType.preTrip
        : _QueueType.media;
    final items = <_QueueItem>[];
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null || value['trip_id'] != widget.tripId) continue;
      items.add(
        _QueueItem(
          key: key,
          queueType: type,
          payload: Map<String, dynamic>.from(value),
        ),
      );
    }
    return items;
  }

  List<_ViewerItem> _buildPhotoItems(
    _AttachmentsBundle bundle,
    List<_QueueItem> mediaQueue,
    List<_QueueItem> preTripQueue,
  ) {
    final items = <_ViewerItem>[];
    final dedupe = <String>{};
    final preTrip = _normalizedPreTrip(bundle.preTrip);
    final trip = bundle.trip;

    void addRemote({
      required String title,
      required String group,
      required String? url,
      DateTime? capturedAt,
    }) {
      if (url == null || url.isEmpty) return;
      if (!dedupe.add('remote:$url')) return;
      items.add(
        _ViewerItem(
          title: title,
          group: group,
          url: url,
          status: _UploadStatus.uploaded,
          capturedAt: capturedAt,
        ),
      );
    }

    addRemote(title: 'Start odometer', group: 'Loading', url: trip.startOdometerPhotoUrl);
    addRemote(title: 'End odometer', group: 'Fuel', url: trip.endOdometerPhotoUrl);
    addRemote(title: 'Fuel proof', group: 'Fuel', url: trip.proofOfFuellingUrl);
    addRemote(title: 'Odometer', group: 'Loading', url: _preTripValue(preTrip, 'odometer_photo_url'));
    addRemote(title: 'Load photo', group: 'Loading', url: _preTripValue(preTrip, 'load_photo_url'));
    addRemote(title: 'Waybill', group: 'Waybill', url: _preTripValue(preTrip, 'waybill_photo_url'));
    addRemote(title: 'Inspector photo', group: 'Loading', url: _preTripValue(preTrip, 'inspector_photo_url'));

    for (final asset in _extractChecklistAssets(bundle.preTrip)) {
      if (asset.isSignature) continue;
      addRemote(
        title: asset.title,
        group: 'Checklist',
        url: asset.url,
      );
    }

    for (final e in bundle.evidence) {
      final url =
          e['photo_url']?.toString() ??
          e['photo']?.toString() ??
          e['file_url']?.toString() ??
          e['url']?.toString() ??
          '';
      if (url.isEmpty || !dedupe.add('remote:$url')) continue;
      final kind = e['kind']?.toString() ?? 'arrival';
      items.add(
        _ViewerItem(
          title: kind.replaceAll('_', ' '),
          group: _groupForKind(kind),
          url: url,
          status: _UploadStatus.uploaded,
          capturedAt: _parseTime(
            e['recorded_at']?.toString() ?? e['captured_at']?.toString(),
          ),
        ),
      );
    }

    for (final q in mediaQueue) {
      if (q.payload['type']?.toString() == 'evidence') {
        final path = q.payload['photo_path']?.toString();
        if (path == null || path.isEmpty || !dedupe.add('local:$path')) continue;
        items.add(
          _ViewerItem(
            title: q.payload['kind']?.toString() ?? 'Queued photo',
            group: _groupForKind(q.payload['kind']?.toString() ?? ''),
            localPath: path,
            status: _statusForPath(path),
            queueKey: q.key,
            queueType: q.queueType,
          ),
        );
      }
      if (q.payload['type']?.toString() == 'attachments') {
        final fuelPath = q.payload['proof_of_fuelling_path']?.toString();
        if (fuelPath != null &&
            fuelPath.isNotEmpty &&
            dedupe.add('local:$fuelPath')) {
          items.add(
            _ViewerItem(
              title: 'Fuel proof',
              group: 'Fuel',
              localPath: fuelPath,
              status: _statusForPath(fuelPath),
              queueKey: q.key,
              queueType: q.queueType,
            ),
          );
        }
      }
    }

    for (final q in preTripQueue) {
      const mapping = {
        'odometer_photo_path': ('Odometer', 'Loading'),
        'inspector_photo_path': ('Inspector photo', 'Loading'),
        'waybill_photo_path': ('Waybill', 'Waybill'),
        'load_photo_path': ('Load photo', 'Loading'),
      };
      mapping.forEach((k, v) {
        final path = q.payload[k]?.toString();
        if (path == null || path.isEmpty || !dedupe.add('local:$path')) return;
        items.add(
          _ViewerItem(
            title: v.$1,
            group: v.$2,
            localPath: path,
            status: _statusForPath(path),
            queueKey: q.key,
            queueType: q.queueType,
          ),
        );
      });

      for (final entry in q.payload.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value?.toString();
        if (value == null || value.isEmpty) continue;
        if (!key.contains('checklist')) continue;
        if (!key.endsWith('_path')) continue;
        if (!dedupe.add('local:$value')) continue;
        items.add(
          _ViewerItem(
            title: 'Checklist photo',
            group: 'Checklist',
            localPath: value,
            status: _statusForPath(value),
            queueKey: q.key,
            queueType: q.queueType,
          ),
        );
      }
    }
    return items;
  }

  List<_ViewerItem> _buildDocItems(
    _AttachmentsBundle bundle,
    List<_QueueItem> mediaQueue,
    List<_QueueItem> preTripQueue,
  ) {
    final items = <_ViewerItem>[];
    final preTrip = _normalizedPreTrip(bundle.preTrip);
    final waybill = _preTripValue(preTrip, 'waybill_photo_url');
    if (waybill != null && waybill.isNotEmpty) {
      items.add(
        const _ViewerItem(
          title: 'Waybill Document',
          mimeType: 'image',
          sizeLabel: '—',
          status: _UploadStatus.uploaded,
        ).copyWith(url: waybill),
      );
    }

    for (final q in mediaQueue) {
      if (q.payload['type']?.toString() != 'attachments') continue;
      final path = q.payload['proof_of_fuelling_path']?.toString();
      if (path == null || path.isEmpty) continue;
      items.add(
        _ViewerItem(
          title: 'Fuel Proof (Local)',
          localPath: path,
          mimeType: 'image',
          sizeLabel: _fileSizeLabel(path),
          status: _statusForPath(path),
          queueKey: q.key,
          queueType: q.queueType,
        ),
      );
    }
    for (final q in preTripQueue) {
      final path = q.payload['waybill_photo_path']?.toString();
      if (path == null || path.isEmpty) continue;
      items.add(
        _ViewerItem(
          title: 'Waybill Document (Local)',
          localPath: path,
          mimeType: 'image',
          sizeLabel: _fileSizeLabel(path),
          status: _statusForPath(path),
          queueKey: q.key,
          queueType: q.queueType,
        ),
      );
    }
    return items;
  }

  List<_ViewerItem> _buildSignatureItems(
    _AttachmentsBundle bundle,
    List<_QueueItem> mediaQueue,
    List<_QueueItem> preTripQueue,
  ) {
    final preTrip = _normalizedPreTrip(bundle.preTrip);
    final trip = bundle.trip;
    final items = <_ViewerItem>[];

    void addSig(String title, String? url, DateTime? capturedAt) {
      if (url == null || url.isEmpty) return;
      items.add(
        _ViewerItem(
          title: title,
          url: url,
          capturedAt: capturedAt,
          status: _UploadStatus.uploaded,
        ),
      );
    }

    addSig('Client Rep', trip.clientRepSignatureUrl, trip.arrivalTimeAtSite);
    addSig('Inspector', trip.inspectorSignatureUrl, null);
    addSig('Security', trip.securitySignatureUrl, null);
    addSig('Driver', trip.driverSignatureUrl, null);
    addSig(
      'Inspector (Pre-trip)',
      _preTripValue(preTrip, 'inspector_signature_url'),
      _parseTime(_preTripValue(preTrip, 'accepted_at')),
    );
    for (final asset in _extractChecklistAssets(bundle.preTrip)) {
      if (!asset.isSignature) continue;
      addSig(asset.title, asset.url, null);
    }

    for (final q in mediaQueue) {
      if (q.payload['type']?.toString() != 'attachments') continue;
      const mapping = {
        'client_rep_signature_path': 'Client Rep',
        'inspector_signature_path': 'Inspector',
        'security_signature_path': 'Security',
        'driver_signature_path': 'Driver',
      };
      mapping.forEach((k, title) {
        final path = q.payload[k]?.toString();
        if (path == null || path.isEmpty) return;
        items.add(
          _ViewerItem(
            title: '$title (Local)',
            localPath: path,
            status: _statusForPath(path),
            queueKey: q.key,
            queueType: q.queueType,
          ),
        );
      });
    }
    for (final q in preTripQueue) {
      final path = q.payload['inspector_signature_path']?.toString();
      if (path == null || path.isEmpty) continue;
      items.add(
        _ViewerItem(
          title: 'Inspector (Pre-trip Local)',
          localPath: path,
          status: _statusForPath(path),
          queueKey: q.key,
          queueType: q.queueType,
        ),
      );
    }
    return items;
  }

  Map<String, dynamic> _normalizedPreTrip(Map<String, dynamic>? raw) {
    if (raw == null) return const <String, dynamic>{};
    final nested = raw['pre_trip'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return raw;
  }

  String? _preTripValue(Map<String, dynamic> preTrip, String key) {
    final direct = preTrip[key];
    if (direct != null && direct.toString().isNotEmpty) return direct.toString();
    final bracket = preTrip['pre_trip[$key]'];
    if (bracket != null && bracket.toString().isNotEmpty) {
      return bracket.toString();
    }
    return null;
  }

  _UploadStatus _statusForPath(String path) {
    return File(path).existsSync() ? _UploadStatus.uploading : _UploadStatus.failed;
  }

  Future<void> _retryQueuedItem(_ViewerItem item) async {
    if (item.queueKey == null || item.queueType == null) return;
    try {
      if (item.queueType == _QueueType.media) {
        final box = Hive.box<Map>(HiveBoxes.evidenceQueue);
        final payload = box.get(item.queueKey);
        if (payload == null) return;
        await ref
            .read(tripsRepositoryProvider)
            .replayQueuedMedia(Map<String, dynamic>.from(payload));
        await box.delete(item.queueKey);
      } else {
        final box = Hive.box<Map>(HiveBoxes.preTripQueue);
        final payload = box.get(item.queueKey);
        if (payload == null) return;
        await ref
            .read(tripsRepositoryProvider)
            .replayQueuedPreTrip(Map<String, dynamic>.from(payload));
        await box.delete(item.queueKey);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Retry successful.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: $e')));
    }
  }

  void _openPreview(_ViewerItem item) {
    final hasImage =
        (item.url != null && item.url!.isNotEmpty) ||
        (item.localPath != null && item.localPath!.isNotEmpty);
    if (!hasImage) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ImagePreviewPage(item: item)),
    );
  }

  Future<void> _shareItem(_ViewerItem item) async {
    final url = item.url;
    if (url == null || url.isEmpty) return;
    final email = Uri.parse(
      'mailto:?subject=Trip Attachment&body=${Uri.encodeComponent(url)}',
    );
    final whatsapp = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(url)}');
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Share via Email'),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(email);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Share via WhatsApp'),
              onTap: () async {
                Navigator.pop(context);
                await launchUrl(whatsapp, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _groupForKind(String kind) {
    switch (kind) {
      case 'before_loading':
      case 'after_loading':
      case 'loading':
        return 'Loading';
      case 'arrival':
        return 'Arrival';
      case 'offloading':
      case 'waybill':
        return 'Waybill';
      case 'fuel':
        return 'Fuel';
      default:
        return 'Arrival';
    }
  }

  DateTime? _parseTime(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _fileSizeLabel(String path) {
    final file = File(path);
    if (!file.existsSync()) return '—';
    final bytes = file.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<_ChecklistAsset> _extractChecklistAssets(Map<String, dynamic>? raw) {
    if (raw == null) return const [];
    final assets = <_ChecklistAsset>[];
    final seen = <String>{};

    void add(String keyPath, String url) {
      if (url.isEmpty || !url.startsWith('http')) return;
      if (!seen.add(url)) return;
      final lower = keyPath.toLowerCase();
      final isSignature = lower.contains('signature');
      final title = isSignature ? 'Checklist signature' : 'Checklist image';
      assets.add(_ChecklistAsset(title: title, url: url, isSignature: isSignature));
    }

    void walk(dynamic node, String path, {required bool onlyChecklist}) {
      if (node is Map) {
        node.forEach((k, v) {
          final key = k.toString();
          final nextPath = path.isEmpty ? key : '$path.$key';
          final nextOnlyChecklist =
              onlyChecklist || nextPath.toLowerCase().contains('core_checklist');
          if (v is String) {
            final lk = key.toLowerCase();
            if (!nextOnlyChecklist) return;
            final looksLikeImageKey =
                lk.contains('photo') ||
                lk.contains('image') ||
                lk.contains('signature') ||
                lk.contains('attachment') ||
                lk.contains('file');
            if (looksLikeImageKey && lk.contains('url')) {
              add(nextPath, v);
            }
          } else {
            walk(v, nextPath, onlyChecklist: nextOnlyChecklist);
          }
        });
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], '$path[$i]', onlyChecklist: onlyChecklist);
        }
      }
    }

    final normalized = _normalizedPreTrip(raw);
    walk(normalized['core_checklist'], 'core_checklist', onlyChecklist: true);
    final checklistJson = normalized['core_checklist_json'];
    if (checklistJson is String && checklistJson.trim().isNotEmpty) {
      try {
        walk(jsonDecode(checklistJson), 'core_checklist_json', onlyChecklist: true);
      } catch (_) {}
    } else {
      walk(checklistJson, 'core_checklist_json', onlyChecklist: true);
    }
    return assets;
  }
}

class _ChecklistAsset {
  const _ChecklistAsset({
    required this.title,
    required this.url,
    required this.isSignature,
  });

  final String title;
  final String url;
  final bool isSignature;
}

class _AttachmentsBundle {
  const _AttachmentsBundle({
    required this.trip,
    required this.preTrip,
    required this.evidence,
  });

  final Trip trip;
  final Map<String, dynamic>? preTrip;
  final List<Map<String, dynamic>> evidence;
}

enum _QueueType { media, preTrip }

class _QueueItem {
  const _QueueItem({
    required this.key,
    required this.queueType,
    required this.payload,
  });

  final dynamic key;
  final _QueueType queueType;
  final Map<String, dynamic> payload;
}

enum _UploadStatus { uploaded, uploading, failed }

class _ViewerItem {
  const _ViewerItem({
    required this.title,
    this.group,
    this.url,
    this.localPath,
    this.mimeType,
    this.sizeLabel,
    this.capturedAt,
    this.status = _UploadStatus.uploaded,
    this.queueKey,
    this.queueType,
  });

  final String title;
  final String? group;
  final String? url;
  final String? localPath;
  final String? mimeType;
  final String? sizeLabel;
  final DateTime? capturedAt;
  final _UploadStatus status;
  final dynamic queueKey;
  final _QueueType? queueType;

  _ViewerItem copyWith({
    String? title,
    String? group,
    String? url,
    String? localPath,
    String? mimeType,
    String? sizeLabel,
    DateTime? capturedAt,
    _UploadStatus? status,
    dynamic queueKey,
    _QueueType? queueType,
  }) {
    return _ViewerItem(
      title: title ?? this.title,
      group: group ?? this.group,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      mimeType: mimeType ?? this.mimeType,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      queueKey: queueKey ?? this.queueKey,
      queueType: queueType ?? this.queueType,
    );
  }
}

class _PhotoTab extends StatelessWidget {
  const _PhotoTab({
    required this.items,
    required this.onOpen,
    required this.onRetry,
    required this.onShare,
    required this.onRefresh,
  });

  final List<_ViewerItem> items;
  final ValueChanged<_ViewerItem> onOpen;
  final ValueChanged<_ViewerItem> onRetry;
  final ValueChanged<_ViewerItem> onShare;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_ViewerItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.group ?? 'Other', () => []).add(item);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: grouped.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: entry.value.length,
                  itemBuilder: (context, index) {
                    final item = entry.value[index];
                    return _MediaCard(
                      item: item,
                      onTap: () => onOpen(item),
                      onLongPress: () => onShare(item),
                      onRetry: () => onRetry(item),
                    );
                  },
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DocTab extends StatelessWidget {
  const _DocTab({
    required this.items,
    required this.onRetry,
    required this.onShare,
  });

  final List<_ViewerItem> items;
  final ValueChanged<_ViewerItem> onRetry;
  final ValueChanged<_ViewerItem> onShare;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No documents available.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            onLongPress: () => onShare(item),
            leading: const Icon(Icons.description_outlined),
            title: Text(item.title),
            subtitle: Text(
              '${item.mimeType ?? 'file'} • ${item.sizeLabel ?? '—'} • ${_statusLabel(item.status)}',
            ),
            trailing: item.status == _UploadStatus.uploaded
                ? const Icon(Icons.check_circle, color: AppColors.successGreen)
                : TextButton(
                    onPressed: () => onRetry(item),
                    child: const Text('Retry'),
                  ),
          ),
        );
      },
    );
  }
}

class _SignatureTab extends StatelessWidget {
  const _SignatureTab({
    required this.items,
    required this.onOpen,
    required this.onRetry,
    required this.onShare,
  });

  final List<_ViewerItem> items;
  final ValueChanged<_ViewerItem> onOpen;
  final ValueChanged<_ViewerItem> onRetry;
  final ValueChanged<_ViewerItem> onShare;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No signatures captured yet.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaCard(
          item: item,
          onTap: () => onOpen(item),
          onLongPress: () => onShare(item),
          onRetry: () => onRetry(item),
          footer: item.capturedAt == null
              ? item.title
              : '${item.title}\n${item.capturedAt!.toLocal()}',
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.onRetry,
    this.footer,
  });

  final _ViewerItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (item.localPath != null && item.localPath!.isNotEmpty) {
      image = Image.file(File(item.localPath!), fit: BoxFit.cover);
    } else if (item.url != null && item.url!.isNotEmpty) {
      image = Image.network(item.url!, fit: BoxFit.cover);
    } else {
      image = const Center(child: Icon(Icons.image_not_supported_outlined));
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(width: double.infinity, child: image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      footer ?? item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StatusBadge(status: item.status),
                  if (item.status != _UploadStatus.uploaded)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      onPressed: onRetry,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final _UploadStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(status);
    final color = switch (status) {
      _UploadStatus.uploaded => AppColors.successGreen,
      _UploadStatus.uploading => AppColors.accentOrangeDark,
      _UploadStatus.failed => AppColors.errorRed,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _statusLabel(_UploadStatus status) {
  return switch (status) {
    _UploadStatus.uploaded => '✓ Uploaded',
    _UploadStatus.uploading => '⏳ Uploading',
    _UploadStatus.failed => '✕ Failed',
  };
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.item});
  final _ViewerItem item;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (item.localPath != null && item.localPath!.isNotEmpty) {
      image = Image.file(File(item.localPath!), fit: BoxFit.contain);
    } else {
      image = Image.network(item.url!, fit: BoxFit.contain);
    }
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(minScale: 0.8, maxScale: 5, child: image),
      ),
    );
  }
}
