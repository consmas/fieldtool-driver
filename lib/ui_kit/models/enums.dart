// ============================================================
// ConsMas FieldTool Driver — Domain Enums & Models
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ── Trip Status ───────────────────────────────────────────────
enum TripStatus {
  assigned,
  enRoute,
  arrived,
  offloaded,
  completed;

  /// Human-readable label shown in UI
  String get label => switch (this) {
    TripStatus.assigned  => 'Assigned',
    TripStatus.enRoute   => 'En Route',
    TripStatus.arrived   => 'Arrived',
    TripStatus.offloaded => 'Offloaded',
    TripStatus.completed => 'Completed',
  };

  /// API string used in requests/responses
  String get apiValue => switch (this) {
    TripStatus.assigned  => 'assigned',
    TripStatus.enRoute   => 'en_route',
    TripStatus.arrived   => 'arrived',
    TripStatus.offloaded => 'offloaded',
    TripStatus.completed => 'completed',
  };

  Color get badgeBg => switch (this) {
    TripStatus.assigned  => AppColors.statusAssignedBg,
    TripStatus.enRoute   => AppColors.statusEnRouteBg,
    TripStatus.arrived   => AppColors.statusArrivedBg,
    TripStatus.offloaded => const Color(0xFFEDE7F6),
    TripStatus.completed => AppColors.statusCompletedBg,
  };

  Color get badgeFg => switch (this) {
    TripStatus.assigned  => AppColors.statusAssignedFg,
    TripStatus.enRoute   => AppColors.statusEnRouteFg,
    TripStatus.arrived   => AppColors.statusArrivedFg,
    TripStatus.offloaded => const Color(0xFF512DA8),
    TripStatus.completed => AppColors.statusCompletedFg,
  };

  /// Icon code to accompany the badge (accessibility: not color-only)
  IconData get icon => switch (this) {
    TripStatus.assigned  => Icons.schedule_outlined,
    TripStatus.enRoute   => Icons.local_shipping_outlined,
    TripStatus.arrived   => Icons.place_outlined,
    TripStatus.offloaded => Icons.inventory_2_outlined,
    TripStatus.completed => Icons.check_circle_outlined,
  };

  bool get isLive => this == TripStatus.enRoute || this == TripStatus.arrived;

  /// Whether user can transition to [next]
  bool canTransitionTo(TripStatus next) {
    final order = TripStatus.values;
    return order.indexOf(next) == order.indexOf(this) + 1;
  }

  /// The logical next status (null if already completed)
  TripStatus? get next {
    final idx = TripStatus.values.indexOf(this);
    if (idx >= TripStatus.values.length - 1) return null;
    return TripStatus.values[idx + 1];
  }

  /// Primary action label for the bottom bar CTA on Trip Detail
  String? get primaryActionLabel => switch (this) {
    TripStatus.assigned  => null,
    TripStatus.enRoute   => '📍  Mark as Arrived',
    TripStatus.arrived   => '📦  Complete Delivery',
    TripStatus.offloaded => '🏁  End Trip',
    TripStatus.completed => null,
  };
}

// ── Sync Status ───────────────────────────────────────────────
enum SyncStatus {
  queued,
  syncing,
  synced,
  failed;

  String get label => switch (this) {
    SyncStatus.queued  => 'Queued',
    SyncStatus.syncing => 'Syncing',
    SyncStatus.synced  => 'Synced',
    SyncStatus.failed  => 'Failed',
  };

  Color get color => switch (this) {
    SyncStatus.queued  => AppColors.syncQueued,
    SyncStatus.syncing => AppColors.syncSyncing,
    SyncStatus.synced  => AppColors.syncSynced,
    SyncStatus.failed  => AppColors.syncFailed,
  };

  IconData get icon => switch (this) {
    SyncStatus.queued  => Icons.schedule_outlined,
    SyncStatus.syncing => Icons.sync,
    SyncStatus.synced  => Icons.check_circle_outline,
    SyncStatus.failed  => Icons.error_outline,
  };
}

// ── Checklist Item State ──────────────────────────────────────
enum ChecklistItemState {
  unchecked,
  passed,
  failed;

  String get label => switch (this) {
    ChecklistItemState.unchecked => 'Not checked',
    ChecklistItemState.passed    => 'Pass',
    ChecklistItemState.failed    => 'Fail',
  };
}

// ── Evidence Photo Type ───────────────────────────────────────
enum EvidenceType {
  loadingPhoto,
  sealVerification,
  deliveryArrival,
  signedWaybill,
  damage,
  odometerReading,
  fuelReceipt,
  other;

  String get label => switch (this) {
    EvidenceType.loadingPhoto    => 'Loading Photo',
    EvidenceType.sealVerification=> 'Seal Verification',
    EvidenceType.deliveryArrival => 'Delivery Arrival',
    EvidenceType.signedWaybill   => 'Signed Waybill',
    EvidenceType.damage          => 'Damage Report',
    EvidenceType.odometerReading => 'Odometer Reading',
    EvidenceType.fuelReceipt     => 'Fuel Receipt',
    EvidenceType.other           => 'Other',
  };
}

// ── Alert/Banner Type ────────────────────────────────────────
enum AlertType { info, success, warning, error }
