class Trip {
  Trip({
    required this.id,
    required this.referenceCode,
    required this.status,
    this.tripDate,
    this.pickupLocation,
    this.dropoffLocation,
    this.destination,
    this.deliveryAddress,
    this.materialDescription,
    this.pickupNotes,
    this.dropoffNotes,
    this.waybillNumber,
    this.clientName,
    this.tonnageLoad,
    this.estimatedDepartureTime,
    this.estimatedArrivalTime,
    this.customerContactName,
    this.customerContactPhone,
    this.specialInstructions,
    this.driverName,
    this.driverContact,
    this.vehicleRef,
    this.trailerRef,
    this.truckRegNo,
    this.truckTypeCapacity,
    this.odometerStartKm,
    this.odometerEndKm,
    this.roadExpenseDisbursed,
    this.roadExpenseReference,
    this.arrivalTimeAtSite,
    this.podType,
    this.waybillReturned,
    this.notesIncidents,
    this.fuelStationUsed,
    this.fuelPaymentMode,
    this.fuelLitresFilled,
    this.fuelReceiptNo,
    this.returnTime,
    this.vehicleConditionPostTrip,
    this.postTripInspectorName,
    this.distanceKm,
    this.startOdometerPhotoAttached = false,
    this.endOdometerPhotoAttached = false,
    this.startOdometerPhotoUrl,
    this.endOdometerPhotoUrl,
    this.clientRepSignatureUrl,
    this.proofOfFuellingUrl,
    this.inspectorSignatureUrl,
    this.securitySignatureUrl,
    this.driverSignatureUrl,
    this.hasAfterLoadingEvidence = false,
    this.destinationLat,
    this.destinationLng,
    this.latestLocationLat,
    this.latestLocationLng,
    this.latestLocationSpeedKph,
  });

  final int id;
  final String referenceCode;
  final String status;
  final DateTime? tripDate;
  final String? pickupLocation;
  final String? dropoffLocation;
  final String? destination;
  final String? deliveryAddress;
  final String? materialDescription;
  final String? pickupNotes;
  final String? dropoffNotes;
  final String? waybillNumber;
  final String? clientName;
  final String? tonnageLoad;
  final DateTime? estimatedDepartureTime;
  final DateTime? estimatedArrivalTime;
  final String? customerContactName;
  final String? customerContactPhone;
  final String? specialInstructions;
  final String? driverName;
  final String? driverContact;
  final String? vehicleRef;
  final String? trailerRef;
  final String? truckRegNo;
  final String? truckTypeCapacity;
  final double? odometerStartKm;
  final double? odometerEndKm;
  final String? roadExpenseDisbursed;
  final String? roadExpenseReference;
  final DateTime? arrivalTimeAtSite;
  final String? podType;
  final bool? waybillReturned;
  final String? notesIncidents;
  final String? fuelStationUsed;
  final String? fuelPaymentMode;
  final String? fuelLitresFilled;
  final String? fuelReceiptNo;
  final DateTime? returnTime;
  final String? vehicleConditionPostTrip;
  final String? postTripInspectorName;
  final double? distanceKm;
  final bool startOdometerPhotoAttached;
  final bool endOdometerPhotoAttached;
  final String? startOdometerPhotoUrl;
  final String? endOdometerPhotoUrl;
  final String? clientRepSignatureUrl;
  final String? proofOfFuellingUrl;
  final String? inspectorSignatureUrl;
  final String? securitySignatureUrl;
  final String? driverSignatureUrl;
  final bool hasAfterLoadingEvidence;
  final double? destinationLat;
  final double? destinationLng;
  final double? latestLocationLat;
  final double? latestLocationLng;
  final double? latestLocationSpeedKph;

  bool get hasOdometerStart => odometerStartKm != null;
  bool get hasOdometerEnd => odometerEndKm != null;

  factory Trip.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final truck = (json['vehicle'] ?? json['truck']) as Map<String, dynamic>?;
    final trailer = json['trailer'] as Map<String, dynamic>?;

    double? toDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    DateTime? toDate(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    int toInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    bool? toBool(dynamic value) {
      if (value == null) return null;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') return true;
        if (v == 'false' || v == '0' || v == 'no') return false;
      }
      return null;
    }

    return Trip(
      id: toInt(json['id']),
      referenceCode: json['reference_code']?.toString() ?? 'TRIP-${json['id']}',
      status: (json['status'] ?? '').toString(),
      tripDate: toDate(json['trip_date']),
      pickupLocation: json['pickup_location']?.toString(),
      dropoffLocation: json['dropoff_location']?.toString(),
      destination: json['destination']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      pickupNotes: json['pickup_notes']?.toString(),
      dropoffNotes: json['dropoff_notes']?.toString(),
      materialDescription: json['material_description']?.toString(),
      waybillNumber: json['waybill_number']?.toString(),
      clientName: json['client_name']?.toString(),
      tonnageLoad: json['tonnage_load']?.toString(),
      estimatedDepartureTime: toDate(json['estimated_departure_time']),
      estimatedArrivalTime: toDate(json['estimated_arrival_time']),
      customerContactName: json['customer_contact_name']?.toString(),
      customerContactPhone: json['customer_contact_phone']?.toString(),
      specialInstructions: json['special_instructions']?.toString(),
      driverName: driver?['name']?.toString(),
      driverContact:
          json['driver_contact']?.toString() ??
          driver?['phone_number']?.toString(),
      vehicleRef:
          truck?['name']?.toString() ?? truck?['license_plate']?.toString(),
      trailerRef:
          trailer?['name']?.toString() ?? trailer?['license_plate']?.toString(),
      truckRegNo:
          json['truck_reg_no']?.toString() ??
          truck?['license_plate']?.toString(),
      truckTypeCapacity: truck?['truck_type_capacity']?.toString(),
      odometerStartKm: toDouble(json['start_odometer_km']),
      odometerEndKm: toDouble(json['end_odometer_km']),
      roadExpenseDisbursed: json['road_expense_disbursed']?.toString(),
      roadExpenseReference: json['road_expense_reference']?.toString(),
      arrivalTimeAtSite: toDate(json['arrival_time_at_site']),
      podType: json['pod_type']?.toString(),
      waybillReturned: toBool(json['waybill_returned']),
      notesIncidents: json['notes_incidents']?.toString(),
      fuelStationUsed: json['fuel_station_used']?.toString(),
      fuelPaymentMode: json['fuel_payment_mode']?.toString(),
      fuelLitresFilled: json['fuel_litres_filled']?.toString(),
      fuelReceiptNo: json['fuel_receipt_no']?.toString(),
      returnTime: toDate(json['return_time']),
      vehicleConditionPostTrip: json['vehicle_condition_post_trip']?.toString(),
      postTripInspectorName: json['post_trip_inspector_name']?.toString(),
      distanceKm: toDouble(json['distance_km']),
      startOdometerPhotoAttached: json['start_odometer_photo_attached'] == true,
      endOdometerPhotoAttached: json['end_odometer_photo_attached'] == true,
      startOdometerPhotoUrl: json['start_odometer_photo_url']?.toString(),
      endOdometerPhotoUrl: json['end_odometer_photo_url']?.toString(),
      clientRepSignatureUrl: json['client_rep_signature_url']?.toString(),
      proofOfFuellingUrl: json['proof_of_fuelling_url']?.toString(),
      inspectorSignatureUrl: json['inspector_signature_url']?.toString(),
      securitySignatureUrl: json['security_signature_url']?.toString(),
      driverSignatureUrl: json['driver_signature_url']?.toString(),
      hasAfterLoadingEvidence:
          (json['has_after_loading_evidence'] ?? false) == true,
      destinationLat:
          toDouble(json['destination_lat']) ??
          toDouble(json['delivery_lat']) ??
          toDouble(json['dropoff_lat']),
      destinationLng:
          toDouble(json['destination_lng']) ??
          toDouble(json['delivery_lng']) ??
          toDouble(json['dropoff_lng']),
      latestLocationLat: toDouble(
        (json['latest_location'] as Map<String, dynamic>?)?['lat'],
      ),
      latestLocationLng: toDouble(
        (json['latest_location'] as Map<String, dynamic>?)?['lng'],
      ),
      latestLocationSpeedKph: (() {
        final speedMps = toDouble(
          (json['latest_location'] as Map<String, dynamic>?)?['speed'],
        );
        if (speedMps == null) return null;
        return speedMps * 3.6;
      })(),
    );
  }
}
