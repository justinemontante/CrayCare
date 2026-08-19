"""
CrayCare — Water Quality Agency Standards Reference
====================================================

All thresholds, class boundaries, and recommendation text in this system are
derived from the following official sources:

  DENR    — DENR Administrative Order 2016-08: Revised Water Quality Guidelines
             and General Effluent Standards of 2016 (Class C — Fishery Water Supply,
             Inland Waters for Propagation and Growth of Fish/Other Aquatic Resources)
  DA_BFAR — Department of Agriculture Bureau of Fisheries and Aquatic Resources:
             Aquaculture Water Quality Standards for Freshwater Species (Philippines)
  FAO     — FAO Fisheries Technical Paper 458 (Schmittou et al., 2001):
             "Water Quality for Pond Aquaculture"; FAO 2015 Aquaculture Guidelines
  WHO     — WHO Guidelines for Drinking-water Quality, 4th Edition (2011)
  BOYD    — Boyd, C.E. & Tucker, C.S. (1998): Pond Aquaculture Water Quality
             Management. Springer.
  HOLDICH — Holdich, D.M. (2002): Biology of Freshwater Crayfish. Blackwell Science.
             (Crayfish-specific physiological limits)

Applies to: freshwater crayfish aquaculture (Procambarus / Cherax spp.)
"""

# ── Agency full citations ──────────────────────────────────────────────────────

AGENCY_CITATIONS = {
    "DENR": (
        "DENR DAO 2016-08: Revised Water Quality Guidelines and General Effluent "
        "Standards of 2016 — Class C Inland Waters (Fishery Water Supply)"
    ),
    "DA_BFAR": (
        "DA-BFAR: Philippine National Standards for Freshwater Aquaculture Water "
        "Quality (Bureau of Fisheries and Aquatic Resources)"
    ),
    "FAO": (
        "FAO Fisheries Technical Paper 458 — Water Quality for Pond Aquaculture "
        "(Schmittou, Mischke & Liu, 2001); FAO Aquaculture Guidelines (2015)"
    ),
    "WHO": (
        "WHO Guidelines for Drinking-water Quality, 4th Edition (2011), "
        "World Health Organization, Geneva"
    ),
    "BOYD": (
        "Boyd, C.E. & Tucker, C.S. (1998): Pond Aquaculture Water Quality "
        "Management. Springer, Boston"
    ),
    "HOLDICH": (
        "Holdich, D.M. (2002): Biology of Freshwater Crayfish. Blackwell Science, Oxford"
    ),
}

# ── Per-parameter thresholds and agency links ──────────────────────────────────
# Each entry defines the boundary for Water Quality Assessment scoring and
# Water Quality Assessment condition-label generation.
# "direction": "lower_is_worse" | "higher_is_worse" | "range"
#
# Class mapping used in compute_water_quality_assessment_score() /
# generate_dataset.py:
#   0 — Good     (all parameters excellent / within optimal)
#   1 — Moderate (minor deviation; within "good" bounds)
#   2 — Poor     (approaching or at "fair" boundary)
#   3 — Critical (any parameter in "poor" or "critical" zone)

PARAM_STANDARDS = {
    # ── Dissolved Oxygen (mg/L) ───────────────────────────────────────────────
    "DO": {
        "label": "Dissolved Oxygen",
        "unit": "mg/L",
        "direction": "lower_is_worse",
        # Optimal: ≥5 mg/L   — DENR Class C; DA-BFAR; FAO pond guideline
        # Good:    ≥4 mg/L   — DA-BFAR minimum; Boyd & Tucker 1998 acceptable
        # Fair:    ≥3 mg/L   — Temporary stress, crayfish tolerate short exposure
        # Poor:    ≥2 mg/L   — Sub-lethal chronic stress (HOLDICH, FAO)
        # Critical: <2 mg/L  — Acute hypoxia, mass mortality risk
        "thresholds": {
            "optimal_min": 5.0,
            "good_min":    4.0,
            "fair_min":    3.0,
            "poor_min":    2.0,
        },
        "primary_agencies": ["DENR", "DA_BFAR", "FAO"],
        "denr_standard": "Class C Inland Waters: ≥5.0 mg/L",
        "bfar_standard": "Freshwater aquaculture: ≥5.0 mg/L (min 4.0 mg/L)",
        "fao_standard":  "FAO TP-458: ≥5 mg/L; ≥4 mg/L minimum for aquaculture ponds",
    },

    # ── pH ────────────────────────────────────────────────────────────────────
    "pH": {
        "label": "pH",
        "unit": "pH units",
        "direction": "range",
        # Optimal:  7.0–8.0  — FAO/HOLDICH crayfish physiological optimum
        # Good:     6.5–8.5  — DENR Class C; DA-BFAR freshwater aquaculture
        # Fair:     6.0–9.0  — DA-BFAR extended tolerance; Boyd & Tucker
        # Poor:     5.5–9.5  — Sublethal stress zone; molting affected (HOLDICH)
        # Critical: <5.5 or >9.5 — Acute injury / mortality
        "thresholds": {
            "optimal_min": 7.0, "optimal_max": 8.0,
            "good_min":    6.5, "good_max":    8.5,
            "fair_min":    6.0, "fair_max":    9.0,
            "poor_min":    5.5, "poor_max":    9.5,
        },
        "primary_agencies": ["DENR", "DA_BFAR", "FAO"],
        "denr_standard": "Class C Inland Waters: 6.5–8.5",
        "bfar_standard": "Freshwater aquaculture: 6.5–9.0",
        "fao_standard":  "FAO TP-458: 6.5–9.0; crayfish optimal 7.0–8.5",
    },

    # ── Temperature (°C) ─────────────────────────────────────────────────────
    "temp": {
        "label": "Water Temperature",
        "unit": "°C",
        "direction": "range",
        # Optimal:  24–28°C  — FAO / HOLDICH crayfish growth optimum
        # Good:     20–30°C  — DA-BFAR acceptable production range
        # Fair:     18–32°C  — Feeding depressed; suboptimal FCR
        # Poor:     15–35°C  — Significant physiological stress (HOLDICH)
        # Critical: <15 or >35°C — Near-lethal; mass mortality risk
        "thresholds": {
            "optimal_min": 24.0, "optimal_max": 28.0,
            "good_min":    20.0, "good_max":    30.0,
            "fair_min":    18.0, "fair_max":    32.0,
            "poor_min":    15.0, "poor_max":    35.0,
        },
        "primary_agencies": ["DA_BFAR", "FAO", "HOLDICH"],
        "denr_standard": "DA-BFAR: 20–30°C for freshwater aquaculture",
        "bfar_standard": "Freshwater aquaculture: 20–30°C",
        "fao_standard":  "FAO TP-458: 25–30°C optimal; crayfish tolerate 15–35°C",
    },

    # ── Turbidity (NTU) ───────────────────────────────────────────────────────
    "turbidity": {
        "label": "Turbidity",
        "unit": "NTU",
        "direction": "higher_is_worse",
        # Optimal:  <10 NTU  — FAO clear productive pond water
        # Good:     <25 NTU  — Acceptable for aquaculture (Boyd & Tucker)
        # Fair:     <50 NTU  — DENR Class C upper limit; moderate waste load
        # Poor:     <100 NTU — High suspended solids, oxygen demand elevated
        # Critical: ≥100 NTU — Extreme; gill damage risk; severe oxygen depletion
        "thresholds": {
            "optimal_max": 10.0,
            "good_max":    25.0,
            "fair_max":    50.0,
            "poor_max":    100.0,
        },
        "primary_agencies": ["DENR", "FAO", "BOYD"],
        "denr_standard": "Class C Inland Waters: ≤50 NTU",
        "bfar_standard": "Freshwater aquaculture: ≤50 NTU",
        "fao_standard":  "FAO TP-458: 25–40 cm Secchi depth (≈10–25 NTU optimal)",
    },

    # ── Water Level (cm) ─────────────────────────────────────────────────────
    "waterLevel": {
        "label": "Water Level",
        "unit": "cm",
        "direction": "range",
        # Tank-specific operating depth, not a universal agency numeric limit.
        # Ranges expand monotonically away from the configured 15–20 cm target.
        # FAO/Boyd support stable adequate depth; the exact centimetres come
        # from this CrayCare tank's physical design and HC-SR04 calibration.
        "thresholds": {
            "optimal_min": 15.0, "optimal_max": 20.0,
            "good_min":     12.5, "good_max":    22.5,
            "fair_min":     10.0, "fair_max":    25.0,
            "poor_min":      5.0, "poor_max":    30.0,
        },
        "primary_agencies": ["BOYD", "FAO"],
        "denr_standard": "FAO/Boyd: Maintain adequate depth for stocking density",
        "bfar_standard": "Maintain consistent water level per tank specification",
        "fao_standard":  "FAO: Stable depth reduces stress and territorial aggression in crayfish",
    },
}

# ── Per-parameter recommendation text (agency-cited) ──────────────────────────

RECOMMENDATIONS = {
    "DO": {
        "problem": "Low dissolved oxygen",
        "low_action": (
            "Increase aeration (add paddle wheels or air stones). "
            "Reduce feeding rate by 50% until DO recovers — decomposing feed depletes oxygen. "
            "Target ≥5.0 mg/L per DENR DAO 2016-08 Class C and DA-BFAR freshwater aquaculture standards."
        ),
        "critical_action": (
            "CRITICAL — Hypoxia risk: Activate emergency aeration immediately. "
            "Halt all feeding — organic load worsens oxygen depletion. "
            "Perform 30–50% water exchange with well-oxygenated source water. "
            "DENR DAO 2016-08 Class C mandates ≥5 mg/L; values below 2 mg/L cause "
            "acute mortality in crayfish (HOLDICH 2002; Boyd & Tucker 1998)."
        ),
        "agencies": "DENR DAO 2016-08 (Class C: ≥5 mg/L); DA-BFAR; Boyd & Tucker (1998); Holdich (2002)",
    },

    "pH": {
        "problem": "pH outside safe range",
        "low_action": (
            "pH is too low (acidic). Add agricultural lime (CaCO₃) or baking soda (NaHCO₃) "
            "in small doses (max 10 kg/ha·day) to raise pH gradually — avoid rapid shifts. "
            "DENR DAO 2016-08 Class C specifies 6.5–8.5; DA-BFAR freshwater aquaculture: 6.5–9.0. "
            "Low pH impairs crayfish molting and calcium uptake (Holdich 2002)."
        ),
        "high_action": (
            "pH is too high (alkaline). Perform 20–30% partial water exchange with neutral source water. "
            "Check for heavy algae bloom (photosynthesis drives pH up). "
            "DENR DAO 2016-08 Class C upper limit is 8.5; values above 9.5 cause "
            "ammonia toxicity amplification (FAO TP-458)."
        ),
        "critical_action": (
            "CRITICAL — pH shock risk: Perform immediate 30–40% water exchange. "
            "Do NOT add chemical buffer in large doses — sharp swings are as harmful as the deviation. "
            "DENR DAO 2016-08 Class C: 6.5–8.5. pH <5.5 or >9.5 can cause acute crayfish mortality "
            "within hours (Holdich 2002; Boyd & Tucker 1998). Test source water before adding."
        ),
        "agencies": "DENR DAO 2016-08 (Class C: 6.5–8.5); DA-BFAR (6.5–9.0); FAO TP-458; Holdich (2002)",
    },

    "temp": {
        "problem": "Water temperature out of safe range",
        "high_action": (
            "Temperature is too high. Add shade netting (50–70% shade) over the tank. "
            "Increase water exchange rate using cooler source water. Boost aeration — warm water "
            "holds less dissolved oxygen. Reduce feeding during heat spikes. "
            "DA-BFAR sets 20–30°C for freshwater species; above 32°C crayfish feeding and "
            "immune response are significantly impaired (Holdich 2002; FAO TP-458)."
        ),
        "low_action": (
            "Temperature is too low. Cover tanks to retain heat or add aquatic heaters. "
            "Increase feeding frequency with smaller portions — metabolism slows in cold water. "
            "DA-BFAR minimum is 20°C; below 15°C crayfish enter torpor and "
            "feeding ceases entirely (Holdich 2002)."
        ),
        "critical_action": (
            "CRITICAL — Thermal stress: Restore temperature immediately. "
            "For high temp: maximum water exchange + shade + emergency aeration. "
            "For low temp: insulate tank and add supplemental heating. "
            "DA-BFAR: 20–30°C operational range. Below 15°C or above 35°C risks "
            "rapid mortality — crayfish have narrow lethal temperature tolerance "
            "(Holdich 2002; Boyd & Tucker 1998; FAO TP-458)."
        ),
        "agencies": "DA-BFAR (20–30°C freshwater); FAO TP-458; Holdich (2002); Boyd & Tucker (1998)",
    },

    "turbidity": {
        "problem": "High turbidity (suspended solids / waste buildup)",
        "low_action": (
            "Turbidity is elevated. Reduce daily feed amount by 30% and remove uneaten feed. "
            "Perform a 20–30% partial water change. Check biofilter performance. "
            "DENR DAO 2016-08 Class C limit is 50 NTU; FAO recommends <25 NTU for "
            "productive aquaculture ponds (FAO TP-458)."
        ),
        "critical_action": (
            "CRITICAL — Severe turbidity: Perform 40–60% emergency water exchange immediately. "
            "Suspend all feeding for 24–48 hours. Clean filters and check aeration. "
            "High turbidity blocks oxygen exchange through water surface and causes "
            "gill irritation in crayfish. DENR DAO 2016-08 Class C: ≤50 NTU. "
            "Values above 100 NTU indicate severe organic overload (Boyd & Tucker 1998; FAO TP-458)."
        ),
        "agencies": "DENR DAO 2016-08 (Class C: ≤50 NTU); FAO TP-458 (optimal <25 NTU); Boyd & Tucker (1998)",
    },

    "waterLevel": {
        "problem": "Abnormal water level",
        "low_action": (
            "Water level is below optimal. Top up with clean, conditioned source water. "
            "Low water concentrates waste, raises stocking density stress, and reduces "
            "territorial space — increasing aggression and mortality in crayfish. "
            "FAO recommends stable water depth consistent with stocking rate (FAO TP-458; Boyd & Tucker 1998)."
        ),
        "high_action": (
            "Water level is above optimal. Open drain valves gradually to bring level into range. "
            "Overflow risk can introduce pathogens and cause stock loss. "
            "Maintain stable level per FAO/Boyd guidelines (Boyd & Tucker 1998)."
        ),
        "critical_action": (
            "CRITICAL — Water level emergency: Act immediately. "
            "Extremely low level risks gill exposure and mass mortality; extremely high level "
            "risks overflow and complete stock loss. Restore normal operating level as fast as safely possible. "
            "FAO TP-458 and Boyd & Tucker (1998) both emphasize stable water depth as a fundamental "
            "requirement for crayfish welfare."
        ),
        "agencies": "FAO TP-458; Boyd & Tucker (1998); DA-BFAR tank management guidelines",
    },
}
