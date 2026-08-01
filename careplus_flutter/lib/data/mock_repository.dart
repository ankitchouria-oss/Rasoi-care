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

}
