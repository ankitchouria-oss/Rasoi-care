// The repository interface is the seam between the app and its backend.
//
// Every screen depends on [PartnerRepository], never on a data source
// directly. [MockPartnerRepository] serves canned data so the app runs with
// no backend. To go live, write a real repository implementing the same
// interface and swap the provider in lib/state/providers.dart — no screen
// changes.

import 'models.dart';

abstract interface class PartnerRepository {
  TechStats techStats();
  JobRequest? incomingRequest();
  List<RouteStop> routeToday();
  JobDetail jobDetail(String jobId);
  List<InvoiceLine> closeInvoice(String jobId);
}

class MockPartnerRepository implements PartnerRepository {
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
}
