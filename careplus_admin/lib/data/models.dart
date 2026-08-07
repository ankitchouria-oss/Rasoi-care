// Domain models for Rasoi Care Admin — the owner/staff-facing operations and
// analytics app.
//
// Money is stored in paise (integer) everywhere and only formatted at the
// edge. See [Money] for the formatter.

import 'package:intl/intl.dart';

/// Indian-locale currency, from paise. `Money.rupees(89900) == '₹899'`.
abstract final class Money {
  static final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static String rupees(int paise) => _fmt.format(paise / 100);

  static final _fmtDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static String rupeesDecimal(int paise) => _fmtDec.format(paise / 100);
}

/// Owner sees financials and staff management; Staff gets operations only.
enum AdminRole { owner, staff }

extension AdminRoleX on AdminRole {
  String get label => this == AdminRole.owner ? 'Owner' : 'Staff member';
}

enum LineTone { neutral, success }

// ============================================================ OVERVIEW
/// A single item on the "needs attention" list — unassigned jobs, complaints,
/// refunds queued.
class AttentionItem {
  const AttentionItem(this.jobId, this.title, this.detail, this.tone);
  final String jobId;
  final String title;
  final String detail;
  final LineTone tone;
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

// ============================================================ BOOKINGS
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

// ============================================================ TEAM
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

enum StaffStatus { active, invited, suspended }

/// A back-office staff account (owner-only "Staff & access" screen) — not a
/// field technician, but someone who signs into this app.
class StaffAccount {
  const StaffAccount({
    required this.name,
    required this.initials,
    required this.phone,
    required this.role,
    required this.status,
    required this.lastActive,
  });
  final String name;
  final String initials;
  final String phone;
  final AdminRole role;
  final StaffStatus status;
  final String lastActive;
}

// ============================================================ STOCK
/// One SKU on the stock tab, with a burn-rate forecast for the reports view.
class AdminStockItem {
  const AdminStockItem({
    required this.name,
    required this.sku,
    required this.inStock,
    required this.reorderAt,
    required this.low,
    required this.burnPerDay,
  });
  final String name;
  final String sku;
  final int inStock;
  final int reorderAt;
  final bool low;
  final double burnPerDay;
  double get fillFraction => (inStock / reorderAt).clamp(0, 1);
  int get daysLeft => burnPerDay <= 0 ? 999 : (inStock / burnPerDay).floor();
}

// ============================================================ REPORTS
enum ReportRange { week, month, quarter }

extension ReportRangeX on ReportRange {
  String get label => switch (this) {
        ReportRange.week => 'This week',
        ReportRange.month => 'This month',
        ReportRange.quarter => 'This quarter',
      };
}

/// One point on a revenue/rating trend line.
class TrendPoint {
  const TrendPoint(this.label, this.value);
  final String label;
  final double value; // pre-normalized 0..1 for the chart
}

/// Revenue and job count for one appliance category, for the mix breakdown.
class CategoryRevenue {
  const CategoryRevenue(this.label, this.glyph, this.revenuePaise, this.jobs);
  final String label;
  final String glyph;
  final int revenuePaise;
  final int jobs;
}

/// One row of the technician leaderboard report.
class TechnicianRow {
  const TechnicianRow({
    required this.name,
    required this.initials,
    required this.jobs,
    required this.revenuePaise,
    required this.rating,
    required this.firstTimeFixPct,
  });
  final String name;
  final String initials;
  final int jobs;
  final int revenuePaise;
  final double rating;
  final int firstTimeFixPct;
}

/// One customer segment slice (new / repeat / loyal / lapsed).
class CustomerSegment {
  const CustomerSegment(this.label, this.count, this.pct);
  final String label;
  final int count;
  final double pct;
}

/// One complaint reason slice, for the SLA & complaints report.
class ComplaintReason {
  const ComplaintReason(this.label, this.count, this.avgResolutionHrs);
  final String label;
  final int count;
  final double avgResolutionHrs;
}

/// One payment method's share of collections.
class PaymentMixItem {
  const PaymentMixItem(this.method, this.amountPaise, this.pct);
  final String method;
  final int amountPaise;
  final double pct;
}

/// One coupon/discount code's usage for the period.
class CouponUsage {
  const CouponUsage(this.code, this.redemptions, this.discountGivenPaise);
  final String code;
  final int redemptions;
  final int discountGivenPaise;
}

/// Owner-only P&L summary for the selected report range.
class FinancialSummary {
  const FinancialSummary({
    required this.grossRevenuePaise,
    required this.technicianPayoutsPaise,
    required this.partsCostPaise,
    required this.taxCollectedPaise,
    required this.refundsPaise,
    required this.discountsGivenPaise,
  });
  final int grossRevenuePaise;
  final int technicianPayoutsPaise;
  final int partsCostPaise;
  final int taxCollectedPaise;
  final int refundsPaise;
  final int discountsGivenPaise;

  int get netMarginPaise =>
      grossRevenuePaise - technicianPayoutsPaise - partsCostPaise - refundsPaise - discountsGivenPaise;
  double get netMarginPct =>
      grossRevenuePaise == 0 ? 0 : (netMarginPaise / grossRevenuePaise) * 100;
}

/// Everything the Reports tab needs for one [ReportRange].
class ReportBundle {
  const ReportBundle({
    required this.range,
    required this.revenueTrend,
    required this.ratingTrend,
    required this.categoryRevenue,
    required this.technicianLeaderboard,
    required this.customerSegments,
    required this.complaintReasons,
    required this.paymentMix,
    required this.coupons,
    required this.financials,
  });
  final ReportRange range;
  final List<TrendPoint> revenueTrend;
  final List<TrendPoint> ratingTrend;
  final List<CategoryRevenue> categoryRevenue;
  final List<TechnicianRow> technicianLeaderboard;
  final List<CustomerSegment> customerSegments;
  final List<ComplaintReason> complaintReasons;
  final List<PaymentMixItem> paymentMix;
  final List<CouponUsage> coupons;
  final FinancialSummary financials;
}
