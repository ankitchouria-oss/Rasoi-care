// Wire shape for GET /api/technician/earnings — see app.py's
// technician_earnings_payload. This is the one place the Partner app
// learns a technician's real, commission-based pay; everywhere else (job
// cards, invoices) shows the customer's full invoice total, which is
// never what the technician is actually paid — see EarningsJob.

/// One completed booking's real commission, computed backend-side from
/// its own invoice total and the technician's employment_type — never the
/// full invoice amount itself (see [totalAmountPaise], kept only for
/// context/comparison, not as "what was earned").
class EarningsJob {
  const EarningsJob({
    required this.bookingId,
    required this.service,
    required this.totalAmountPaise,
    required this.commissionPaise,
    this.completedAt,
  });

  final String bookingId;
  final String service;
  final int totalAmountPaise;
  final int commissionPaise;
  final DateTime? completedAt;

  factory EarningsJob.fromJson(Map<String, dynamic> json) => EarningsJob(
        bookingId: '${json['bookingId']}',
        service: (json['service'] as String?)?.trim().isNotEmpty == true
            ? json['service'] as String
            : 'Service',
        totalAmountPaise: (json['totalAmountPaise'] as num?)?.round() ?? 0,
        commissionPaise: (json['commissionPaise'] as num?)?.round() ?? 0,
        completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      );
}

/// One real, auto-computed addition to a technician's pay — a milestone
/// incentive (positive) or a late-arrival fine (negative), see
/// advance_booking in app.py. Never a manual admin entry.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.reason,
    this.bookingId,
    this.createdAt,
  });

  final String id;

  /// 'incentive' or 'fine'.
  final String kind;
  final int amountPaise;
  final String reason;
  final String? bookingId;
  final DateTime? createdAt;

  bool get isIncentive => kind == 'incentive';

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: '${json['id']}',
        kind: (json['kind'] as String?) ?? 'incentive',
        amountPaise: (json['amountPaise'] as num?)?.round() ?? 0,
        reason: (json['reason'] as String?) ?? '',
        bookingId: json['bookingId'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      );
}

/// A technician's whole real earnings picture: per-job commission, the
/// running commission total, and the full bonus/incentive + fine ledger —
/// everything this screen needs, in one fetch.
class TechEarningsSummary {
  const TechEarningsSummary({
    required this.employmentType,
    required this.commissionRate,
    required this.visitChargePaise,
    required this.jobs,
    required this.commissionTotalPaise,
    required this.ledger,
    required this.incentiveTotalPaise,
    required this.fineTotalPaise,
    required this.netTotalPaise,
  });

  /// 'payroll' or 'outsourced' — see the technician's own apply-screen
  /// choice, self-declared once at KYC and never editable afterward.
  final String employmentType;
  final double commissionRate;

  /// The flat visit fee excluded from both employment types' commission
  /// base — neither gets a cut of a fee that isn't for their own labour.
  final int visitChargePaise;
  final List<EarningsJob> jobs;
  final int commissionTotalPaise;
  final List<LedgerEntry> ledger;
  final int incentiveTotalPaise;
  final int fineTotalPaise;

  /// commissionTotalPaise + incentiveTotalPaise + fineTotalPaise (the fine
  /// total already carries a negative sign) — the real total this
  /// technician has actually earned.
  final int netTotalPaise;

  bool get isPayroll => employmentType == 'payroll';
  List<LedgerEntry> get incentives => ledger.where((e) => e.isIncentive).toList(growable: false);
  List<LedgerEntry> get fines => ledger.where((e) => !e.isIncentive).toList(growable: false);

  factory TechEarningsSummary.fromJson(Map<String, dynamic> json) => TechEarningsSummary(
        employmentType: (json['employmentType'] as String?) ?? 'outsourced',
        commissionRate: (json['commissionRate'] as num?)?.toDouble() ?? 0,
        visitChargePaise: (json['visitChargePaise'] as num?)?.round() ?? 0,
        jobs: (json['jobs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(EarningsJob.fromJson)
                .toList(growable: false) ??
            const [],
        commissionTotalPaise: (json['commissionTotalPaise'] as num?)?.round() ?? 0,
        ledger: (json['ledger'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(LedgerEntry.fromJson)
                .toList(growable: false) ??
            const [],
        incentiveTotalPaise: (json['incentiveTotalPaise'] as num?)?.round() ?? 0,
        fineTotalPaise: (json['fineTotalPaise'] as num?)?.round() ?? 0,
        netTotalPaise: (json['netTotalPaise'] as num?)?.round() ?? 0,
      );
}
