class TripStop {
  TripStop({
    required this.id,
    this.destination,
    this.deliveryAddress,
    this.tonnageLoad,
    this.waybillNumber,
    this.customerContactName,
    this.customerContactPhone,
    this.arrivalTimeAtSite,
    this.podType,
    this.waybillReturned,
    this.notesIncidents,
  });

  final int id;
  final String? destination;
  final String? deliveryAddress;
  final String? tonnageLoad;
  final String? waybillNumber;
  final String? customerContactName;
  final String? customerContactPhone;
  final DateTime? arrivalTimeAtSite;
  final String? podType;
  final bool? waybillReturned;
  final String? notesIncidents;

  factory TripStop.fromJson(Map<String, dynamic> json) {
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

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return TripStop(
      id: toInt(json['id']),
      destination: json['destination']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      tonnageLoad: json['tonnage_load']?.toString(),
      waybillNumber: json['waybill_number']?.toString(),
      customerContactName: json['customer_contact_name']?.toString(),
      customerContactPhone: json['customer_contact_phone']?.toString(),
      arrivalTimeAtSite: parseDate(json['arrival_time_at_site']),
      podType: json['pod_type']?.toString(),
      waybillReturned: toBool(json['waybill_returned']),
      notesIncidents: json['notes_incidents']?.toString(),
    );
  }
}
