import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import '../../../core/utils/app_theme.dart';
import '../../../core/utils/logger.dart';
import '../../../ui_kit/models/enums.dart';
import '../../../ui_kit/theme/app_colors.dart';
import '../../../ui_kit/theme/app_spacing.dart';
import '../../../ui_kit/widgets/badges.dart';
import '../../../ui_kit/widgets/buttons.dart';
import '../../../ui_kit/widgets/cards.dart';
import '../../../ui_kit/widgets/forms.dart';
import '../../../ui_kit/widgets/navigation.dart';
import '../data/trips_repository.dart';

class PreTripFormPage extends ConsumerStatefulWidget {
  const PreTripFormPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<PreTripFormPage> createState() => _PreTripFormPageState();
}

class _PreTripFormPageState extends ConsumerState<PreTripFormPage> {
  static const _lastInspectionChecklistPrefsKey =
      'pre_trip_last_core_checklist_v1';
  final _odometerController = TextEditingController();
  bool _accepted = true;
  bool _dispatchNotifiedForCurrentFailures = false;
  bool? _existingBrakes;
  bool? _existingTyres;
  bool? _existingLights;
  bool? _existingMirrors;
  bool? _existingHorn;
  bool? _existingFuelSufficient;

  XFile? _odometerPhoto;
  XFile? _inspectorSignatureFile;
  XFile? _inspectorPhoto;
  String? _existingOdometerPhotoUrl;
  String? _existingInspectorSignatureUrl;
  String? _existingInspectorPhotoUrl;

  bool _loadingExisting = true;
  String _loadStage = 'init';
  String? _loadError;
  String? _loadSummary;
  bool _hasExistingPreTrip = false;
  bool _existingOdometerPhoto = false;
  bool _submitting = false;

  late final SignatureController _signatureController;

  List<_CoreChecklistTemplateItem> _templateItems = const [];
  final Map<String, _InspectionDecision> _checklistState = {};
  final Map<String, TextEditingController> _checklistNoteCtrls = {};

  @override
  void initState() {
    super.initState();
    Logger.d('PreTripFormPage opened for trip ${widget.tripId}');
    _signatureController = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _loadExisting();
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _signatureController.dispose();
    for (final ctrl in _checklistNoteCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    if (mounted) {
      setState(() {
        _loadStage = 'fetch_pre_trip';
        _loadError = null;
      });
    }

    try {
      final raw = await ref
          .read(tripsRepositoryProvider)
          .fetchPreTrip(widget.tripId);
      final data = raw == null
          ? null
          : (raw['pre_trip'] is Map<String, dynamic>
                ? raw['pre_trip'] as Map<String, dynamic>
                : raw);

      if (!mounted) return;

      if (data != null) {
        bool parseBool(dynamic value, {bool fallback = false}) {
          if (value is bool) return value;
          if (value is num) return value != 0;
          if (value is String) {
            final v = value.toLowerCase().trim();
            if (v == 'true' || v == '1' || v == 'yes') return true;
            if (v == 'false' || v == '0' || v == 'no') return false;
          }
          return fallback;
        }

        final template = _parseTemplate(
          raw?['core_checklist_template'] ?? data['core_checklist_template'],
        ).where((item) => !_isLoadReadinessTemplateItem(item)).toList();
        final checklistValue =
            data['core_checklist'] ??
            data['core_checklist_json'] ??
            raw?['core_checklist'];
        final existingChecklist = _parseCoreChecklist(checklistValue);

        setState(() {
          _templateItems = template.isNotEmpty
              ? template
              : _defaultTemplate
                    .where((item) => !_isLoadReadinessTemplateItem(item))
                    .toList();
          _hasExistingPreTrip = true;
          _odometerController.text =
              data['odometer_value_km']?.toString() ?? '';
          _existingBrakes = parseBool(data['brakes'], fallback: true);
          _existingTyres = parseBool(data['tyres'], fallback: true);
          _existingLights = parseBool(data['lights'], fallback: true);
          _existingMirrors = parseBool(data['mirrors'], fallback: true);
          _existingHorn = parseBool(data['horn'], fallback: true);
          _existingFuelSufficient = parseBool(
            data['fuel_sufficient'],
            fallback: true,
          );
          _accepted = parseBool(data['accepted'], fallback: _accepted);
          _existingOdometerPhoto = parseBool(
            data['odometer_photo_attached'],
            fallback: false,
          );
          _existingOdometerPhotoUrl = data['odometer_photo_url']?.toString();
          _existingInspectorSignatureUrl = data['inspector_signature_url']
              ?.toString();
          _existingInspectorPhotoUrl = data['inspector_photo_url']?.toString();

          _hydrateChecklistState(data, existingChecklist);

          _loadSummary =
              'loaded id=${data['id']} trip=${data['trip_id']} template=${_templateItems.length}';
        });
      } else if (mounted) {
        final savedDefaults = await _loadSavedChecklistDefaults();
        var appliedDefaults = 0;
        setState(() {
          _templateItems = _defaultTemplate
              .where((item) => !_isLoadReadinessTemplateItem(item))
              .toList();
          _initEmptyChecklistState();
          appliedDefaults = _applySmartDefaults(savedDefaults);
          _loadSummary = appliedDefaults > 0
              ? 'no_pre_trip_record smart_defaults=$appliedDefaults'
              : 'no_pre_trip_record';
        });
      }
    } catch (e, st) {
      Logger.e('Failed to load pre-trip', e, st);
      if (mounted) {
        setState(() {
          _templateItems = _defaultTemplate
              .where((item) => !_isLoadReadinessTemplateItem(item))
              .toList();
          _initEmptyChecklistState();
          _loadError = 'pre_trip_load_failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingExisting = false;
          _loadStage = 'ready';
        });
      }
    }
  }

  void _initEmptyChecklistState() {
    _checklistState
      ..clear()
      ..addEntries(
        _templateItems.map(
          (item) => MapEntry(item.code, _InspectionDecision.unchecked),
        ),
      );
    for (final ctrl in _checklistNoteCtrls.values) {
      ctrl.dispose();
    }
    _checklistNoteCtrls.clear();
  }

  void _hydrateChecklistState(
    Map<String, dynamic> data,
    Map<String, ({String status, String? note})> existingChecklist,
  ) {
    _initEmptyChecklistState();

    for (final item in _templateItems) {
      final existing = existingChecklist[item.code];
      if (existing != null) {
        _checklistState[item.code] = _decisionFromApiStatus(existing.status);
        if ((existing.note ?? '').isNotEmpty) {
          _checklistNoteCtrls[item.code] = TextEditingController(
            text: existing.note,
          );
        }
        continue;
      }

      final inferred = _inferFromLegacy(item.code, data);
      if (inferred != null) {
        _checklistState[item.code] = inferred;
      }
    }
  }

  _InspectionDecision _decisionFromApiStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pass':
        return _InspectionDecision.passed;
      case 'fail':
        return _InspectionDecision.failed;
      case 'na':
        return _InspectionDecision.skipped;
      default:
        return _InspectionDecision.unchecked;
    }
  }

  _InspectionDecision? _inferFromLegacy(
    String code,
    Map<String, dynamic> data,
  ) {
    bool? boolValue;
    final lc = code.toLowerCase();

    bool parseBool(dynamic value, {bool fallback = false}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') return true;
        if (v == 'false' || v == '0' || v == 'no') return false;
      }
      return fallback;
    }

    if (lc.contains('brake')) {
      boolValue = parseBool(data['brakes'], fallback: true);
    } else if (lc.contains('tyre') || lc.contains('tire')) {
      boolValue = parseBool(data['tyres'], fallback: true);
    } else if (lc.contains('light')) {
      boolValue = parseBool(data['lights'], fallback: true);
    } else if (lc.contains('mirror')) {
      boolValue = parseBool(data['mirrors'], fallback: true);
    } else if (lc.contains('horn')) {
      boolValue = parseBool(data['horn'], fallback: true);
    } else if (lc.contains('fuel')) {
      boolValue = parseBool(data['fuel_sufficient'], fallback: true);
    } else if (lc.contains('declaration') || lc.contains('accepted')) {
      boolValue = parseBool(data['accepted'], fallback: true);
    }

    if (boolValue == null) return null;
    return boolValue ? _InspectionDecision.passed : _InspectionDecision.failed;
  }

  Map<String, ({String status, String? note})> _parseCoreChecklist(
    dynamic value,
  ) {
    final result = <String, ({String status, String? note})>{};
    dynamic payload = value;

    if (payload is String && payload.trim().isNotEmpty) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        return result;
      }
    }

    if (payload is! Map) return result;

    payload.forEach((key, raw) {
      final code = key.toString();
      if (raw is String) {
        result[code] = (status: raw, note: null);
        return;
      }
      if (raw is Map) {
        final status = raw['status']?.toString() ?? '';
        final note = raw['note']?.toString();
        if (status.isNotEmpty) {
          result[code] = (status: status, note: note);
        }
      }
    });

    return result;
  }

  List<_CoreChecklistTemplateItem> _parseTemplate(dynamic value) {
    if (value is! List) return const [];
    final items = <_CoreChecklistTemplateItem>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final code = entry['code']?.toString();
      if (code == null || code.isEmpty) continue;
      items.add(
        _CoreChecklistTemplateItem(
          code: code,
          label: entry['label']?.toString() ?? code,
          section: entry['section']?.toString() ?? 'General',
          severityOnFail: entry['severity_on_fail']?.toString(),
        ),
      );
    }
    return items;
  }

  Future<void> _pickPhoto(ValueSetter<XFile?> setter) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (file != null) {
      setState(() => setter(file));
    }
  }

  Future<XFile?> _exportSignature() async {
    final bytes = await _signatureController.toPngBytes();
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/inspector_signature_${widget.tripId}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return XFile(file.path);
  }

  int get _totalChecklistItems => _checklistState.length;

  int get _completedChecklistItems => _checklistState.values
      .where((state) => state != _InspectionDecision.unchecked)
      .length;

  int get _failedChecklistItems => _checklistState.values
      .where((state) => state == _InspectionDecision.failed)
      .length;

  int get _blockerFailedItems {
    var count = 0;
    for (final item in _templateItems) {
      if (item.isBlocker &&
          _checklistState[item.code] == _InspectionDecision.failed) {
        count += 1;
      }
    }
    return count;
  }

  bool get _hasFailures => _failedChecklistItems > 0;

  double get _checklistProgress => _totalChecklistItems == 0
      ? 0
      : _completedChecklistItems / _totalChecklistItems;

  List<({String title, List<_CoreChecklistTemplateItem> items})>
  get _orderedSections {
    final grouped = <String, List<_CoreChecklistTemplateItem>>{};
    for (final item in _templateItems) {
      final sectionKey = item.section.trim().isEmpty ? 'general' : item.section;
      grouped.putIfAbsent(sectionKey, () => []).add(item);
    }
    return grouped.entries
        .map((entry) => (title: _sectionTitle(entry.key), items: entry.value))
        .toList();
  }

  String _sectionTitle(String rawSection) {
    final section = rawSection.toLowerCase().trim();
    if (section == 'vehicle_exterior') return 'Vehicle Exterior';
    if (section == 'engine_fluids' || section == 'engine') {
      return 'Engine & Fluids';
    }
    if (section == 'tyres') return 'Tyres';
    if (section == 'brakes') return 'Brakes';
    if (section == 'steering') return 'Steering';
    if (section == 'coupling') return 'Coupling';
    if (section == 'safety') return 'Safety';
    if (section == 'load') return 'Load';
    if (section == 'docs' || section == 'documents') return 'Documents';
    if (section == 'documents') return 'Documents';
    return section
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<Map<String, _InspectionDecision>> _loadSavedChecklistDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastInspectionChecklistPrefsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final defaults = <String, _InspectionDecision>{};
      decoded.forEach((key, value) {
        final decision = _decisionFromApiStatus(value?.toString() ?? '');
        if (decision != _InspectionDecision.unchecked) {
          defaults[key.toString()] = decision;
        }
      });
      return defaults;
    } catch (_) {
      return {};
    }
  }

  int _applySmartDefaults(Map<String, _InspectionDecision> defaults) {
    var applied = 0;
    for (final item in _templateItems) {
      final decision = defaults[item.code];
      if (decision == null || decision == _InspectionDecision.unchecked) {
        continue;
      }
      if ((_checklistState[item.code] ?? _InspectionDecision.unchecked) ==
          _InspectionDecision.unchecked) {
        _checklistState[item.code] = decision;
        applied += 1;
      }
    }
    return applied;
  }

  Future<void> _persistChecklistDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, String>{};
    for (final item in _templateItems) {
      final decision = _checklistState[item.code];
      if (decision == null || decision == _InspectionDecision.unchecked) {
        continue;
      }
      payload[item.code] = _apiStatus(decision);
    }
    await prefs.setString(_lastInspectionChecklistPrefsKey, jsonEncode(payload));
  }

  void _onChecklistChanged(String code, _InspectionDecision decision) {
    setState(() {
      _checklistState[code] = decision;
      if (decision != _InspectionDecision.failed) {
        _checklistNoteCtrls[code]?.clear();
      }
      if (code.toLowerCase().contains('declaration') ||
          code.toLowerCase().contains('accepted')) {
        _accepted = decision == _InspectionDecision.passed;
      }
    });

    if (_hasFailures && !_dispatchNotifiedForCurrentFailures) {
      _notifyDispatchAboutFailures();
    }
    if (!_hasFailures) {
      _dispatchNotifiedForCurrentFailures = false;
    }
  }

  void _notifyDispatchAboutFailures() {
    _dispatchNotifiedForCurrentFailures = true;
    Logger.d(
      'Dispatch auto-notify trigger for trip ${widget.tripId}. Failed items: $_failedChecklistItems',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dispatch notification queued for checklist FAIL items.'),
      ),
    );
  }

  String _apiStatus(_InspectionDecision decision) {
    switch (decision) {
      case _InspectionDecision.passed:
        return 'pass';
      case _InspectionDecision.failed:
        return 'fail';
      case _InspectionDecision.skipped:
      case _InspectionDecision.unchecked:
        return 'na';
    }
  }

  Map<String, dynamic> _buildCoreChecklistPayload() {
    final payload = <String, dynamic>{};
    for (final item in _templateItems) {
      final decision =
          _checklistState[item.code] ?? _InspectionDecision.unchecked;
      final status = _apiStatus(decision);
      final note = _checklistNoteCtrls[item.code]?.text.trim();

      if (status == 'fail') {
        payload[item.code] = {
          'status': status,
          if (note != null && note.isNotEmpty) 'note': note,
        };
      } else {
        payload[item.code] = status;
      }
    }
    return payload;
  }

  bool _resolveLegacyBoolByKeyword({
    required List<String> keywords,
    required bool fallbackWhenUnknown,
    bool? existing,
  }) {
    for (final item in _templateItems) {
      final code = item.code.toLowerCase();
      if (!keywords.any(code.contains)) continue;
      final decision =
          _checklistState[item.code] ?? _InspectionDecision.unchecked;
      switch (decision) {
        case _InspectionDecision.passed:
          return true;
        case _InspectionDecision.failed:
          return false;
        case _InspectionDecision.skipped:
        case _InspectionDecision.unchecked:
          continue;
      }
    }
    return existing ?? fallbackWhenUnknown;
  }

  Future<void> _submit() async {
    final km = double.tryParse(_odometerController.text.trim());
    if (km == null || km <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid odometer value.')),
      );
      return;
    }

    if (_odometerPhoto == null && !_existingOdometerPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Odometer photo is required.')),
      );
      return;
    }

    if (_signatureController.isNotEmpty && _inspectorSignatureFile == null) {
      _inspectorSignatureFile = await _exportSignature();
    }

    setState(() => _submitting = true);

    double? lat;
    double? lng;
    DateTime? capturedAt;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
      if (_odometerPhoto != null || !_hasExistingPreTrip) {
        capturedAt = DateTime.now();
      }
    } catch (_) {}

    final coreChecklistPayload = _buildCoreChecklistPayload();

    final acceptedFromChecklist = _resolveLegacyBoolByKeyword(
      keywords: const ['declaration', 'accepted'],
      fallbackWhenUnknown: _accepted,
      existing: _accepted,
    );

    try {
      await ref
          .read(tripsRepositoryProvider)
          .submitPreTrip(
            tripId: widget.tripId,
            odometerValueKm: km,
            odometerPhoto: _odometerPhoto,
            inspectorSignature: _inspectorSignatureFile,
            inspectorPhoto: _inspectorPhoto,
            brakes: _resolveLegacyBoolByKeyword(
              keywords: const ['brake'],
              fallbackWhenUnknown: true,
              existing: _existingBrakes,
            ),
            tyres: _resolveLegacyBoolByKeyword(
              keywords: const ['tyre', 'tire'],
              fallbackWhenUnknown: true,
              existing: _existingTyres,
            ),
            lights: _resolveLegacyBoolByKeyword(
              keywords: const ['light'],
              fallbackWhenUnknown: true,
              existing: _existingLights,
            ),
            mirrors: _resolveLegacyBoolByKeyword(
              keywords: const ['mirror'],
              fallbackWhenUnknown: true,
              existing: _existingMirrors,
            ),
            horn: _resolveLegacyBoolByKeyword(
              keywords: const ['horn'],
              fallbackWhenUnknown: true,
              existing: _existingHorn,
            ),
            fuelSufficient: _resolveLegacyBoolByKeyword(
              keywords: const ['fuel'],
              fallbackWhenUnknown: true,
              existing: _existingFuelSufficient,
            ),
            accepted: acceptedFromChecklist,
            lat: lat,
            lng: lng,
            capturedAt: capturedAt,
            coreChecklist: coreChecklistPayload,
            update: _hasExistingPreTrip,
          );

      await Future.wait([
        ref.read(tripsRepositoryProvider).fetchTrip(widget.tripId),
        ref.read(tripsRepositoryProvider).fetchPreTrip(widget.tripId),
      ]);
      await _persistChecklistDefaults();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pre-trip inspection submitted.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      if (e is DioException) {
        Logger.e(
          'Pre-trip submission failed (${e.response?.statusCode})',
          e.response?.data ?? e,
          st,
        );
      } else {
        Logger.e('Pre-trip submission failed', e, st);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pre-Trip Inspection')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Loading: $_loadStage'),
                if (_loadError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Trip Checklist'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: Text(
                '$_completedChecklistItems of $_totalChecklistItems',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
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
          StickyBottomBar(
            bottomBar: BottomActionBar(
              secondary: AppSecondaryButton(
                label: 'Skip',
                fullWidth: true,
                onPressed: _submitting
                    ? null
                    : () => Navigator.pop(context, false),
              ),
              primary: AppPrimaryButton(
                label: 'Save & Continue',
                fullWidth: true,
                leadingIcon: Icons.check_circle_outline,
                variant: PrimaryButtonVariant.green,
                state: _submitting
                    ? LoadingButtonState.loading
                    : LoadingButtonState.idle,
                onPressed: _submitting ? null : _submit,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: AppColors.neutral200),
                    ),
                  ),
                  child: AppProgressBar(
                    value: _checklistProgress,
                    label: 'Progress',
                    valueLabel:
                        '$_completedChecklistItems of $_totalChecklistItems',
                    color: AppColors.primaryBlue,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadError != null ||
                            (kDebugMode && _loadSummary != null))
                          Card(
                            color: _loadError != null
                                ? Colors.red.shade50
                                : Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                _loadError ?? _loadSummary!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _loadError != null
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ),
                        if (_loadError != null ||
                            (kDebugMode && _loadSummary != null))
                          const SizedBox(height: AppSpacing.md),
                        if (_hasFailures) ...[
                          AlertBanner(
                            type: _blockerFailedItems > 0
                                ? AlertType.error
                                : AlertType.warning,
                            message: _failedChecklistItems == 1
                                ? '⚠ 1 item marked FAIL. Notify dispatch before departing.'
                                : '⚠ $_failedChecklistItems items marked FAIL. Notify dispatch before departing.',
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        ..._orderedSections.map(
                          (section) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: SectionCard(
                              title: section.title,
                              children: [
                                for (final item in section.items)
                                  _ChecklistDecisionRow(
                                    label: item.label,
                                    state:
                                        _checklistState[item.code] ??
                                        _InspectionDecision.unchecked,
                                    isBlocker: item.isBlocker,
                                    noteController: _checklistNoteCtrls
                                        .putIfAbsent(
                                          item.code,
                                          () => TextEditingController(),
                                        ),
                                    onChanged: (value) =>
                                        _onChecklistChanged(item.code, value),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SectionCard(
                          title: 'Odometer',
                          children: [
                            AppTextField(
                              label: 'Odometer (km)',
                              controller: _odometerController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              prefixIcon: Icons.speed_outlined,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _PhotoPicker(
                              label:
                                  _existingOdometerPhoto &&
                                      _odometerPhoto == null
                                  ? 'Odometer Photo (already uploaded)'
                                  : 'Odometer Photo (required)',
                              file: _odometerPhoto,
                              existingUrl: _existingOdometerPhotoUrl,
                              onPick: () =>
                                  _pickPhoto((file) => _odometerPhoto = file),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SectionCard(
                          title: 'Inspector',
                          children: [
                            if (_existingInspectorSignatureUrl != null &&
                                _existingInspectorSignatureUrl!.isNotEmpty &&
                                _signatureController.isEmpty &&
                                _inspectorSignatureFile == null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _PhotoPreview(
                                  url: _existingInspectorSignatureUrl,
                                ),
                              ),
                            Text(
                              'Inspector Signature (optional)',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 160,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Signature(
                                controller: _signatureController,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () {
                                    _signatureController.clear();
                                    setState(
                                      () => _inspectorSignatureFile = null,
                                    );
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Clear'),
                                ),
                                const SizedBox(width: 12),
                                if (_inspectorSignatureFile != null)
                                  const Text(
                                    'Signature captured',
                                    style: TextStyle(color: AppTheme.textMuted),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _PhotoPicker(
                              label:
                                  _existingInspectorPhotoUrl != null &&
                                      _inspectorPhoto == null
                                  ? 'Inspector Photo (already uploaded)'
                                  : 'Inspector Photo (optional)',
                              file: _inspectorPhoto,
                              existingUrl: _existingInspectorPhotoUrl,
                              onPick: () =>
                                  _pickPhoto((file) => _inspectorPhoto = file),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _InspectionDecision { unchecked, passed, failed, skipped }

class _CoreChecklistTemplateItem {
  const _CoreChecklistTemplateItem({
    required this.code,
    required this.label,
    required this.section,
    required this.severityOnFail,
  });

  final String code;
  final String label;
  final String section;
  final String? severityOnFail;

  bool get isBlocker => severityOnFail?.toLowerCase() == 'blocker';
}

const List<_CoreChecklistTemplateItem> _defaultTemplate = [
  _CoreChecklistTemplateItem(
    code: 'vehicle_exterior.lights_indicators_working',
    label: 'Lights & indicators',
    section: 'vehicle_exterior',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'vehicle_exterior.mirrors_windscreen_ok',
    label: 'Mirrors & windscreen',
    section: 'vehicle_exterior',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'vehicle_exterior.license_plate_visible',
    label: 'License plate visible',
    section: 'vehicle_exterior',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'vehicle_exterior.no_major_body_damage',
    label: 'No major body damage',
    section: 'vehicle_exterior',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'tyres.pressure_all_wheels_ok',
    label: 'Tyre pressure all wheels',
    section: 'tyres',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'tyres.tread_depth_ok',
    label: 'Tread depth',
    section: 'tyres',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'tyres.no_cuts_bulges_exposed_cord',
    label: 'No tyre cuts/bulges/exposed cord',
    section: 'tyres',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'tyres.wheel_nuts_secure',
    label: 'Wheel nuts secure',
    section: 'tyres',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'brakes.service_brake_ok',
    label: 'Service brake',
    section: 'brakes',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'brakes.parking_brake_ok',
    label: 'Parking brake',
    section: 'brakes',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'brakes.air_or_brake_warning_clear',
    label: 'Brake warning clear',
    section: 'brakes',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'steering.steering_response_ok',
    label: 'Steering response',
    section: 'steering',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'engine.engine_oil_level_ok',
    label: 'Engine oil level',
    section: 'engine',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'engine.coolant_level_ok',
    label: 'Coolant level',
    section: 'engine',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'engine.brake_fluid_level_ok',
    label: 'Brake fluid level',
    section: 'engine',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'engine.no_active_leaks',
    label: 'No active leaks',
    section: 'engine',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'coupling.kingpin_or_hitch_locked',
    label: 'Kingpin/hitch locked',
    section: 'coupling',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'coupling.air_electrical_lines_connected',
    label: 'Air/electrical lines connected',
    section: 'coupling',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'coupling.trailer_lights_working',
    label: 'Trailer lights',
    section: 'coupling',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'coupling.trailer_legs_raised_locked',
    label: 'Trailer legs raised/locked',
    section: 'coupling',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'safety.fire_extinguisher_present_charged',
    label: 'Fire extinguisher present/charged',
    section: 'safety',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'safety.warning_triangles_present',
    label: 'Warning triangles present',
    section: 'safety',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'safety.first_aid_kit_present',
    label: 'First aid kit present',
    section: 'safety',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'safety.seatbelt_driver_ok',
    label: 'Driver seatbelt',
    section: 'safety',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'docs.driver_license_valid',
    label: 'Driver license valid',
    section: 'docs',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'docs.vehicle_registration_present',
    label: 'Vehicle registration present',
    section: 'docs',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'docs.insurance_or_roadworthy_valid',
    label: 'Insurance/roadworthy valid',
    section: 'docs',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'docs.waybill_present',
    label: 'Waybill present',
    section: 'docs',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'load.load_area_ready',
    label: 'Load area ready',
    section: 'load',
    severityOnFail: 'warning',
  ),
  _CoreChecklistTemplateItem(
    code: 'load.load_secured',
    label: 'Load secured',
    section: 'load',
    severityOnFail: 'blocker',
  ),
  _CoreChecklistTemplateItem(
    code: 'load.weight_within_limit',
    label: 'Weight within limit',
    section: 'load',
    severityOnFail: 'warning',
  ),
];

class _ChecklistDecisionRow extends StatelessWidget {
  const _ChecklistDecisionRow({
    required this.label,
    required this.state,
    required this.isBlocker,
    required this.noteController,
    required this.onChanged,
  });

  final String label;
  final _InspectionDecision state;
  final bool isBlocker;
  final TextEditingController noteController;
  final ValueChanged<_InspectionDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    final fail = state == _InspectionDecision.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (fail) ...[
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(
                    '✕',
                    style: TextStyle(
                      color: AppColors.errorRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fail ? AppColors.errorRed : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isBlocker)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.errorRed.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'BLOCKER',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.errorRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DecisionChip(
                label: 'PASS',
                selected: state == _InspectionDecision.passed,
                selectedColor: AppColors.successGreen,
                onTap: () => onChanged(_InspectionDecision.passed),
              ),
              _DecisionChip(
                label: 'FAIL',
                selected: state == _InspectionDecision.failed,
                selectedColor: AppColors.errorRed,
                onTap: () => onChanged(_InspectionDecision.failed),
              ),
              _DecisionChip(
                label: 'N/A',
                selected: state == _InspectionDecision.skipped,
                selectedColor: AppColors.primaryBlue,
                onTap: () => onChanged(_InspectionDecision.skipped),
              ),
            ],
          ),
          if (fail) ...[
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Fail note (optional)',
              controller: noteController,
              hint: 'Describe issue',
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionChip extends StatelessWidget {
  const _DecisionChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedColor : AppColors.neutral300,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(url!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Existing signature',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.label,
    required this.file,
    required this.onPick,
    this.existingUrl,
  });

  final String label;
  final XFile? file;
  final VoidCallback onPick;
  final String? existingUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: file != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(file!.path), fit: BoxFit.cover),
                    )
                  : (existingUrl != null && existingUrl!.isNotEmpty)
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(existingUrl!, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.camera_alt, color: AppTheme.textMuted),
            ),
            const SizedBox(width: 12),
            AppSecondaryButton(
              label: 'Capture',
              fullWidth: false,
              leadingIcon: Icons.photo_camera,
              onPressed: onPick,
            ),
          ],
        ),
      ],
    );
  }
}
  bool _isLoadReadinessTemplateItem(_CoreChecklistTemplateItem item) {
    final code = item.code.toLowerCase().trim();
    return code == 'load.load_area_ready' ||
        code == 'load.load_secured' ||
        code == 'load.weight_within_limit' ||
        code == 'load.load_within_weight' ||
        code.contains('load_area_ready') ||
        code.contains('load_secured') ||
        code.contains('weight_within_limit') ||
        code.contains('load_within_weight');
  }
