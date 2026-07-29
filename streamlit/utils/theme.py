"""Color palette and styling constants shared across all panels."""

# Color palette -- muted, professional, colorblind-safe
PRIMARY = "#2C5282"        # Deep blue
ACCENT = "#DD6B20"         # Warm orange for callouts
SUCCESS = "#38A169"        # Diversified/low-risk
WARNING = "#D69E2E"        # Moderate concentration
DANGER = "#C53030"         # High concentration/single-source
NEUTRAL_LIGHT = "#F7FAFC"
NEUTRAL_DARK = "#2D3748"

# HHI thresholds on this project's 0-1 fractional scale (mart_concentration_metrics
# convention, see Phase 6 wrap in data/sources.md) -- these are the standard
# DOJ/FTC 1500/2500 thresholds (on the conventional 0-10,000 HHI scale) scaled
# down by /10,000: 1500/10000 = 0.15, 2500/10000 = 0.25.
HHI_MODERATE = 0.15
HHI_HIGH = 0.25
SINGLE_SOURCE_THRESHOLD = 0.70  # matches mart_concentration_metrics.is_single_source

# HS chapter labels for user-facing display. Matches this project's actual
# scoped chapters (Phase 3/4) -- there is no HS chapter outside this set
# anywhere in fact_shipments.
HS_CHAPTER_LABELS = {
    "84": "Machinery",
    "87": "Vehicles",
    "39": "Plastics",
    "73": "Steel articles",
    "61": "Apparel (knit)",
    "62": "Apparel (woven)",
}

# Real distinct origin countries in fact_shipments (verified directly against
# the account before Phase 9 build -- the Phase 9 doc's draft list included
# "IT", which has zero shipments anywhere in this dataset and was dropped).
ORIGIN_COUNTRIES = ["BE", "CN", "DE", "ES", "FR", "GB", "MX", "VN"]
