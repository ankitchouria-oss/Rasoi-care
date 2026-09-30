"""
Kitchen Passport — default scoring / scheduling configuration.

Everything the engines use to turn raw inspection data into a Health
Score, Safety Status, Repair Priority and Next Service Date lives here as
plain JSON-serialisable data. Nothing in engine.py hard-codes a weight,
threshold or interval.

At runtime the active configuration is DEFAULT_CONFIG deep-merged with
the per-section overrides an admin saved in the `kp_config` table (see
store.load_config). Every saved change bumps `algorithm_version`, which
is stored next to every calculated health score so historical scores
stay explainable after the algorithm changes — and because raw
inspection values are kept separately, any inspection can be re-scored
under the current algorithm at any time.

Parameter definition fields
---------------------------
key        stable identifier (also the column/measurement key)
label      technician-facing label
type       "enum" | "number" | "bool" | "text"
options    enum only: {VALUE: fraction 0..1, or None = "not applicable"}
unit       number only: display unit
required   must be present for the inspection to be scored
malfunction enum only: values that mean the appliance is not working
            properly — they push repair priority to HIGH

Component scorer types
----------------------
enum       average of the option fractions of `params` (combine "min"
           takes the worst instead)
bool_bad   each listed bool param scores 0 when true, 1 when false
band       numeric param mapped through `bands` ([[threshold, fraction]]);
           direction "higher_better" picks the first band whose threshold
           the value is >= to; "lower_better" the first band whose
           threshold the value is <= to
mixed      average of several sub-scorers (used when one component is
           judged from both enum and numeric readings)
service_history  derived by the engine from the appliance's own service
           and repair history — never entered by a technician
"""

INF = 1e18

# --------------------------------------------------------------- shared option sets
COND3 = {"GOOD": 1.0, "FAIR": 0.6, "POOR": 0.2}
NOISE = {"NORMAL": 1.0, "SLIGHT": 0.75, "NOTICEABLE": 0.45, "SEVERE": 0.1}
CLEAN3 = {"CLEAN": 1.0, "MODERATE": 0.6, "DIRTY": 0.25}
SEAL = {"GOOD": 1.0, "WORN": 0.55, "DAMAGED": 0.1}
WIRING = {"GOOD": 1.0, "WORN": 0.6, "DAMAGED": 0.15, "EXPOSED": 0.0}
ELECTRICAL = {"GOOD": 1.0, "LOOSE_CONNECTION": 0.5, "DAMAGED": 0.1, "EXPOSED_WIRING": 0.0}
PLUG = {"GOOD": 1.0, "LOOSE": 0.6, "DAMAGED": 0.15, "BURNT": 0.0}
SWITCH = {"GOOD": 1.0, "LOOSE": 0.6, "FAULTY": 0.2}
EARTHING = {"PROPER": 1.0, "WEAK": 0.5, "ABSENT": 0.0}
TECH_VIEW = {"GOOD": 1.0, "FAIR": 0.6, "POOR": 0.2}


def enum(key, label, options, required=True, malfunction=None):
    d = {"key": key, "label": label, "type": "enum", "options": dict(options), "required": required}
    if malfunction:
        d["malfunction"] = list(malfunction)
    return d


def num(key, label, unit="", required=True):
    return {"key": key, "label": label, "type": "number", "unit": unit, "required": required}


def boolean(key, label, required=True):
    return {"key": key, "label": label, "type": "bool", "required": required}


def text(key, label, required=False):
    return {"key": key, "label": label, "type": "text", "required": required}


def comp(key, label, weight, scorer, key_performance=False):
    return {"key": key, "label": label, "weight": weight, "scorer": scorer, "key_performance": key_performance}


def rule(param, op, value, level, finding, customer_message=None):
    return {
        "param": param, "op": op, "value": value, "level": level, "finding": finding,
        "customer_message": customer_message or finding,
    }


def rec(when, text_, technical=None):
    return {"when": when, "text": text_, "technical": technical or text_}


SERVICE_HISTORY = {"type": "service_history"}

# =============================================================== CATEGORIES
CATEGORIES = {
    # ----------------------------------------------------------- CHIMNEY
    "CHIMNEY": {
        "label": "Kitchen Chimney",
        "id_prefix": "CH",
        "phase": 1,
        "base_service_interval_days": 90,
        "intensity_sensitive": True,
        "params": [
            num("rated_suction", "Rated suction", "m³/h"),
            num("measured_suction", "Measured suction", "m³/h"),
            text("suction_unit", "Suction unit"),
            text("test_condition", "Test condition (e.g. max speed, filters fitted)"),
            enum("filter_condition", "Filter condition", {
                "CLEAN": 1.0, "LIGHT_GREASE": 0.85, "MODERATE_GREASE": 0.6, "HEAVY_GREASE": 0.3, "BLOCKED": 0.0}),
            enum("motor_condition", "Motor condition", {
                "NORMAL": 1.0, "MINOR_NOISE": 0.8, "EXCESS_NOISE": 0.5, "VIBRATION": 0.5, "OVERHEATING": 0.2,
                "MOTOR_REPAIR_REQUIRED": 0.15, "MOTOR_REPLACEMENT_REQUIRED": 0.0},
                malfunction=["MOTOR_REPAIR_REQUIRED", "MOTOR_REPLACEMENT_REQUIRED"]),
            enum("noise_vibration", "Noise / vibration", NOISE),
            num("duct_diameter", "Duct diameter", "mm", required=False),
            num("duct_length", "Duct length", "m", required=False),
            num("bend_count", "Duct bend count", "bends"),
            enum("outlet_condition", "Outlet condition", {
                "GOOD": 1.0, "PARTIALLY_BLOCKED": 0.5, "BLOCKED": 0.0, "DAMAGED": 0.3}),
            enum("blockage_level", "Duct blockage level", {"NONE": 1.0, "MINOR": 0.8, "MODERATE": 0.5, "SEVERE": 0.1}),
            enum("airflow_condition", "Airflow condition", {"GOOD": 1.0, "REDUCED": 0.6, "POOR": 0.2}),
            enum("wiring_condition", "Wiring condition", WIRING),
            enum("plug_condition", "Plug condition", PLUG),
            enum("switch_condition", "Switch condition", SWITCH),
            enum("earthing_condition", "Earthing condition", EARTHING),
            boolean("visible_damage", "Visible electrical damage"),
            boolean("overheating", "Electrical overheating"),
            enum("physical_condition", "Physical condition (body, panels)", COND3),
            enum("grease_accumulation", "Grease accumulation (body / baffle area)", {
                "NONE": 1.0, "LIGHT": 0.8, "MODERATE": 0.5, "HEAVY": 0.2}),
            enum("technician_assessment", "Technician overall assessment", TECH_VIEW),
        ],
        "derived": ["suction_percentage"],
        "components": [
            comp("suction", "Suction / Performance", 25, {
                "type": "band", "param": "suction_percentage", "direction": "higher_better",
                "bands": [[90, 1.0], [80, 0.85], [70, 0.7], [60, 0.5], [50, 0.3], [0, 0.1]]}, key_performance=True),
            comp("filter", "Filter / Grease", 15, {"type": "enum", "params": ["filter_condition"]}, key_performance=True),
            comp("motor", "Motor", 10, {"type": "enum", "params": ["motor_condition"]}, key_performance=True),
            comp("noise", "Noise / Vibration", 10, {"type": "enum", "params": ["noise_vibration"]}),
            comp("duct", "Duct / Airflow", 10, {"type": "mixed", "scorers": [
                {"type": "enum", "params": ["outlet_condition", "blockage_level", "airflow_condition"]},
                {"type": "band", "param": "bend_count", "direction": "lower_better",
                 "bands": [[2, 1.0], [4, 0.8], [6, 0.55], [INF, 0.35]]},
            ]}),
            comp("electrical", "Electrical / Safety", 10, {"type": "mixed", "scorers": [
                {"type": "enum", "params": ["wiring_condition", "plug_condition", "switch_condition", "earthing_condition"]},
                {"type": "bool_bad", "params": ["visible_damage", "overheating"]},
            ]}),
            comp("physical", "Physical Condition", 5, {"type": "enum", "params": ["physical_condition"]}),
            comp("service_history", "Service History", 5, SERVICE_HISTORY),
            comp("grease", "Grease Accumulation", 5, {"type": "enum", "params": ["grease_accumulation"]}),
            comp("technician", "Technician Inspection", 5, {"type": "enum", "params": ["technician_assessment"]}),
        ],
        "safety_rules": [
            rule("wiring_condition", "eq", "EXPOSED", "CRITICAL", "Exposed electrical wiring on chimney",
                 "Exposed wiring was found on your chimney. Please avoid using it until it is repaired."),
            rule("plug_condition", "eq", "BURNT", "CRITICAL", "Burnt plug / socket — overheating evidence",
                 "Burn marks were found on the chimney plug. Please avoid using it until it is repaired."),
            rule("overheating", "true", None, "CRITICAL", "Dangerous electrical overheating",
                 "Dangerous overheating was detected. Please switch off the chimney until it is repaired."),
            rule("wiring_condition", "eq", "DAMAGED", "ATTENTION_REQUIRED", "Damaged chimney wiring",
                 "Wiring needs repair."),
            rule("plug_condition", "eq", "DAMAGED", "ATTENTION_REQUIRED", "Damaged plug", "Plug needs replacement."),
            rule("earthing_condition", "eq", "ABSENT", "ATTENTION_REQUIRED", "No earthing on chimney supply",
                 "Electrical earthing needs to be checked."),
            rule("visible_damage", "true", None, "ATTENTION_REQUIRED", "Visible electrical damage",
                 "Electrical inspection required."),
            rule("motor_condition", "eq", "OVERHEATING", "ATTENTION_REQUIRED", "Motor overheating",
                 "Motor is running hot and needs inspection."),
            rule("earthing_condition", "eq", "WEAK", "MONITOR", "Weak earthing", "Earthing should be monitored."),
            rule("grease_accumulation", "eq", "HEAVY", "MONITOR", "Heavy grease build-up (fire load)",
                 "Heavy grease build-up — cleaning reduces fire risk."),
        ],
        "recommendations": [
            rec({"param": "filter_condition", "op": "in", "value": ["HEAVY_GREASE", "BLOCKED"]},
                "Chimney deep cleaning", "Deep clean: filter heavily greased/blocked"),
            rec({"param": "filter_condition", "op": "in", "value": ["MODERATE_GREASE", "HEAVY_GREASE", "BLOCKED"]},
                "Filter maintenance", "Filter degrease / replace"),
            rec({"param": "grease_accumulation", "op": "in", "value": ["MODERATE", "HEAVY"]},
                "Chimney deep cleaning", "Body grease accumulation"),
            rec({"component": "suction", "below": 0.85}, "Airflow inspection", "Suction below 80% of rated"),
            rec({"param": "blockage_level", "op": "in", "value": ["MODERATE", "SEVERE"]},
                "Airflow inspection", "Duct restriction"),
            rec({"param": "airflow_condition", "op": "in", "value": ["REDUCED", "POOR"]},
                "Airflow inspection", "Airflow reduced"),
            rec({"param": "outlet_condition", "op": "in", "value": ["BLOCKED", "PARTIALLY_BLOCKED", "DAMAGED"]},
                "Duct outlet repair", "Outlet blocked/damaged"),
            rec({"param": "motor_condition", "op": "in", "value": ["MOTOR_REPAIR_REQUIRED", "OVERHEATING", "VIBRATION", "EXCESS_NOISE"]},
                "Motor repair", "Motor fault"),
            rec({"param": "motor_condition", "op": "eq", "value": "MOTOR_REPLACEMENT_REQUIRED"},
                "Motor replacement", "Motor replacement required"),
            rec({"component": "electrical", "below": 0.8}, "Electrical inspection", "Electrical findings"),
        ],
    },
    # ----------------------------------------------------------- HOB
    "HOB": {
        "label": "Hob / Cooktop",
        "id_prefix": "HB",
        "phase": 1,
        "base_service_interval_days": 180,
        "intensity_sensitive": True,
        "params": [
            enum("burner_performance", "Burner performance", {"GOOD": 1.0, "REDUCED": 0.6, "POOR": 0.25, "NOT_WORKING": 0.0},
                 malfunction=["NOT_WORKING"]),
            enum("flame_quality", "Flame quality", {"BLUE_STEADY": 1.0, "MOSTLY_BLUE": 0.75, "YELLOW_TIPS": 0.45, "YELLOW_UNSTABLE": 0.1}),
            enum("ignition_condition", "Ignition", {"WORKING": 1.0, "DELAYED": 0.65, "INTERMITTENT": 0.35, "NOT_WORKING": 0.0},
                 malfunction=["NOT_WORKING"]),
            enum("gas_connection_condition", "Gas connection", {"GOOD": 1.0, "WORN": 0.5, "DAMAGED": 0.0, "NOT_APPLICABLE": None}),
            enum("electrical_connection_condition", "Electrical connection", {
                "GOOD": 1.0, "LOOSE": 0.5, "DAMAGED": 0.0, "NOT_APPLICABLE": None}),
            enum("burner_condition", "Burner condition", {"GOOD": 1.0, "CLOGGED": 0.5, "CORRODED": 0.4, "DAMAGED": 0.1}),
            enum("knob_condition", "Knobs / controls", {"GOOD": 1.0, "LOOSE": 0.6, "DAMAGED": 0.2}),
            enum("pan_support_condition", "Pan supports", {"GOOD": 1.0, "UNSTABLE": 0.5, "DAMAGED": 0.2}),
            enum("glass_condition", "Glass / top", {"GOOD": 1.0, "SCRATCHED": 0.75, "CHIPPED": 0.4, "CRACKED": 0.0}),
            enum("leakage_check", "Gas leakage check", {"NO_LEAK": 1.0, "SUSPECTED": 0.0, "LEAK_DETECTED": 0.0}),
            enum("cleaning_condition", "Cleaning condition", CLEAN3),
        ],
        "derived": [],
        "components": [
            comp("burner_performance", "Burner Performance", 20, {"type": "enum", "params": ["burner_performance"]}, key_performance=True),
            comp("flame", "Flame Quality", 15, {"type": "enum", "params": ["flame_quality"]}, key_performance=True),
            comp("ignition", "Ignition", 10, {"type": "enum", "params": ["ignition_condition"]}, key_performance=True),
            comp("connection", "Gas / Electrical Connection", 15, {
                "type": "enum", "params": ["gas_connection_condition", "electrical_connection_condition"], "combine": "min"}),
            comp("burner_condition", "Burner Condition", 10, {"type": "enum", "params": ["burner_condition"]}),
            comp("knobs", "Knobs / Controls", 5, {"type": "enum", "params": ["knob_condition"]}),
            comp("pan_supports", "Pan Supports", 5, {"type": "enum", "params": ["pan_support_condition"]}),
            comp("glass", "Glass / Top Condition", 5, {"type": "enum", "params": ["glass_condition"]}),
            comp("safety", "Safety Inspection", 10, {"type": "enum", "params": ["leakage_check"]}),
            comp("cleaning", "Cleaning Condition", 5, {"type": "enum", "params": ["cleaning_condition"]}),
        ],
        "safety_rules": [
            rule("leakage_check", "in", ["SUSPECTED", "LEAK_DETECTED"], "CRITICAL", "Suspected gas leakage",
                 "A possible gas leak was found. Keep the gas supply off, ventilate the kitchen and do not use the hob until it is repaired."),
            rule("gas_connection_condition", "eq", "DAMAGED", "CRITICAL", "Damaged gas connection / hose",
                 "The gas connection is damaged. Keep the gas supply off until it is replaced."),
            rule("electrical_connection_condition", "eq", "DAMAGED", "CRITICAL", "Damaged electrical connection",
                 "The hob's electrical connection is damaged. Do not use it until repaired."),
            rule("gas_connection_condition", "eq", "WORN", "ATTENTION_REQUIRED", "Worn gas hose / connection",
                 "Gas hose is worn and should be replaced soon."),
            rule("electrical_connection_condition", "eq", "LOOSE", "ATTENTION_REQUIRED", "Loose electrical connection",
                 "Electrical connection needs tightening."),
            rule("glass_condition", "eq", "CRACKED", "ATTENTION_REQUIRED", "Cracked glass top", "Glass top is cracked."),
            rule("flame_quality", "eq", "YELLOW_UNSTABLE", "ATTENTION_REQUIRED", "Yellow unstable flame (incomplete combustion)",
                 "Flame is burning incorrectly and needs adjustment."),
        ],
        "recommendations": [
            rec({"param": "leakage_check", "op": "in", "value": ["SUSPECTED", "LEAK_DETECTED"]},
                "Urgent gas leak repair", "Gas leak test failed"),
            rec({"param": "gas_connection_condition", "op": "in", "value": ["WORN", "DAMAGED"]},
                "Gas hose replacement", "Gas connection worn/damaged"),
            rec({"param": "ignition_condition", "op": "in", "value": ["DELAYED", "INTERMITTENT", "NOT_WORKING"]},
                "Ignition repair", "Ignition fault"),
            rec({"param": "burner_condition", "op": "in", "value": ["CLOGGED", "CORRODED"]},
                "Burner cleaning", "Burner clogged/corroded"),
            rec({"param": "burner_condition", "op": "eq", "value": "DAMAGED"}, "Burner replacement", "Burner damaged"),
            rec({"component": "flame", "below": 0.75}, "Flame adjustment", "Flame quality poor"),
            rec({"param": "cleaning_condition", "op": "in", "value": ["MODERATE", "DIRTY"]}, "Hob deep cleaning", "Cleaning"),
            rec({"param": "knob_condition", "op": "in", "value": ["LOOSE", "DAMAGED"]}, "Knob replacement", "Knobs"),
            rec({"param": "pan_support_condition", "op": "in", "value": ["UNSTABLE", "DAMAGED"]},
                "Pan support replacement", "Pan supports"),
        ],
    },
    # ----------------------------------------------------------- DISHWASHER
    "DISHWASHER": {
        "label": "Dishwasher",
        "id_prefix": "DW",
        "phase": 1,
        "base_service_interval_days": 120,
        "intensity_sensitive": False,
        "params": [
            enum("washing_performance", "Washing performance", {"GOOD": 1.0, "AVERAGE": 0.6, "POOR": 0.2}),
            enum("drainage_condition", "Drainage", {"GOOD": 1.0, "SLOW": 0.5, "BLOCKED": 0.0}, malfunction=["BLOCKED"]),
            num("drainage_time", "Drainage time", "min", required=False),
            enum("spray_arm_condition", "Spray arms", {"GOOD": 1.0, "PARTIALLY_BLOCKED": 0.55, "BLOCKED": 0.15, "DAMAGED": 0.1}),
            enum("filter_condition", "Filter", {"CLEAN": 1.0, "DIRTY": 0.55, "CLOGGED": 0.15, "DAMAGED": 0.1}),
            enum("inlet_condition", "Water inlet", {"GOOD": 1.0, "SLOW": 0.55, "BLOCKED": 0.0, "LEAKING": 0.2},
                 malfunction=["BLOCKED"]),
            enum("outlet_condition", "Water outlet hose", {"GOOD": 1.0, "KINKED": 0.5, "BLOCKED": 0.0, "LEAKING": 0.2}),
            enum("leakage_condition", "Leakage", {"NONE": 1.0, "MINOR": 0.6, "MAJOR": 0.1, "NEAR_ELECTRICAL": 0.0}),
            enum("drying_condition", "Drying", {"GOOD": 1.0, "PARTIAL": 0.6, "POOR": 0.2}),
            enum("door_seal", "Door seal", SEAL),
            enum("odour", "Odour", {"NONE": 1.0, "MILD": 0.6, "STRONG": 0.2}),
            enum("noise", "Noise / vibration", NOISE),
            text("error_codes", "Error codes shown"),
        ],
        "derived": [],
        "components": [
            comp("washing", "Washing Performance", 15, {"type": "enum", "params": ["washing_performance"]}, key_performance=True),
            comp("drainage", "Drainage", 15, {"type": "mixed", "scorers": [
                {"type": "enum", "params": ["drainage_condition"]},
                {"type": "band", "param": "drainage_time", "direction": "lower_better",
                 "bands": [[2, 1.0], [4, 0.75], [8, 0.4], [INF, 0.1]]},
            ]}, key_performance=True),
            comp("spray_arms", "Spray Arms", 10, {"type": "enum", "params": ["spray_arm_condition"]}),
            comp("filter", "Filter", 10, {"type": "enum", "params": ["filter_condition"]}),
            comp("inlet", "Water Inlet", 10, {"type": "enum", "params": ["inlet_condition", "outlet_condition"]}),
            comp("leakage", "Leakage", 10, {"type": "enum", "params": ["leakage_condition"]}),
            comp("drying", "Drying", 10, {"type": "enum", "params": ["drying_condition"]}),
            comp("door_seal", "Door Seal", 5, {"type": "enum", "params": ["door_seal"]}),
            comp("odour", "Odour", 5, {"type": "enum", "params": ["odour"]}),
            comp("noise", "Noise / Vibration", 5, {"type": "enum", "params": ["noise"]}),
            comp("service_history", "Service History", 5, SERVICE_HISTORY),
        ],
        "safety_rules": [
            rule("leakage_condition", "eq", "NEAR_ELECTRICAL", "CRITICAL", "Major water leakage near electrical components",
                 "Water is leaking near electrical parts. Switch off the dishwasher at the socket until it is repaired."),
            rule("leakage_condition", "eq", "MAJOR", "ATTENTION_REQUIRED", "Major water leakage", "Water leak needs repair."),
            rule("leakage_condition", "eq", "MINOR", "MONITOR", "Minor leakage", "Minor leak — keep an eye on it."),
        ],
        "recommendations": [
            rec({"param": "filter_condition", "op": "in", "value": ["DIRTY", "CLOGGED"]}, "Dishwasher filter cleaning", "Filter dirty"),
            rec({"param": "filter_condition", "op": "eq", "value": "DAMAGED"}, "Filter replacement", "Filter damaged"),
            rec({"component": "drainage", "below": 0.75}, "Drain pump & hose service", "Drainage slow/blocked"),
            rec({"param": "spray_arm_condition", "op": "in", "value": ["PARTIALLY_BLOCKED", "BLOCKED", "DAMAGED"]},
                "Spray arm cleaning", "Spray arms"),
            rec({"param": "leakage_condition", "op": "in", "value": ["MINOR", "MAJOR", "NEAR_ELECTRICAL"]},
                "Leak repair", "Leakage"),
            rec({"param": "door_seal", "op": "in", "value": ["WORN", "DAMAGED"]}, "Door seal replacement", "Door seal"),
            rec({"param": "odour", "op": "in", "value": ["MILD", "STRONG"]}, "Descaling & hygiene cycle", "Odour"),
            rec({"param": "error_codes", "op": "nonempty", "value": None}, "Error code diagnosis", "Error codes present"),
            rec({"component": "inlet", "below": 0.75}, "Water inlet / outlet hose service", "Inlet/outlet"),
        ],
    },
    # ----------------------------------------------------------- OVEN
    "OVEN": {
        "label": "Built-in Oven",
        "id_prefix": "OV",
        "phase": 1,
        "base_service_interval_days": 180,
        "intensity_sensitive": True,
        "params": [
            num("set_temperature", "Set temperature", "°C"),
            num("measured_temperature", "Measured temperature", "°C"),
            num("heating_time", "Time to reach set temperature", "min"),
            enum("element_condition", "Heating element", {"GOOD": 1.0, "WEAK": 0.5, "FAILED": 0.0}, malfunction=["FAILED"]),
            enum("fan_condition", "Fan", {"GOOD": 1.0, "NOISY": 0.6, "SLOW": 0.45, "FAILED": 0.0}, malfunction=["FAILED"]),
            enum("door_seal", "Door seal", SEAL),
            enum("electrical_condition", "Electrical condition", ELECTRICAL),
            enum("control_panel", "Control panel", {"GOOD": 1.0, "PARTIAL": 0.5, "FAULTY": 0.0}, malfunction=["FAULTY"]),
            enum("door_mechanism", "Door mechanism", {"GOOD": 1.0, "LOOSE": 0.55, "DAMAGED": 0.15}),
            enum("interior_condition", "Interior", {"GOOD": 1.0, "STAINED": 0.7, "RUSTED": 0.3, "DAMAGED": 0.1}),
            enum("cleaning_condition", "Cleaning condition", CLEAN3),
        ],
        "derived": ["temperature_difference", "temperature_overshoot"],
        "components": [
            comp("heating", "Heating Performance", 20, {"type": "band", "param": "heating_time", "direction": "lower_better",
                                                      "bands": [[10, 1.0], [15, 0.8], [20, 0.55], [30, 0.3], [INF, 0.1]]},
                 key_performance=True),
            comp("temperature", "Temperature Consistency", 15, {"type": "band", "param": "temperature_difference",
                                                              "direction": "lower_better",
                                                              "bands": [[5, 1.0], [10, 0.85], [20, 0.6], [35, 0.3], [INF, 0.05]]},
                 key_performance=True),
            comp("element", "Heating Element", 10, {"type": "enum", "params": ["element_condition"]}, key_performance=True),
            comp("fan", "Fan", 10, {"type": "enum", "params": ["fan_condition"]}),
            comp("door_seal", "Door Seal", 10, {"type": "enum", "params": ["door_seal"]}),
            comp("electrical", "Electrical Condition", 10, {"type": "enum", "params": ["electrical_condition"]}),
            comp("interior", "Interior Condition", 5, {"type": "enum", "params": ["interior_condition"]}),
            comp("control_panel", "Control Panel", 5, {"type": "enum", "params": ["control_panel"]}),
            comp("door_mechanism", "Door Mechanism", 5, {"type": "enum", "params": ["door_mechanism"]}),
            comp("cleaning", "Cleaning Condition", 5, {"type": "enum", "params": ["cleaning_condition"]}),
            comp("service_history", "Service History", 5, SERVICE_HISTORY),
        ],
        "safety_rules": [
            rule("electrical_condition", "eq", "EXPOSED_WIRING", "CRITICAL", "Exposed electrical wiring on oven",
                 "Exposed wiring was found on your oven. Do not use it until it is repaired."),
            rule("electrical_condition", "eq", "DAMAGED", "CRITICAL", "Severe electrical damage on oven",
                 "Severe electrical damage was found. Do not use the oven until it is repaired."),
            rule("temperature_overshoot", "gt", 40, "CRITICAL", "Dangerous overheating (> 40 °C above set point)",
                 "The oven overheats dangerously. Do not use it until the thermostat is repaired."),
            rule("temperature_overshoot", "gt", 25, "ATTENTION_REQUIRED", "Overheating (> 25 °C above set point)",
                 "The oven runs much hotter than set and needs repair."),
            rule("electrical_condition", "eq", "LOOSE_CONNECTION", "ATTENTION_REQUIRED", "Loose electrical connection",
                 "Electrical connection needs repair."),
            rule("door_mechanism", "eq", "DAMAGED", "MONITOR", "Door mechanism damaged (burn risk)", "Oven door needs repair."),
        ],
        "recommendations": [
            rec({"component": "temperature", "below": 0.85}, "Thermostat calibration", "Temperature deviation"),
            rec({"component": "heating", "below": 0.8}, "Heating performance check", "Slow heating"),
            rec({"param": "element_condition", "op": "in", "value": ["WEAK", "FAILED"]}, "Heating element replacement", "Element"),
            rec({"param": "fan_condition", "op": "in", "value": ["NOISY", "SLOW", "FAILED"]}, "Oven fan service", "Fan"),
            rec({"param": "door_seal", "op": "in", "value": ["WORN", "DAMAGED"]}, "Door gasket replacement", "Door seal"),
            rec({"param": "electrical_condition", "op": "in", "value": ["LOOSE_CONNECTION", "DAMAGED", "EXPOSED_WIRING"]},
                "Electrical repair", "Electrical"),
            rec({"param": "cleaning_condition", "op": "in", "value": ["MODERATE", "DIRTY"]}, "Oven deep cleaning", "Cleaning"),
            rec({"param": "control_panel", "op": "in", "value": ["PARTIAL", "FAULTY"]}, "Control panel repair", "Controls"),
        ],
    },
    # ----------------------------------------------------------- MICROWAVE (phase 2)
    "MICROWAVE": {
        "label": "Microwave",
        "id_prefix": "MW",
        "phase": 2,
        "base_service_interval_days": 180,
        "intensity_sensitive": False,
        "params": [
            enum("heating_performance", "Heating performance (water test)", {"GOOD": 1.0, "REDUCED": 0.55, "POOR": 0.2, "NO_HEAT": 0.0},
                 malfunction=["NO_HEAT"]),
            enum("heating_consistency", "Heating consistency", {"EVEN": 1.0, "SLIGHTLY_UNEVEN": 0.65, "UNEVEN": 0.3}),
            enum("turntable_condition", "Turntable", {"GOOD": 1.0, "SLOW": 0.6, "NOT_ROTATING": 0.1}),
            enum("door_latch", "Door / latch", {"GOOD": 1.0, "LOOSE": 0.4, "FAULTY": 0.0}),
            enum("door_seal", "Door seal", SEAL),
            enum("fan_condition", "Fan", {"GOOD": 1.0, "NOISY": 0.6, "FAILED": 0.0}),
            enum("interior_condition", "Interior", {"GOOD": 1.0, "STAINED": 0.7, "BURN_MARKS": 0.2, "DAMAGED": 0.1}),
            enum("control_panel", "Control panel", {"GOOD": 1.0, "PARTIAL": 0.5, "FAULTY": 0.0}, malfunction=["FAULTY"]),
            enum("noise", "Noise", NOISE),
            enum("electrical_condition", "Electrical safety", ELECTRICAL),
        ],
        "derived": [],
        "components": [
            comp("heating", "Heating Performance", 20, {"type": "enum", "params": ["heating_performance"]}, key_performance=True),
            comp("consistency", "Heating Consistency", 10, {"type": "enum", "params": ["heating_consistency"]}),
            comp("turntable", "Turntable", 5, {"type": "enum", "params": ["turntable_condition"]}),
            comp("door_latch", "Door / Latch", 15, {"type": "enum", "params": ["door_latch"]}),
            comp("door_seal", "Door Seal", 10, {"type": "enum", "params": ["door_seal"]}),
            comp("fan", "Fan", 5, {"type": "enum", "params": ["fan_condition"]}),
            comp("interior", "Interior Condition", 5, {"type": "enum", "params": ["interior_condition"]}),
            comp("control_panel", "Control Panel", 5, {"type": "enum", "params": ["control_panel"]}),
            comp("noise", "Noise", 5, {"type": "enum", "params": ["noise"]}),
            comp("electrical", "Electrical Safety", 15, {"type": "enum", "params": ["electrical_condition"]}),
            comp("service_history", "Service History", 5, SERVICE_HISTORY),
        ],
        "safety_rules": [
            rule("door_latch", "eq", "FAULTY", "CRITICAL", "Faulty door latch (possible microwave leakage)",
                 "The door latch is faulty. Do not use the microwave until it is repaired."),
            rule("door_seal", "eq", "DAMAGED", "ATTENTION_REQUIRED", "Damaged door seal", "Door seal needs replacement."),
            rule("electrical_condition", "in", ["EXPOSED_WIRING", "DAMAGED"], "CRITICAL", "Electrical hazard on microwave",
                 "An electrical hazard was found. Do not use the microwave until it is repaired."),
            rule("interior_condition", "eq", "BURN_MARKS", "ATTENTION_REQUIRED", "Arcing / burn marks inside cavity",
                 "Burn marks inside need inspection."),
        ],
        "recommendations": [
            rec({"component": "heating", "below": 0.6}, "Magnetron / heating check", "Heating"),
            rec({"param": "turntable_condition", "op": "in", "value": ["SLOW", "NOT_ROTATING"]}, "Turntable motor service", "Turntable"),
            rec({"param": "door_latch", "op": "in", "value": ["LOOSE", "FAULTY"]}, "Door latch repair", "Latch"),
            rec({"param": "door_seal", "op": "in", "value": ["WORN", "DAMAGED"]}, "Door seal replacement", "Seal"),
            rec({"param": "interior_condition", "op": "in", "value": ["BURN_MARKS", "DAMAGED"]}, "Waveguide cover replacement", "Interior"),
        ],
    },
    # ----------------------------------------------------------- REFRIGERATOR (phase 2)
    "REFRIGERATOR": {
        "label": "Refrigerator",
        "id_prefix": "RF",
        "phase": 2,
        "base_service_interval_days": 180,
        "intensity_sensitive": False,
        "params": [
            enum("cooling_performance", "Cooling performance", {"GOOD": 1.0, "REDUCED": 0.55, "POOR": 0.2, "NOT_COOLING": 0.0},
                 malfunction=["NOT_COOLING"]),
            num("measured_fridge_temperature", "Measured fridge compartment temperature", "°C"),
            enum("compressor_condition", "Compressor", {"NORMAL": 1.0, "NOISY": 0.6, "OVERHEATING": 0.2, "NOT_RUNNING": 0.0},
                 malfunction=["NOT_RUNNING"]),
            enum("fan_condition", "Fan", {"GOOD": 1.0, "NOISY": 0.6, "FAILED": 0.0}),
            enum("door_gasket", "Door gasket", SEAL),
            enum("frost_condition", "Frost / ice", {"NORMAL": 1.0, "EXCESS_FROST": 0.5, "ICE_BLOCKAGE": 0.15}),
            enum("drainage_condition", "Drainage", {"GOOD": 1.0, "SLOW": 0.5, "BLOCKED": 0.1}),
            enum("interior_condition", "Interior", COND3),
            enum("noise", "Noise / vibration", NOISE),
            enum("electrical_condition", "Electrical condition", ELECTRICAL),
        ],
        "derived": ["temperature_deviation"],
        "components": [
            comp("cooling", "Cooling Performance", 20, {"type": "enum", "params": ["cooling_performance"]}, key_performance=True),
            comp("stability", "Temperature Stability", 15, {"type": "band", "param": "temperature_deviation",
                                                          "direction": "lower_better",
                                                          "bands": [[1, 1.0], [2, 0.8], [4, 0.5], [7, 0.2], [INF, 0.05]]},
                 key_performance=True),
            comp("compressor", "Compressor", 15, {"type": "enum", "params": ["compressor_condition"]}, key_performance=True),
            comp("fan", "Fan", 5, {"type": "enum", "params": ["fan_condition"]}),
            comp("gasket", "Door Gasket", 10, {"type": "enum", "params": ["door_gasket"]}),
            comp("frost", "Frost / Ice", 5, {"type": "enum", "params": ["frost_condition"]}),
            comp("drainage", "Drainage", 5, {"type": "enum", "params": ["drainage_condition"]}),
            comp("interior", "Interior Condition", 5, {"type": "enum", "params": ["interior_condition"]}),
            comp("noise", "Noise / Vibration", 5, {"type": "enum", "params": ["noise"]}),
            comp("electrical", "Electrical Condition", 10, {"type": "enum", "params": ["electrical_condition"]}),
            comp("service_history", "Service History", 5, SERVICE_HISTORY),
        ],
        "safety_rules": [
            rule("electrical_condition", "in", ["EXPOSED_WIRING", "DAMAGED"], "CRITICAL", "Electrical hazard on refrigerator",
                 "An electrical hazard was found on your refrigerator. Please get it repaired immediately."),
            rule("compressor_condition", "eq", "OVERHEATING", "ATTENTION_REQUIRED", "Compressor overheating",
                 "Compressor is overheating."),
            rule("electrical_condition", "eq", "LOOSE_CONNECTION", "ATTENTION_REQUIRED", "Loose electrical connection",
                 "Electrical connection needs repair."),
        ],
        "recommendations": [
            rec({"component": "cooling", "below": 0.6}, "Cooling system diagnosis", "Cooling"),
            rec({"component": "stability", "below": 0.8}, "Thermostat check", "Temp deviation"),
            rec({"param": "door_gasket", "op": "in", "value": ["WORN", "DAMAGED"]}, "Door gasket replacement", "Gasket"),
            rec({"param": "frost_condition", "op": "in", "value": ["EXCESS_FROST", "ICE_BLOCKAGE"]}, "Defrost system service", "Frost"),
            rec({"param": "drainage_condition", "op": "in", "value": ["SLOW", "BLOCKED"]}, "Drain line cleaning", "Drainage"),
            rec({"param": "compressor_condition", "op": "in", "value": ["NOISY", "OVERHEATING", "NOT_RUNNING"]},
                "Compressor service", "Compressor"),
        ],
    },
}

DEFAULT_CONFIG = {
    "algorithm_version": 1,
    "categories": CATEGORIES,
    # 8. Score status — first band whose min the score is >= to.
    "score_thresholds": [
        {"min": 90, "status": "EXCELLENT", "label": "Excellent"},
        {"min": 80, "status": "HEALTHY", "label": "Healthy"},
        {"min": 70, "status": "MONITOR", "label": "Monitor"},
        {"min": 50, "status": "ATTENTION_REQUIRED", "label": "Attention Required"},
        {"min": 0, "status": "CRITICAL", "label": "Critical"},
    ],
    # 19. Service countdown — first band whose min days_remaining is >= to.
    "countdown_thresholds": [
        {"min": 31, "status": "NOT_DUE", "label": "Not Due", "color": "green"},
        {"min": 15, "status": "APPROACHING", "label": "Approaching", "color": "blue"},
        {"min": 1, "status": "DUE_SOON", "label": "Due Soon", "color": "orange"},
        {"min": 0, "status": "DUE", "label": "Due", "color": "red"},
        {"min": -INF, "status": "OVERDUE", "label": "Overdue", "color": "red"},
    ],
    # 21. Kitchen score weights (renormalised over the categories present).
    "kitchen_weights": {
        "CHIMNEY": 30, "HOB": 20, "DISHWASHER": 20, "OVEN": 15, "REFRIGERATOR": 15, "MICROWAVE": 10,
    },
    # 17. Service interval adjustment factors.
    "service_intervals": {
        "min_days": 7,
        "max_days": 365,
        "cooking_intensity_factor": {"LIGHT": 1.25, "MODERATE": 1.0, "HEAVY": 0.75},
        "daily_hours_threshold": 4,
        "daily_hours_factor": 0.9,
        "health_status_factor": {
            "EXCELLENT": 1.15, "HEALTHY": 1.0, "MONITOR": 0.85, "ATTENTION_REQUIRED": 0.6, "CRITICAL": 0.35,
        },
        "score_drop_threshold": 10,
        "score_drop_factor": 0.85,
        "repairs_12m_threshold": 2,
        "repairs_factor": 0.85,
        "age_years_threshold": 8,
        "age_factor": 0.9,
        "previous_interval_blend": 0.25,
        # Hard caps by repair priority (days). None = no cap.
        "priority_cap_days": {"EMERGENCY": 1, "HIGH": 7, "MEDIUM": 30, "LOW": 60, "PREVENTIVE": None, "MONITOR": None},
    },
    # 16. Repair priority rules (evaluated top-down; first match wins).
    "repair_priority": {
        "high_below_score": 50,
        "high_component_fraction": 0.2,       # key-performance component at/below this → HIGH
        "medium_below_score": 70,
        "medium_component_fraction": 0.75,    # key-performance component below this → MEDIUM
        "low_below_score": 80,
        "low_component_fraction": 0.5,        # any component below this → LOW
        "preventive_below_score": 90,
        "recommended_within_days": {"EMERGENCY": 1, "HIGH": 7, "MEDIUM": 30, "LOW": 60},
        "action_text": {
            "EMERGENCY": "Urgent safety repair required",
            "HIGH": "Repair required",
            "MEDIUM": "Service recommended",
            "LOW": "Minor repair recommended",
            "PREVENTIVE": "Preventive maintenance recommended",
            "MONITOR": "No action needed",
        },
    },
    # 15. Safety — global rules evaluated for every category in addition to
    # the per-category ones. Technician-defined findings are always added.
    "safety": {
        "levels": ["NORMAL", "MONITOR", "ATTENTION_REQUIRED", "CRITICAL"],
        "global_rules": [],
    },
    # Notification rules (phase 3 channels are recorded, not sent, until
    # a WhatsApp provider is configured).
    "notifications": {
        "on_safety_critical": ["app", "sms", "whatsapp"],
        "on_safety_attention": ["app"],
        "on_report_ready": ["app", "whatsapp"],
        "on_service_due_soon": ["app"],
    },
}
