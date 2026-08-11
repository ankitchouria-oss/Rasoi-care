// Maps between this app's [Appliance] enum and the backend's
// APPLIANCES_SEED category strings (app.py/database.py at the repo root).
// The backend has no chimney/hob/cooktop/... granularity of its own — it
// groups appliances under coarser "categories" — so this mapping is lossy
// in both directions and that's expected, not a bug:
//  * forward (booking creation): hob and cooktop both fall under
//    "RasoiSpark"; microwave and otg both fall under "RasoiBuilt".
//  * reverse (reading a booking back): "RasoiSpark" could have originated
//    from either a hob or cooktop booking, "RasoiBuilt" from either a
//    microwave or otg booking. We default to whichever appliance is first
//    in the forward mapping (hob, microwave respectively) — cosmetic only,
//    it only affects which icon/label a real booking shows.

import '../models.dart';

const Map<Appliance, String> applianceToBackendCategory = {
  Appliance.chimney: 'RasoiAir',
  Appliance.hob: 'RasoiSpark',
  Appliance.cooktop: 'RasoiSpark',
  Appliance.dishwasher: 'RasoiWash',
  Appliance.microwave: 'RasoiBuilt',
  Appliance.refrigerator: 'RasoiChill',
  Appliance.otg: 'RasoiBuilt',
  Appliance.purifier: 'RasoiPure',
};

const Map<String, Appliance> backendCategoryToAppliance = {
  'RasoiAir': Appliance.chimney,
  'RasoiSpark': Appliance.hob, // ambiguous with cooktop — default to hob
  'RasoiWash': Appliance.dishwasher,
  'RasoiBuilt': Appliance.microwave, // ambiguous with otg — default to microwave
  'RasoiChill': Appliance.refrigerator,
  'RasoiPure': Appliance.purifier,
};
