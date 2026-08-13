// Wire shape for a booking as returned by the real backend
// (GET /api/technician/bookings, PATCH /api/bookings/<id>/advance — see
// app.py's `booking_row_to_dict`). Only the fields this app actually uses
// are parsed; everything else in the JSON is ignored.
class BookingDto {
  const BookingDto({
    required this.id,
    required this.service,
    required this.status,
    required this.customerName,
    required this.totalAmountPaise,
    required this.area,
    required this.createdAt,
  });

  final String id;
  final String service;
  final String status;
  final String customerName;
  final int totalAmountPaise;
  final String? area;
  final DateTime? createdAt;

  factory BookingDto.fromJson(Map<String, dynamic> json) {
    // total_amount arrives in rupees (see app.py) — this app stores money in
    // paise everywhere, so convert at the edge.
    final totalAmount = json['total_amount'] ?? json['price'] ?? 0;
    final rupees = (totalAmount is num) ? totalAmount : num.tryParse('$totalAmount') ?? 0;
    return BookingDto(
      id: '${json['id']}',
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
    );
  }

  BookingDto copyWith({String? status}) => BookingDto(
        id: id,
        service: service,
        status: status ?? this.status,
        customerName: customerName,
        totalAmountPaise: totalAmountPaise,
        area: area,
        createdAt: createdAt,
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
