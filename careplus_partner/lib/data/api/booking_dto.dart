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
  });

  final String id;
  final String category;
  final String service;
  final String status;
  final String customerName;
  final int totalAmountPaise;
  final String? area;
  final DateTime? createdAt;
  /// Last status-transition time — for a Completed booking, this is when it
  /// was actually finished, which the earnings screen uses to bucket a job
  /// into "today"/"this week" rather than its (possibly much earlier)
  /// creation time.
  final DateTime? updatedAt;
  final double? lat;
  final double? lng;

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
    );
  }

  BookingDto copyWith({String? status}) => BookingDto(
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
