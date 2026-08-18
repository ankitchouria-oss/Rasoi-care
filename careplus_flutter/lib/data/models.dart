// Domain models for Care+.
//
// Money is stored in paise (integer) everywhere and only formatted at the edge
// — floating-point rupees are how you end up owing a customer ₹0.01. See
// [Money] for the formatter.

import 'package:intl/intl.dart';

/// Which of the eight kitchen appliances a service belongs to.
enum Appliance {
  chimney('Kitchen chimney', '◍'),
  hob('Gas hob', '⊙'),
  cooktop('Cooktop', '▤'),
  dishwasher('Dishwasher', '▥'),
  microwave('Built-in microwave', '▣'),
  refrigerator('Refrigerator', '❄'),
  otg('OTG', '▦'),
  purifier('Water purifier', '◈');

  const Appliance(this.label, this.glyph);
  final String label;
  final String glyph;
}

/// A bookable service under an appliance (deep clean, repair visit, install…).
class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.appliance,
    required this.title,
    required this.blurb,
    required this.pricePaise,
    required this.durationMin,
    this.mostBooked = false,
    this.strikePaise,
    this.included = const [],
    this.notIncluded = '',
  });

  final String id;
  final Appliance appliance;
  final String title;
  final String blurb;
  final int pricePaise;
  final int durationMin;
  final bool mostBooked;
  final int? strikePaise;

  /// What's included in *this specific* service — shown as a dropdown on
  /// its card, not a shared appliance-wide list, since a repair visit and a
  /// deep clean genuinely include different things.
  final List<String> included;
  final String notIncluded;
}

/// One symptom a customer can flag before the visit.
class Issue {
  const Issue(this.label, this.hint, {this.selected = false});
  final String label;
  final String hint;
  final bool selected;
  Issue copyWith({bool? selected}) =>
      Issue(label, hint, selected: selected ?? this.selected);
}

/// One customer review on an appliance's service detail screen.
class Review {
  const Review(this.initials, this.name, this.meta, this.quote);
  final String initials;
  final String name;
  final String meta;
  final String quote;
}

/// Everything the service detail screen needs beyond the bookable
/// [ServiceItem]s themselves — rating, what's included, and reviews.
/// [comingSoon] appliances (refrigerator, water purifier as of writing)
/// have no services or issues yet — only [blurb] is shown.
class ApplianceDetail {
  const ApplianceDetail({
    required this.heading,
    required this.blurb,
    this.rating = 0,
    this.ratingCount = 0,
    this.reviews = const [],
    this.comingSoon = false,
  });
  final String heading;
  final String blurb;
  final double rating;
  final int ratingCount;
  final List<Review> reviews;
  final bool comingSoon;
}

class SavedAddress {
  /// [lat]/[lng] are null for the canned demo addresses (label-only, no
  /// real geocoding behind them) and for anything entered through the
  /// manual-entry fallback form when Maps isn't configured. They're set
  /// only when an address is confirmed through the real map picker — see
  /// AddressPickerScreen in lib/features/booking/address_picker_screen.dart.
  const SavedAddress(this.id, this.label, this.line, this.glyph,
      [this.lat, this.lng]);
  final String id;
  final String label;
  final String line;
  final String glyph;
  final double? lat;
  final double? lng;
}

class PaymentMethod {
  const PaymentMethod(this.id, this.name, this.detail, this.glyph);
  final String id;
  final String name;
  final String detail;
  final String glyph;
}

enum BookingStatus { scheduled, onTheWay, inProgress, completed, cancelled }

extension BookingStatusX on BookingStatus {
  String get label => switch (this) {
        BookingStatus.scheduled => 'Scheduled',
        BookingStatus.onTheWay => 'On the way',
        BookingStatus.inProgress => 'In progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };
}

class Technician {
  const Technician({
    required this.id,
    required this.name,
    required this.initials,
    required this.rating,
    required this.jobsDone,
    required this.years,
    required this.vehicle,
  });
  final String id;
  final String name;
  final String initials;
  final double rating;
  final int jobsDone;
  final int years;
  final String vehicle;
}

class Booking {
  const Booking({
    required this.id,
    required this.title,
    required this.appliance,
    required this.status,
    required this.whenLabel,
    required this.addressLabel,
    required this.totalPaise,
    this.technician,
    this.stars,
    this.technicianId,
    this.technicianFirebaseUid,
    this.lat,
    this.lng,
    this.suctionBefore,
    this.suctionAfter,
    this.timeOnSiteMin,
    this.cancellationFeePaise,
    this.rawStatus = '',
  });

  final String id;
  final String title;
  final Appliance appliance;
  final BookingStatus status;
  final String whenLabel;
  final String addressLabel;
  final int totalPaise;
  final Technician? technician;
  final int? stars;

  /// The assigned technician's raw id, straight off the backend's
  /// `technicianId` field — unlike [technician] (a full profile, always
  /// null for API-sourced bookings, see ApiRepository) this is just the id,
  /// enough to look up their live location. See TechnicianLocationService
  /// in lib/data/firebase/technician_location_service.dart.
  final String? technicianId;

  /// The assigned technician's Firebase Auth uid — NOT the same value as
  /// [technicianId] above (that's the backend's own `technicians.id`
  /// primary key). This is the id the Partner app actually keys its live
  /// Firestore location document by (`technician_locations/{firebaseUid}`),
  /// so live tracking must watch this one, not [technicianId]. Null for
  /// mock/demo bookings, or a real booking assigned to a seed technician
  /// that's never bootstrapped through the Partner app.
  final String? technicianFirebaseUid;

  /// The service address's coordinates, when known — set from the
  /// backend's `lat`/`lng` fields on bookings created through the real map
  /// picker. Null for anything booked with a label-only address.
  final double? lat;
  final double? lng;

  /// Real work-log readings, filled in by the technician as they actually
  /// advance the job (see app.py's advance_booking) — null until the
  /// relevant step has happened, which the invoice treats as "not
  /// recorded" rather than showing an invented number. m³/hr for the
  /// suction readings, minutes for time on site.
  final int? suctionBefore;
  final int? suctionAfter;
  final int? timeOnSiteMin;

  /// Set only once this booking is actually cancelled — the real fee
  /// charged for cancelling at that point in the job's progress (credited
  /// to the technician), from app.py's CANCELLATION_FEE_BY_STATUS. Null
  /// for anything not cancelled.
  final int? cancellationFeePaise;

  /// The backend's own status string (`Requested`/`Accepted`/`On the
  /// way`/`In Progress`/`Completed`/`Cancelled`), kept alongside [status]
  /// because that enum collapses Requested and Accepted into the same
  /// `scheduled` value — too coarse to preview a cancellation fee, which
  /// differs between the two. Empty for mock/demo bookings.
  final String rawStatus;
}

/// A timeline entry on the tracking screen.
class TimelineStep {
  const TimelineStep(this.title, this.detail, this.state);
  final String title;
  final String detail;
  final StepState state;
}

enum StepState { done, now, upcoming }

/// Indian-locale currency, from paise. `Money.rupees(89900) == '₹899'`.
abstract final class Money {
  static final _fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String rupees(int paise) => _fmt.format(paise / 100);
}

