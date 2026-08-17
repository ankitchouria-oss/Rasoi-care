// Live [AdminRepository] backed by the Flask+SQLite backend at the repo
// root (app.py / database.py), sharing real data with careplus_flutter
// (customer) and careplus_partner (technician).
//
// The interface is synchronous by design (see repository.dart's header), so
// this class fetches in the background and caches whatever arrives; every
// getter serves the freshest cached value it has and falls back to
// [MockAdminRepository] — field by field — for anything not yet fetched,
// not fetched-able at all (no backend concept), or that failed (backend not
// deployed yet, timeout, 401, ...). It never throws and never blocks a
// screen's build.
//
// It's a [ChangeNotifier] so `ChangeNotifierProvider` (see
// lib/state/providers.dart) can rebuild watchers once background fetches
// resolve, without turning the repository interface itself async.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models.dart';
import '../repository.dart';
import 'api_config.dart';

const _timeout = Duration(seconds: 8);

class ApiRepository extends ChangeNotifier implements AdminRepository {
  ApiRepository({http.Client? client, MockAdminRepository? mock})
    : _client = client ?? http.Client(),
      _mock = mock ?? MockAdminRepository() {
    // Open endpoints — no auth needed, safe to fetch as soon as the
    // repository is first used (see providers.dart).
    unawaited(_fetchOverview());
    unawaited(_fetchBookings());
    unawaited(_fetchTechnicians());
    unawaited(_fetchInventory());
    // Staff-gated endpoints — by the time anything reads this repository the
    // user has already completed sign-in (it's only ever watched from the
    // post-auth dashboard shell), so a token should be available. If it
    // isn't yet, these just fail quietly and fall back to Mock.
    unawaited(_fetchStaffAccounts());
    unawaited(_fetchReport(ReportRange.week));
  }

  final http.Client _client;
  final MockAdminRepository _mock;

  // ---- raw cached pieces (null = not yet fetched / fetch failed) --------
  Map<String, dynamic>? _overviewRaw;
  int? _weekCompletedJobs;
  List<dynamic>? _bookingsRaw;
  List<dynamic>? _techniciansRaw;
  List<dynamic>? _inventoryRaw;
  List<dynamic>? _staffRaw;
  final Map<ReportRange, Map<String, dynamic>> _reportsRaw = {};
  final Set<ReportRange> _reportsFetching = {};

  // ============================================================ OVERVIEW
  @override
  AdminOverview overview() {
    final mock = _mock.overview();
    final raw = _overviewRaw;
    if (raw == null) return mock;
    final totalTechnicians = _asInt(raw['totalTechnicians']);
    final onlineTechnicians = _asInt(raw['onlineTechnicians']);
    final utilisationPct = totalTechnicians == 0
        ? 0
        : ((onlineTechnicians / totalTechnicians) * 100).round();
    return AdminOverview(
      revenuePaise: _asInt(raw['revenue']) * 100,
      // No week-over-week delta from the backend — pass through Mock's.
      revenueDeltaPct: mock.revenueDeltaPct,
      // /api/stats/overview's totalBookings isn't "closed" jobs; use the
      // period-scoped completedJobs from /api/stats/reports?period=week
      // when it's arrived, else fall back to Mock.
      jobsClosed: _weekCompletedJobs ?? mock.jobsClosed,
      jobsClosedDeltaPct: mock.jobsClosedDeltaPct,
      slaBreaches: mock.slaBreaches,
      slaBreachesToday: mock.slaBreachesToday,
      // No overall rating figure on this endpoint — Mock's.
      avgRating: mock.avgRating,
      ratingCount: mock.ratingCount,
      weekBars: mock.weekBars,
      weekLabels: mock.weekLabels,
      technicianUtilisationPct: utilisationPct,
      firstTimeFixPct: mock.firstTimeFixPct,
      attention: mock.attention,
    );
  }

  Future<void> _fetchOverview() async {
    try {
      final res = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/stats/overview'))
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      _overviewRaw = jsonDecode(res.body) as Map<String, dynamic>;
      notifyListeners();
    } catch (_) {
      // Backend not deployed yet / offline / timed out — keep serving Mock.
    }
  }

  // ============================================================ BOOKINGS
  @override
  List<AdminBooking> bookings() {
    final raw = _bookingsRaw;
    if (raw == null) return _mock.bookings();
    return [for (final b in raw) _bookingFrom(b as Map<String, dynamic>)];
  }

  AdminBooking _bookingFrom(Map<String, dynamic> b) {
    final area = (b['area'] as String?)?.trim();
    final customerName = (b['customerName'] as String?)?.trim();
    final meta = [
      if (area != null && area.isNotEmpty) area,
      if (customerName != null && customerName.isNotEmpty) customerName,
    ].join(' · ');
    final status = (b['status'] as String?) ?? 'Requested';
    return AdminBooking(
      jobId: (b['id'] as String?) ?? '—',
      title: (b['service'] as String?) ?? 'Service request',
      meta: meta.isEmpty ? '—' : meta,
      statusLabel: status,
      category: _categoryForStatus(status),
    );
  }

  /// The backend has no "scheduled" status string — every booking is either
  /// unassigned (just requested), some flavour of in-progress, or completed.
  /// Anything unrecognised is treated as in-progress (an active job of some
  /// kind) rather than silently dropped.
  BookingCategory _categoryForStatus(String status) => switch (status) {
    'Requested' => BookingCategory.unassigned,
    'Accepted' || 'On the way' || 'In Progress' => BookingCategory.inProgress,
    'Completed' => BookingCategory.closed,
    _ => BookingCategory.inProgress,
  };

  Future<void> _fetchBookings() async {
    try {
      final token = await _idToken();
      final res = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/bookings'),
            headers: _headers(token),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      _bookingsRaw = jsonDecode(res.body) as List<dynamic>;
      notifyListeners();
    } catch (_) {
      // keep serving Mock
    }
  }

  // ================================================================ TEAM
  @override
  List<AdminTeamMember> team() {
    final raw = _techniciansRaw;
    if (raw == null) return _mock.team();
    return [for (final t in raw) _teamMemberFrom(t as Map<String, dynamic>)];
  }

  AdminTeamMember _teamMemberFrom(Map<String, dynamic> t) {
    final name = (t['name'] as String?) ?? 'Technician';
    final online = t['online'] == true;
    return AdminTeamMember(
      id: t['id'] as String?,
      name: name,
      initials: _initials(name),
      specialties: (t['category'] as String?) ?? '—',
      area: t['area'] as String?,
      statsLabel: '${_asInt(t['jobsCompleted'])} jobs',
      rating: _asDouble(t['rating']),
      // The payload can't distinguish "actively on a job" from "idle but
      // online" — online maps to idle, offline to offDuty. onJob is never
      // emitted for API-sourced rows.
      duty: online ? DutyStatus.idle : DutyStatus.offDuty,
      verified: t['verified'] == true,
      applicationSubmitted: t['applicationSubmitted'] == true,
      photoUrl: t['photoUrl'] as String?,
      experienceYears: t['experienceYears'] == null ? null : _asInt(t['experienceYears']),
      idDocumentUrl: t['idDocumentUrl'] as String?,
      bankAccountName: t['bankAccountName'] as String?,
      bankAccountNumber: t['bankAccountNumber'] as String?,
      bankIfsc: t['bankIfsc'] as String?,
    );
  }

  Future<void> _fetchTechnicians() async {
    try {
      final res = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/technicians'))
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      _techniciansRaw = jsonDecode(res.body) as List<dynamic>;
      notifyListeners();
    } catch (_) {
      // keep serving Mock
    }
  }

  @override
  Future<bool> verifyTechnician(String technicianId) async {
    try {
      final res = await _client
          .patch(Uri.parse('${ApiConfig.baseUrl}/api/technicians/$technicianId/verify'))
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      // Refresh the cache so the Team screen reflects the change immediately
      // without waiting for the next natural refetch.
      await _fetchTechnicians();
      return true;
    } catch (_) {
      return false;
    }
  }

  // =============================================================== STOCK
  @override
  List<AdminStockItem> stock() {
    final raw = _inventoryRaw;
    if (raw == null) return _mock.stock();
    return [for (final s in raw) _stockItemFrom(s as Map<String, dynamic>)];
  }

  AdminStockItem _stockItemFrom(Map<String, dynamic> s) => AdminStockItem(
    name: (s['name'] as String?) ?? 'Item',
    sku: (s['sku'] as String?) ?? '—',
    inStock: _asInt(s['quantity']),
    reorderAt: _asInt(s['reorderLevel']),
    low: s['lowStock'] == true,
    // No burn-rate data from the backend — small placeholder constant.
    burnPerDay: 1.0,
  );

  Future<void> _fetchInventory() async {
    try {
      final res = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/inventory'))
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      _inventoryRaw = jsonDecode(res.body) as List<dynamic>;
      notifyListeners();
    } catch (_) {
      // keep serving Mock
    }
  }

  // ========================================================= STAFF ACCTS
  @override
  List<StaffAccount> staffAccounts() {
    final raw = _staffRaw;
    if (raw == null) return _mock.staffAccounts();
    return [for (final s in raw) _staffAccountFrom(s as Map<String, dynamic>)];
  }

  StaffAccount _staffAccountFrom(Map<String, dynamic> s) {
    final name = (s['name'] as String?) ?? 'Staff';
    final roleStr = (s['role'] as String?) ?? 'staff';
    return StaffAccount(
      name: name,
      initials: _initials(name),
      // May be a synthetic `fb-...` placeholder for Firebase-bootstrapped
      // accounts that never set a real phone — displayed as-is.
      phone: (s['phone'] as String?) ?? '—',
      role: roleStr == 'owner' ? AdminRole.owner : AdminRole.staff,
      // The backend has no "invited" concept — only active/suspended.
      status: s['active'] == true ? StaffStatus.active : StaffStatus.suspended,
      lastActive: _formatCreatedAt(s['createdAt'] as String?),
    );
  }

  String _formatCreatedAt(String? raw) {
    final dt = raw == null ? null : DateTime.tryParse(raw);
    if (dt == null) return 'Joined —';
    return 'Joined ${DateFormat('MMM d, yyyy').format(dt.toLocal())}';
  }

  Future<void> _fetchStaffAccounts() async {
    try {
      final token = await _idToken();
      if (token == null) return; // staff-gated — nothing to fetch without one
      final res = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/staff'),
            headers: _headers(token),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      _staffRaw = jsonDecode(res.body) as List<dynamic>;
      notifyListeners();
    } catch (_) {
      // keep serving Mock
    }
  }

  // ============================================================= REPORTS
  @override
  ReportBundle report(ReportRange range) {
    final raw = _reportsRaw[range];
    if (raw == null) {
      // Kick off a fetch for whichever range was just asked for (the week
      // range is already fetched eagerly in the constructor) — at most one
      // attempt per range per app session.
      if (!_reportsFetching.contains(range)) unawaited(_fetchReport(range));
      return _mock.report(range);
    }
    return _reportBundleFrom(range, raw);
  }

  ReportBundle _reportBundleFrom(ReportRange range, Map<String, dynamic> raw) {
    final mock = _mock.report(range);
    final pnl = raw['pnl'] as Map<String, dynamic>?;
    return ReportBundle(
      range: range,
      revenueTrend: _normalizedTrend(
        (raw['revenueTrend'] as List<dynamic>? ?? []),
        valueKey: 'revenue',
      ),
      ratingTrend: _normalizedTrend(
        (raw['ratingTrend'] as List<dynamic>? ?? []),
        valueKey: 'avgRating',
        fixedMax: 5.0,
      ),
      categoryRevenue: [
        for (final c in (raw['revenueByCategory'] as List<dynamic>? ?? []))
          CategoryRevenue(
            (c as Map<String, dynamic>)['category'] as String? ?? '—',
            '●', // no glyph data server-side
            _asInt(c['revenue']) * 100,
            0, // no per-category job count in this payload
          ),
      ],
      technicianLeaderboard: [
        for (final t in (raw['technicianLeaderboard'] as List<dynamic>? ?? []))
          _technicianRowFrom(t as Map<String, dynamic>),
      ],
      // No server data at all for these four — pass Mock through unchanged.
      customerSegments: mock.customerSegments,
      complaintReasons: mock.complaintReasons,
      paymentMix: mock.paymentMix,
      coupons: mock.coupons,
      financials: pnl == null ? mock.financials : _financialsFrom(pnl),
    );
  }

  TechnicianRow _technicianRowFrom(Map<String, dynamic> t) {
    final name = (t['name'] as String?) ?? 'Technician';
    return TechnicianRow(
      name: name,
      initials: _initials(name),
      jobs: _asInt(t['jobsInPeriod']),
      revenuePaise: _asInt(t['revenueInPeriod']) * 100,
      rating: _asDouble(t['rating']),
      // No real first-time-fix data per technician per period — placeholder.
      firstTimeFixPct: 90,
    );
  }

  /// [FinancialSummary.netMarginPaise] is a derived getter (gross - payouts
  /// - parts - refunds - discounts), and the backend's pnl block only
  /// breaks out gross revenue and technician payout — parts cost, tax,
  /// refunds and discounts aren't tracked there. Those four are left at 0,
  /// so the derived net margin is gross-minus-payout, the closest available
  /// approximation of the backend's own `netMargin` figure.
  FinancialSummary _financialsFrom(Map<String, dynamic> pnl) =>
      FinancialSummary(
        grossRevenuePaise: _asInt(pnl['grossRevenue']) * 100,
        technicianPayoutsPaise: _asInt(pnl['technicianPayout']) * 100,
        partsCostPaise: 0,
        taxCollectedPaise: 0,
        refundsPaise: 0,
        discountsGivenPaise: 0,
      );

  List<TrendPoint> _normalizedTrend(
    List<dynamic> points, {
    required String valueKey,
    double? fixedMax,
  }) {
    if (points.isEmpty) return const [];
    final values = [
      for (final p in points) _asDouble((p as Map<String, dynamic>)[valueKey]),
    ];
    final max = fixedMax ?? values.fold<double>(0, (m, v) => v > m ? v : m);
    return [
      for (var i = 0; i < points.length; i++)
        TrendPoint(
          (points[i] as Map<String, dynamic>)['date'] as String? ?? '',
          max <= 0 ? 0 : (values[i] / max).clamp(0, 1),
        ),
    ];
  }

  Future<void> _fetchReport(ReportRange range) async {
    _reportsFetching.add(range);
    try {
      final token = await _idToken();
      if (token == null) return; // staff-gated — nothing to fetch without one
      final period = switch (range) {
        ReportRange.week => 'week',
        ReportRange.month => 'month',
        ReportRange.quarter => 'quarter',
      };
      final res = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/stats/reports?period=$period'),
            headers: _headers(token),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      _reportsRaw[range] = json;
      if (range == ReportRange.week) {
        _weekCompletedJobs = _asInt(json['completedJobs']);
      }
      notifyListeners();
    } catch (_) {
      // keep serving Mock
    } finally {
      _reportsFetching.remove(range);
    }
  }

  // ================================================================ UTIL
  Future<String?> _idToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers(String? token) => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  int _asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  double _asDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
