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
  });

  final String id;
  final Appliance appliance;
  final String title;
  final String blurb;
  final int pricePaise;
  final int durationMin;
  final bool mostBooked;
  final int? strikePaise;
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

class SavedAddress {
  const SavedAddress(this.id, this.label, this.line, this.glyph);
  final String id;
  final String label;
  final String line;
  final String glyph;
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

// ============================================================ TECHNICIAN APP
/// Today's dashboard numbers on the technician's job-feed screen.
class TechStats {
  const TechStats({
    required this.earningsTodayPaise,
    required this.jobsDone,
    required this.jobsTotal,
    required this.tipsPaise,
    required this.rating,
    required this.firstTimeFixPct,
    required this.onDuty,
  });
  final int earningsTodayPaise;
  final int jobsDone;
  final int jobsTotal;
  final int tipsPaise;
  final double rating;
  final int firstTimeFixPct;
  final bool onDuty;
  double get progress => jobsTotal == 0 ? 0 : jobsDone / jobsTotal;
}

/// An incoming job offer the technician can accept or pass within a countdown.
class JobRequest {
  const JobRequest({
    required this.jobId,
    required this.serviceTitle,
    required this.distanceKm,
    required this.timeWindow,
    required this.payoutPaise,
    required this.note,
  });
  final String jobId;
  final String serviceTitle;
  final double distanceKm;
  final String timeWindow;
  final int payoutPaise;
  final String note;
}

enum StopStatus { inProgress, next }

/// A stop on the technician's route for today.
class RouteStop {
  const RouteStop({
    required this.jobId,
    required this.time,
    required this.title,
    required this.customerName,
    required this.meta,
    required this.status,
  });
  final String jobId;
  final String time;
  final String title;
  final String customerName;
  final String meta;
  final StopStatus status;
}

/// One line on the technician's in-job checklist.
class ChecklistItem {
  const ChecklistItem(this.label, {this.checked = false});
  final String label;
  final bool checked;
  ChecklistItem copyWith({bool? checked}) =>
      ChecklistItem(label, checked: checked ?? this.checked);
}

/// A part fitted during the visit, pending or already customer-approved.
class PartLine {
  const PartLine({
    required this.name,
    required this.sku,
    required this.qty,
    required this.pricePaise,
    required this.approved,
    this.approvedAt,
  });
  final String name;
  final String sku;
  final int qty;
  final int pricePaise;
  final bool approved;
  final String? approvedAt;
}

/// Full detail for a job the technician is actively working.
class JobDetail {
  const JobDetail({
    required this.jobId,
    required this.customerName,
    required this.customerInitials,
    required this.addressLine,
    required this.directions,
    required this.reportedTags,
    required this.reportedQuote,
    required this.checklist,
    required this.parts,
  });
  final String jobId;
  final String customerName;
  final String customerInitials;
  final String addressLine;
  final String directions;
  final List<String> reportedTags;
  final String reportedQuote;
  final List<ChecklistItem> checklist;
  final List<PartLine> parts;
}

enum LineTone { neutral, success }

/// One invoice line for the technician's close-job screen.
class InvoiceLine {
  const InvoiceLine(this.label, this.amountPaise, {this.tone = LineTone.neutral});
  final String label;
  final int amountPaise;
  final LineTone tone;
}

// ============================================================ ADMIN CONSOLE
/// A single item on the "needs attention" list — unassigned jobs, complaints,
/// refunds queued.
class AttentionItem {
  const AttentionItem(this.jobId, this.title, this.detail, this.tone);
  final String jobId;
  final String title;
  final String detail;
  final LineTone tone; // reused: success reads as "ok", neutral as "warn" here
}

/// Cluster-wide KPIs for the overview tab.
class AdminOverview {
  const AdminOverview({
    required this.revenuePaise,
    required this.revenueDeltaPct,
    required this.jobsClosed,
    required this.jobsClosedDeltaPct,
    required this.slaBreaches,
    required this.slaBreachesToday,
    required this.avgRating,
    required this.ratingCount,
    required this.weekBars,
    required this.weekLabels,
    required this.technicianUtilisationPct,
    required this.firstTimeFixPct,
    required this.attention,
  });
  final int revenuePaise;
  final double revenueDeltaPct;
  final int jobsClosed;
  final double jobsClosedDeltaPct;
  final int slaBreaches;
  final int slaBreachesToday;
  final double avgRating;
  final int ratingCount;
  final List<int> weekBars; // 0..100, one per day
  final List<String> weekLabels;
  final int technicianUtilisationPct;
  final int firstTimeFixPct;
  final List<AttentionItem> attention;
}

enum BookingCategory { unassigned, inProgress, scheduled, closed }

/// One row in the admin bookings queue.
class AdminBooking {
  const AdminBooking({
    required this.jobId,
    required this.title,
    required this.meta,
    required this.statusLabel,
    required this.category,
  });
  final String jobId;
  final String title;
  final String meta;
  final String statusLabel;
  final BookingCategory category;
}

enum DutyStatus { onJob, idle, offDuty }

/// One technician on the roster tab.
class AdminTeamMember {
  const AdminTeamMember({
    required this.name,
    required this.initials,
    required this.specialties,
    required this.statsLabel,
    required this.rating,
    required this.duty,
  });
  final String name;
  final String initials;
  final String specialties;
  final String statsLabel;
  final double rating;
  final DutyStatus duty;
}

/// One SKU on the stock tab.
class AdminStockItem {
  const AdminStockItem({
    required this.name,
    required this.sku,
    required this.inStock,
    required this.reorderAt,
    required this.low,
  });
  final String name;
  final String sku;
  final int inStock;
  final int reorderAt;
  final bool low;
  double get fillFraction => (inStock / reorderAt).clamp(0, 1);
}
