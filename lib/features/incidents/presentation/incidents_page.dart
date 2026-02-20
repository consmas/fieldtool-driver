import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../offline/hive_boxes.dart';
import '../../trips/data/trips_repository.dart';
import '../data/incidents_repository.dart';

class IncidentsPage extends ConsumerStatefulWidget {
  const IncidentsPage({super.key, this.initialTripId});

  final int? initialTripId;

  @override
  ConsumerState<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends ConsumerState<IncidentsPage>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationTextController = TextEditingController();
  final _noteController = TextEditingController();
  late final TabController _tabController = TabController(length: 2, vsync: this);
  final _picker = ImagePicker();

  bool _loading = true;
  bool _submitting = false;
  bool _uploading = false;
  List<DriverIncident> _history = const [];

  int? _activeTripId;
  int? _createdIncidentId;
  double? _lat;
  double? _lng;
  String _type = 'safety';
  String _severity = 'medium';
  String _evidenceCategory = 'scene';
  bool _injuryReported = false;
  bool _vehicleDrivable = true;

  int get _queueCount {
    var count = 0;
    count += Hive.box<Map>(HiveBoxes.incidentDraftsQueue).length;
    count += Hive.box<Map>(HiveBoxes.incidentEvidenceQueue).length;
    return count;
  }

  @override
  void initState() {
    super.initState();
    _activeTripId = widget.initialTripId;
    _bootstrap();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationTextController.dispose();
    _noteController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final futures = <Future<void>>[_loadHistory()];
      if (_activeTripId == null) {
        futures.add(_resolveActiveTripId());
      }
      futures.add(_captureLocation());
      await Future.wait(futures);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveActiveTripId() async {
    try {
      final trips = await ref.read(tripsRepositoryProvider).fetchAssignedTrips();
      final active = trips.where((t) {
        return {
          'assigned',
          'loaded',
          'en_route',
          'arrived',
          'offloaded',
        }.contains(t.status);
      }).toList();
      if (active.isNotEmpty) {
        _activeTripId = active.first.id;
      }
    } catch (_) {}
  }

  Future<void> _captureLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _lat = position.latitude;
      _lng = position.longitude;
      _locationTextController.text =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final incidents = await ref.read(incidentsRepositoryProvider).fetchMyIncidents();
    if (!mounted) return;
    setState(() => _history = incidents);
  }

  Future<void> _submitIncident() async {
    if (_titleController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and incident details are required.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final incidentId = await ref.read(incidentsRepositoryProvider).createIncident(
            tripId: _activeTripId?.toString(),
            incidentType: _type,
            severity: _severity,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            injuryReported: _injuryReported,
            vehicleDrivable: _vehicleDrivable,
            locationText: _locationTextController.text.trim(),
            lat: _lat,
            lng: _lng,
          );
      if (!mounted) return;
      setState(() => _createdIncidentId = incidentId);
      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            incidentId == null
                ? 'Incident saved offline and queued for sync.'
                : 'Incident submitted successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Incident submit failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _captureEvidence() async {
    if (_createdIncidentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submit incident first before adding evidence.'),
        ),
      );
      return;
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await ref.read(incidentsRepositoryProvider).uploadIncidentEvidence(
            incidentId: _createdIncidentId!,
            category: _evidenceCategory,
            file: file,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
      if (!mounted) return;
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidence uploaded (or queued offline).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Evidence upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidents'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Quick Report'), Tab(text: 'History')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
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
                TabBarView(
                  controller: _tabController,
                  children: [_buildQuickReport(), _buildHistory()],
                ),
              ],
            ),
    );
  }

  Widget _buildQuickReport() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_queueCount > 0) ...[
          AlertBanner(
            type: AlertType.warning,
            message: 'Incident queue pending: $_queueCount item(s).',
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        SectionCard(
          title: 'Quick Incident Report',
          children: [
            InfoRow(
              label: 'Trip',
              value: _activeTripId == null ? 'No active trip' : '#$_activeTripId',
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Incident type'),
              items: const [
                DropdownMenuItem(value: 'safety', child: Text('Safety')),
                DropdownMenuItem(value: 'damage', child: Text('Damage')),
                DropdownMenuItem(value: 'security', child: Text('Security')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _type = value ?? 'safety'),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'critical', child: Text('Critical')),
              ],
              onChanged: (value) => setState(() => _severity = value ?? 'medium'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'What happened'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _locationTextController,
              decoration: const InputDecoration(
                labelText: 'Location (auto-filled from GPS)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Injury'),
                    value: _injuryReported,
                    onChanged: (value) => setState(() => _injuryReported = value),
                  ),
                ),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vehicle drivable'),
                    value: _vehicleDrivable,
                    onChanged: (value) => setState(() => _vehicleDrivable = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submitIncident,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.warning_amber_outlined),
                label: Text(_submitting ? 'Submitting...' : 'Submit Incident'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Scene Evidence',
          children: [
            if (_createdIncidentId == null)
              const Text('Submit the incident first to enable evidence upload.'),
            DropdownButtonFormField<String>(
              initialValue: _evidenceCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'scene', child: Text('Scene')),
                DropdownMenuItem(value: 'damage', child: Text('Damage')),
                DropdownMenuItem(
                  value: 'police_report',
                  child: Text('Police report'),
                ),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _createdIncidentId == null
                  ? null
                  : (value) => setState(() => _evidenceCategory = value ?? 'scene'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _noteController,
              enabled: _createdIncidentId != null,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_createdIncidentId == null || _uploading)
                        ? null
                        : _captureEvidence,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Capture'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_history.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.only(top: 120),
              child: Text('No incidents reported yet.'),
            ))
          else
            ..._history.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: SectionCard(
                  title: '${item.incidentNo} • ${item.title}',
                  children: [
                    InfoRow(label: 'Type', value: item.incidentType),
                    InfoRow(label: 'Severity', value: item.severity),
                    InfoRow(label: 'Status', value: item.status),
                    InfoRow(
                      label: 'Created',
                      value:
                          '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}',
                      showDivider: false,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
