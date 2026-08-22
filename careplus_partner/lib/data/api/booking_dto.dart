// Wire shape for a booking as returned by the real backend
// (GET /api/technician/bookings, PATCH /api/bookings/<id>/advance — see
// app.py's `booking_row_to_dict`). Only the fields this app actually uses
// are parsed; everything else in the JSON is ignored.
class BookingDto {
  const BookingDto({
    required this.id,
    required this.category,
    required this.service,
    required this.status,
    required this.customerName,
    required this.totalAmountPaise,
    required this.area,
    required this.createdAt,
    this.updatedAt,
    this.lat,
    this.lng,
    this.cancellationFeePaise,
    this.directions,
    this.notes,
    this.issues = const [],
    this.customerPhone,
    this.paymentMethod,
  });

  final String id;
  final String category;
  final String service;
  final String status;
  final String customerName;
  final int totalAmountPaise;
  final String? area;
  final DateTime? createdAt;
  /// Free text the customer actually typed on the address step of their
  /// booking — null when they left it blank, never a fabricated fallback.
  final String? directions;
  /// Last status-transition time — for a Completed booking, this is when it
  /// was actually finished, which the earnings screen uses to bucket a job
  /// into "today"/"this week" rather than its (possibly much earlier)
  /// creation time.
  final DateTime? updatedAt;
  final double? lat;
  final double? lng;

  /// Set only when this booking was cancelled by the customer — the real
  /// fee credited to this technician for time already committed, from
  /// app.py's CANCELLATION_FEE_BY_STATUS. 0 if the customer cancelled
  /// before any technician engagement, null if not cancelled at all.
  final int? cancellationFeePaise;

  /// Free text the customer typed on the Issue screen ("Anything else?") —
  /// null when they left it blank. See JobDetail.reportedQuote.
  final String? notes;

  /// Which symptom checkboxes the customer actually ticked on the Issue
  /// screen — empty when they reported nothing, never a fabricated
  /// symptom list. See JobDetail.reportedTags.
  final List<String> issues;

  /// The customer's own Firebase-verified phone number, when known — lets
  /// the job screen's "Call" action dial a real number instead of a fake
  /// "Calling — masked" toast. Null for bookings made before the backend
  /// captured this, or a customer who never verified a phone.
  final String? customerPhone;

  /// How the customer actually paid, once the technician records it on the
  /// close-job screen — null until then. One of upi/card/cash/link.
  final String? paymentMethod;

  factory BookingDto.fromJson(Map<String, dynamic> json) {
    // total_amount arrives in rupees (see app.py) — this app stores money in
    // paise everywhere, so convert at the edge.
    final totalAmount = json['total_amount'] ?? json['price'] ?? 0;
    final rupees = (totalAmount is num) ? totalAmount : num.tryParse('$totalAmount') ?? 0;
    return BookingDto(
      id: '${json['id']}',
      category: (json['category'] as String?) ?? '',
      service: (json['service'] as String?)?.trim().isNotEmpty == true
          ? json['service'] as String
          : 'Service visit',
      status: (json['status'] as String?) ?? 'Requested',
      customerName: (json['customerName'] as String?)?.trim().isNotEmpty == true
          ? json['customerName'] as String
          : 'Customer',
      totalAmountPaise: (rupees * 100).round(),
      area: json['area'] as String?,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      cancellationFeePaise: (json['cancellationFee'] as num?) == null
          ? null
          : (json['cancellationFee'] as num).round() * 100,
      directions: (json['directions'] as String?)?.trim().isNotEmpty == true
          ? json['directions'] as String
          : null,
      notes: (json['notes'] as String?)?.trim().isNotEmpty == true
          ? json['notes'] as String
          : null,
      issues: (json['issues'] as List?)?.whereType<String>().toList(growable: false) ??
          const [],
      customerPhone: (json['customerPhone'] as String?)?.trim().isNotEmpty == true
          ? json['customerPhone'] as String
          : null,
      paymentMethod: json['paymentMethod'] as String?,
    );
  }

  BookingDto copyWith({String? status, String? paymentMethod}) => BookingDto(
        id: id,
        category: category,
        service: service,
        status: status ?? this.status,
        customerName: customerName,
        totalAmountPaise: totalAmountPaise,
        area: area,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lat: lat,
        lng: lng,
        cancellationFeePaise: cancellationFeePaise,
        directions: directions,
        notes: notes,
        issues: issues,
        customerPhone: customerPhone,
        paymentMethod: paymentMethod ?? this.paymentMethod,
      );
}

/// Fixed status progression the backend enforces — mirrors `STATUS_ORDER` in
/// app.py. `/advance` always moves a booking exactly one step forward.
const List<String> kBookingStatusOrder = [
  'Requested',
  'Accepted',
  'On the way',
  'In Progress',
  'Completed',
];
