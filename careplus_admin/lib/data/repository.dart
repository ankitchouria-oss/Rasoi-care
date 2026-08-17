// The repository interface is the seam between the app and its backend.
//
// Every screen depends on [AdminRepository], never on a data source directly.
// [MockAdminRepository] serves canned data so the app runs with no backend.
// To go live, write a real repository implementing the same interface and
// swap the provider in lib/state/providers.dart — no screen changes.

import 'models.dart';

abstract interface class AdminRepository {
  AdminOverview overview();
  List<AdminBooking> bookings();
  List<AdminTeamMember> team();
  List<AdminStockItem> stock();
  List<StaffAccount> staffAccounts();
  ReportBundle report(ReportRange range);

  /// Approves a self-signed-up technician's application (see
  /// careplus_partner's TechApplyScreen) — flips them verified/online so
  /// they start appearing in auto-routing and their own job feed. No-op on
  /// [MockAdminRepository] (nothing real to verify against).
  Future<bool> verifyTechnician(String technicianId);
}

class MockAdminRepository implements AdminRepository {
  @override
  AdminOverview overview() => const AdminOverview(
        revenuePaise: 48200000,
        revenueDeltaPct: 12.4,
        jobsClosed: 318,
        jobsClosedDeltaPct: 6.1,
        slaBreaches: 7,
        slaBreachesToday: 3,
        avgRating: 4.86,
        ratingCount: 1204,
        weekBars: [62, 78, 54, 88, 96, 71, 84],
        weekLabels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        technicianUtilisationPct: 87,
        firstTimeFixPct: 91,
        attention: [
          AttentionItem('CP-2502', 'Unassigned · 22 min',
              'Refrigerator not cooling · Indira Nagar · slot 2:00 pm', LineTone.neutral),
          AttentionItem('CP-2377', 'Complaint · rework',
              'Hob igniter failed again in 6 days · warranty claim', LineTone.neutral),
          AttentionItem('CP-2418', 'Refund pending · ₹1,299',
              'Cancelled after dispatch · 3 days old', LineTone.neutral),
        ],
      );

  @override
  List<AdminBooking> bookings() => const [
        AdminBooking(
          jobId: 'CP-2502',
          title: 'Refrigerator not cooling',
          meta: 'Indira Nagar · 2:00 pm',
          statusLabel: 'Unassigned',
          category: BookingCategory.unassigned,
        ),
        AdminBooking(
          jobId: 'CP-2481',
          title: 'Chimney deep clean',
          meta: 'Gangapur Rd · Sandeep P.',
          statusLabel: 'In progress',
          category: BookingCategory.inProgress,
        ),
        AdminBooking(
          jobId: 'CP-2496',
          title: 'RO filter change',
          meta: 'College Rd · Nilesh K.',
          statusLabel: 'Scheduled',
          category: BookingCategory.scheduled,
        ),
        AdminBooking(
          jobId: 'CP-2477',
          title: 'Dishwasher install',
          meta: 'Ashok Nagar · Imran S.',
          statusLabel: 'Closed ₹3,240',
          category: BookingCategory.closed,
        ),
        AdminBooking(
          jobId: 'CP-2468',
          title: 'Hob igniter',
          meta: 'Panchavati · Sandeep P.',
          statusLabel: 'Closed ₹1,180',
          category: BookingCategory.closed,
        ),
      ];

  @override
  List<AdminTeamMember> team() => const [
        AdminTeamMember(
          name: 'Sandeep Pawar',
          initials: 'SP',
          specialties: 'Chimney, hob',
          statsLabel: '6 jobs · ₹3,180',
          rating: 4.94,
          duty: DutyStatus.onJob,
        ),
        AdminTeamMember(
          name: 'Nilesh Kadam',
          initials: 'NK',
          specialties: 'Purifier, OTG',
          statsLabel: '5 jobs · ₹2,410',
          rating: 4.88,
          duty: DutyStatus.idle,
        ),
        AdminTeamMember(
          name: 'Imran Shaikh',
          initials: 'IS',
          specialties: 'Dishwasher, fridge',
          statsLabel: '7 jobs · ₹4,020',
          rating: 4.91,
          duty: DutyStatus.onJob,
        ),
        AdminTeamMember(
          name: 'Ravi Bhoir',
          initials: 'RB',
          specialties: 'Microwave, cooktop',
          statsLabel: '4 jobs · ₹1,960',
          rating: 4.72,
          duty: DutyStatus.offDuty,
        ),
      ];

  @override
  Future<bool> verifyTechnician(String technicianId) async => false;

  @override
  List<AdminStockItem> stock() => const [
        AdminStockItem(
            name: 'Elica baffle filter 90cm',
            sku: 'ELF-90B',
            inStock: 8,
            reorderAt: 40,
            low: true,
            burnPerDay: 1.8),
        AdminStockItem(
            name: 'RO membrane 80 GPD',
            sku: 'ROM-80',
            inStock: 14,
            reorderAt: 40,
            low: true,
            burnPerDay: 2.1),
        AdminStockItem(
            name: 'Hob igniter — universal',
            sku: 'HBI-U',
            inStock: 9,
            reorderAt: 30,
            low: true,
            burnPerDay: 1.2),
        AdminStockItem(
            name: 'Dishwasher drain pump',
            sku: 'DWP-BSH',
            inStock: 26,
            reorderAt: 30,
            low: false,
            burnPerDay: 0.6),
        AdminStockItem(
            name: 'Fridge gas R600a (can)',
            sku: 'GAS-600',
            inStock: 48,
            reorderAt: 30,
            low: false,
            burnPerDay: 0.9),
      ];

  @override
  List<StaffAccount> staffAccounts() => const [
        StaffAccount(
          name: 'Ankit Chouria',
          initials: 'AC',
          phone: '98220 41537',
          role: AdminRole.owner,
          status: StaffStatus.active,
          lastActive: 'Active now',
        ),
        StaffAccount(
          name: 'Priya Nair',
          initials: 'PN',
          phone: '98230 55210',
          role: AdminRole.staff,
          status: StaffStatus.active,
          lastActive: '12 min ago',
        ),
        StaffAccount(
          name: 'Rahul Deshmukh',
          initials: 'RD',
          phone: '98221 09983',
          role: AdminRole.staff,
          status: StaffStatus.active,
          lastActive: 'Yesterday',
        ),
        StaffAccount(
          name: 'Sunita Joshi',
          initials: 'SJ',
          phone: '98225 77341',
          role: AdminRole.staff,
          status: StaffStatus.invited,
          lastActive: 'Invite sent 2 days ago',
        ),
        StaffAccount(
          name: 'Vikram Salvi',
          initials: 'VS',
          phone: '98226 44120',
          role: AdminRole.staff,
          status: StaffStatus.suspended,
          lastActive: 'Suspended · 14 days ago',
        ),
      ];

  @override
  ReportBundle report(ReportRange range) {
    final scale = switch (range) {
      ReportRange.week => 1.0,
      ReportRange.month => 4.3,
      ReportRange.quarter => 13.0,
    };
    int money(int base) => (base * scale).round();

    return ReportBundle(
      range: range,
      revenueTrend: _trendFor(range, base: 62),
      ratingTrend: _ratingTrendFor(range),
      categoryRevenue: [
        CategoryRevenue('Kitchen chimney', '◍', money(1420000), (28 * scale).round()),
        CategoryRevenue('Water purifier', '◈', money(860000), (34 * scale).round()),
        CategoryRevenue('Gas hob', '⊙', money(640000), (19 * scale).round()),
        CategoryRevenue('Refrigerator', '❄', money(590000), (11 * scale).round()),
        CategoryRevenue('Dishwasher', '▥', money(410000), (7 * scale).round()),
        CategoryRevenue('Built-in microwave', '▣', money(260000), (6 * scale).round()),
      ],
      technicianLeaderboard: [
        TechnicianRow(
            name: 'Sandeep Pawar',
            initials: 'SP',
            jobs: (32 * scale).round(),
            revenuePaise: money(342000),
            rating: 4.94,
            firstTimeFixPct: 93),
        TechnicianRow(
            name: 'Imran Shaikh',
            initials: 'IS',
            jobs: (29 * scale).round(),
            revenuePaise: money(318000),
            rating: 4.91,
            firstTimeFixPct: 89),
        TechnicianRow(
            name: 'Nilesh Kadam',
            initials: 'NK',
            jobs: (24 * scale).round(),
            revenuePaise: money(256000),
            rating: 4.88,
            firstTimeFixPct: 90),
        TechnicianRow(
            name: 'Ravi Bhoir',
            initials: 'RB',
            jobs: (17 * scale).round(),
            revenuePaise: money(178000),
            rating: 4.72,
            firstTimeFixPct: 84),
      ],
      customerSegments: [
        CustomerSegment('New', (120 * scale).round(), 34),
        CustomerSegment('Repeat', (168 * scale).round(), 47),
        CustomerSegment('Loyal (AMC)', (48 * scale).round(), 14),
        CustomerSegment('Lapsed 90d+', (18 * scale).round(), 5),
      ],
      complaintReasons: const [
        ComplaintReason('Rework — same issue recurred', 9, 36),
        ComplaintReason('Part failed early', 5, 52),
        ComplaintReason('Technician late', 7, 4),
        ComplaintReason('Billing dispute', 3, 18),
      ],
      paymentMix: [
        PaymentMixItem('UPI', money(268000), 56),
        PaymentMixItem('Cards', money(96000), 20),
        PaymentMixItem('Cash to technician', money(76000), 16),
        PaymentMixItem('Wallet / Care Coins', money(38000), 8),
      ],
      coupons: [
        CouponUsage('CARE30', (86 * scale).round(), money(184000)),
        CouponUsage('FIRSTCLEAN', (41 * scale).round(), money(61000)),
        CouponUsage('AMC10', (22 * scale).round(), money(29000)),
      ],
      financials: FinancialSummary(
        grossRevenuePaise: money(4820000),
        technicianPayoutsPaise: money(1928000),
        partsCostPaise: money(674000),
        taxCollectedPaise: money(734000),
        refundsPaise: money(41000),
        discountsGivenPaise: money(184000),
      ),
    );
  }

  List<TrendPoint> _trendFor(ReportRange range, {required int base}) {
    final labels = switch (range) {
      ReportRange.week => ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      ReportRange.month => ['W1', 'W2', 'W3', 'W4'],
      ReportRange.quarter => ['M1', 'M2', 'M3'],
    };
    final shape = switch (range) {
      ReportRange.week => [0.62, 0.78, 0.54, 0.88, 0.96, 0.71, 0.84],
      ReportRange.month => [0.58, 0.74, 0.82, 0.91],
      ReportRange.quarter => [0.61, 0.79, 0.94],
    };
    return [for (var i = 0; i < labels.length; i++) TrendPoint(labels[i], shape[i])];
  }

  List<TrendPoint> _ratingTrendFor(ReportRange range) {
    final labels = switch (range) {
      ReportRange.week => ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      ReportRange.month => ['W1', 'W2', 'W3', 'W4'],
      ReportRange.quarter => ['M1', 'M2', 'M3'],
    };
    final shape = switch (range) {
      ReportRange.week => [0.90, 0.92, 0.88, 0.94, 0.95, 0.93, 0.97],
      ReportRange.month => [0.89, 0.92, 0.94, 0.96],
      ReportRange.quarter => [0.88, 0.93, 0.97],
    };
    return [for (var i = 0; i < labels.length; i++) TrendPoint(labels[i], shape[i])];
  }
}
