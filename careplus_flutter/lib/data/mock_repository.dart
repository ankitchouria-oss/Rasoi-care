// The repository interface is the seam between the app and its backend.
//
// Every screen depends on [CareRepository], never on a data source directly.
// [MockRepository] serves canned data so the app runs with no backend. To go
// live, write a FirestoreRepository that implements the same interface and
// swap the provider in lib/state/providers.dart — no screen changes.

import 'dart:async';
import 'models.dart';

abstract interface class CareRepository {
  List<ServiceItem> servicesFor(Appliance a);
  List<ServiceItem> catalog();
  List<Issue> issuesFor(Appliance a);
  List<SavedAddress> addresses();
  List<PaymentMethod> paymentMethods();
  List<Booking> bookings({BookingStatus? status, bool completed = false});
  Technician get preferredTechnician;

  /// Simulated tracking feed. Emits an ETA (minutes) that counts down, so the
  /// tracking screen has something live to animate. Firestore version streams
  /// technicians/{id}/locations/live instead.
  Stream<int> etaStream(String bookingId);

  // --- Technician app ---
  TechStats techStats();
  JobRequest? incomingRequest();
  List<RouteStop> routeToday();
  JobDetail jobDetail(String jobId);
  List<InvoiceLine> closeInvoice(String jobId);

  // --- Admin console ---
  AdminOverview adminOverview();
  List<AdminBooking> adminBookings();
  List<AdminTeamMember> adminTeam();
  List<AdminStockItem> adminStock();
}

class MockRepository implements CareRepository {
  static const _sandeep = Technician(
    id: 't_sandeep',
    name: 'Sandeep Pawar',
    initials: 'SP',
    rating: 4.94,
    jobsDone: 1860,
    years: 6,
    vehicle: 'MH15 CJ 8842',
  );

  @override
  Technician get preferredTechnician => _sandeep;

  @override
  List<ServiceItem> servicesFor(Appliance a) => [
        ServiceItem(
          id: '${a.name}_clean',
          appliance: a,
          title: 'Deep clean — filters, motor, duct',
          blurb:
              'Degreasing bath for filters, blower and oil collector · 90 min',
          pricePaise: 89900,
          strikePaise: 129900,
          durationMin: 90,
          mostBooked: true,
        ),
        ServiceItem(
          id: '${a.name}_repair',
          appliance: a,
          title: 'Repair visit and diagnosis',
          blurb: 'Fee waived if you approve the repair quote · parts extra',
          pricePaise: 39900,
          durationMin: 45,
        ),
        ServiceItem(
          id: '${a.name}_install',
          appliance: a,
          title: 'Installation with duct work',
          blurb: 'Wall or island mount, up to 6 ft of ducting included',
          pricePaise: 149900,
          durationMin: 120,
        ),
        ServiceItem(
          id: '${a.name}_uninstall',
          appliance: a,
          title: 'Uninstall and shift',
          blurb: 'Safe removal, capping and packing for a move',
          pricePaise: 74900,
          durationMin: 60,
        ),
      ];

  @override
  List<ServiceItem> catalog() => [
        for (final a in Appliance.values) servicesFor(a).first,
      ];

  @override
  List<Issue> issuesFor(Appliance a) => const [
        Issue('Weak or no suction', 'Most common on 2+ year old units',
            selected: true),
        Issue('Oil dripping from the hood', 'Collector or filter saturation',
            selected: true),
        Issue('Loud or rattling motor', 'Blower imbalance or loose mount'),
        Issue('Auto-clean not working', 'Heating coil or timer fault'),
        Issue('Lights not turning on', 'LED or switch failure'),
        Issue('Not switching on at all', 'Power, PCB or capacitor'),
      ];

  @override
  List<SavedAddress> addresses() => const [
        SavedAddress('a_home', 'Home',
            'B-704, Ashwin Residency, Gangapur Rd, Nashik 422013', '🏠'),
        SavedAddress('a_parents', 'Parents',
            '12, Shivneri Colony, College Rd, Nashik 422005', '🏢'),
      ];

  @override
  List<PaymentMethod> paymentMethods() => const [
        PaymentMethod('upi', 'UPI — GPay, PhonePe, Paytm', 'Instant · no fee', '▲'),
        PaymentMethod('card', 'HDFC •••• 4471', 'Visa credit', '▭'),
        PaymentMethod('wallet', 'Care+ wallet', '₹1,240 available', '◍'),
        PaymentMethod('netbank', 'Net banking', '12 banks', '▤'),
        PaymentMethod('cod', 'Pay after the visit', 'Cash or UPI to technician', '₹'),
      ];

  @override
  List<Booking> bookings({BookingStatus? status, bool completed = false}) {
    final all = <Booking>[
      Booking(
        id: 'CP-2481-NSK',
        title: 'Chimney deep clean',
        appliance: Appliance.chimney,
        status: BookingStatus.onTheWay,
        whenLabel: 'Today · 10:00–11:00 am · Home',
        addressLabel: 'Home',
        totalPaise: 80000,
        technician: _sandeep,
      ),
      const Booking(
        id: 'CP-2496-NSK',
        title: 'RO purifier — filter change',
        appliance: Appliance.purifier,
        status: BookingStatus.scheduled,
        whenLabel: '02 Aug · 4:00–6:00 pm · Parents',
        addressLabel: 'Parents',
        totalPaise: 129900,
      ),
      const Booking(
        id: 'CP-2109-NSK',
        title: 'Dishwasher — drain pump',
        appliance: Appliance.dishwasher,
        status: BookingStatus.completed,
        whenLabel: '12 Jun · Home',
        addressLabel: 'Home',
        totalPaise: 324000,
        stars: 5,
      ),
      const Booking(
        id: 'CP-1884-NSK',
        title: 'Chimney deep clean',
        appliance: Appliance.chimney,
        status: BookingStatus.completed,
        whenLabel: '12 Feb · Home',
        addressLabel: 'Home',
        totalPaise: 89900,
        stars: 5,
      ),
    ];
    if (completed) {
      return all.where((b) => b.status == BookingStatus.completed).toList();
    }
    return all
        .where((b) => b.status != BookingStatus.completed)
        .where((b) => status == null || b.status == status)
        .toList();
  }

  @override
  Stream<int> etaStream(String bookingId) async* {
    var eta = 14;
    yield eta;
    while (eta > 0) {
      await Future<void>.delayed(const Duration(seconds: 4));
      eta -= 1;
      yield eta;
    }
  }

  // --- Technician app ---
  @override
  TechStats techStats() => const TechStats(
        earningsTodayPaise: 318000,
        jobsDone: 4,
        jobsTotal: 6,
        tipsPaise: 42000,
        rating: 4.94,
        firstTimeFixPct: 91,
        onDuty: true,
      );

  @override
  JobRequest? incomingRequest() => const JobRequest(
        jobId: 'CP-2481',
        serviceTitle: 'Chimney · deep clean',
        distanceKm: 2.4,
        timeWindow: '10:00–11:00 am',
        payoutPaise: 64000,
        note: '2 filters flagged',
      );

  @override
  List<RouteStop> routeToday() => const [
        RouteStop(
          jobId: 'CP-2481',
          time: '10:00 am',
          title: 'Chimney deep clean',
          customerName: 'R. Deshpande',
          meta: 'B-704 Ashwin Residency · start code needed',
          status: StopStatus.inProgress,
        ),
        RouteStop(
          jobId: 'CP-2483',
          time: '12:30 pm',
          title: 'Hob — igniter fault',
          customerName: 'M. Kulkarni',
          meta: 'College Road · 3.1 km from previous',
          status: StopStatus.next,
        ),
        RouteStop(
          jobId: 'CP-2488',
          time: '3:00 pm',
          title: 'RO purifier — filter set',
          customerName: 'A. Sharma',
          meta: 'Indira Nagar · parts in van ✓',
          status: StopStatus.next,
        ),
      ];

  @override
  JobDetail jobDetail(String jobId) => JobDetail(
        jobId: jobId,
        customerName: 'Rohan Deshpande',
        customerInitials: 'RD',
        addressLine: 'B-704, Ashwin Residency, Gangapur Rd',
        directions: 'Gate code 4402, lift on the left',
        reportedTags: const ['Weak suction', 'Rattling noise', 'Oil dripping'],
        reportedQuote:
            'Smoke lingers even on turbo, and there\'s a rattle when it starts.',
        checklist: const [
          ChecklistItem('Start code verified', checked: true),
          ChecklistItem('Floor sheeting laid', checked: true),
          ChecklistItem('Suction reading before — 480 m³/hr', checked: true),
          ChecklistItem('Filters and blower degreased', checked: true),
          ChecklistItem('Suction reading after'),
          ChecklistItem('Site cleaned, customer walkthrough'),
        ],
        parts: const [
          PartLine(
            name: 'Baffle filter — Elica 90cm',
            sku: 'ELF-90B',
            qty: 2,
            pricePaise: 64000,
            approved: true,
            approvedAt: '11:02',
          ),
        ],
      );

  @override
  List<InvoiceLine> closeInvoice(String jobId) => const [
        InvoiceLine('Deep clean (prepaid)', 89900),
        InvoiceLine('Baffle filter set (2)', 64000),
        InvoiceLine('Visit and safety kit', 4900),
        InvoiceLine('CARE30', -27000, tone: LineTone.success),
        InvoiceLine('GST 18%', 23700),
      ];

  // --- Admin console ---
  @override
  AdminOverview adminOverview() => const AdminOverview(
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
  List<AdminBooking> adminBookings() => const [
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
  List<AdminTeamMember> adminTeam() => const [
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
  List<AdminStockItem> adminStock() => const [
        AdminStockItem(
            name: 'Elica baffle filter 90cm',
            sku: 'ELF-90B',
            inStock: 8,
            reorderAt: 40,
            low: true),
        AdminStockItem(
            name: 'RO membrane 80 GPD',
            sku: 'ROM-80',
            inStock: 14,
            reorderAt: 40,
            low: true),
        AdminStockItem(
            name: 'Hob igniter — universal',
            sku: 'HBI-U',
            inStock: 9,
            reorderAt: 30,
            low: true),
        AdminStockItem(
            name: 'Dishwasher drain pump',
            sku: 'DWP-BSH',
            inStock: 26,
            reorderAt: 30,
            low: false),
        AdminStockItem(
            name: 'Fridge gas R600a (can)',
            sku: 'GAS-600',
            inStock: 48,
            reorderAt: 30,
            low: false),
      ];
}
