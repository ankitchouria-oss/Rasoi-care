// Domain models for Rasoi Care Partner — the technician-facing app.
//
// Money is stored in paise (integer) everywhere and only formatted at the edge
// — floating-point rupees are how you end up owing someone ₹0.01. See [Money]
// for the formatter.

import 'package:intl/intl.dart';

/// Indian-locale currency, from paise. `Money.rupees(89900) == '₹899'`.
abstract final class Money {
  static final _fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String rupees(int paise) => _fmt.format(paise / 100);
}

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
