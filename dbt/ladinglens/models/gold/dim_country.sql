-- Inline reference dim, not sourced from a seed: ~46 rows, hand-curated country
-- metadata (region, Section 232/301 target flags) that doesn't come from any
-- ingested table. Only 8 countries actually appear in silver_bol_shipments_scoped
-- (BE, CN, DE, ES, FR, GB, MX, VN, per Phase 3's EU-auto/Vietnam-apparel scope) --
-- the rest are context for the semantic layer / dim_country browsing.
--
-- is_section_232_target: TRUE for all steel/aluminum-tariffed countries as of the
-- Q3 2026 regime, FALSE for the five with negotiated quota exemptions (AR, AU, BR,
-- CA, MX). is_section_301_target: China only.
--
-- region groups on geographic/trade-bloc convenience (e.g. GB, CH, NO grouped with
-- 'EU' as "Europe" for analysis purposes), not strict EU membership.

select * from values
    ('US', 'United States',        'NORTH_AMERICA', true,  false, null),
    ('DE', 'Germany',              'EU',            true,  false, null),
    ('BE', 'Belgium',              'EU',            true,  false, null),
    ('VN', 'Vietnam',              'ASIA',          true,  false, null),
    ('ES', 'Spain',                'EU',            true,  false, null),
    ('GB', 'United Kingdom',       'EU',            true,  false, null),
    ('FR', 'France',               'EU',            true,  false, null),
    ('MX', 'Mexico',               'NORTH_AMERICA', false, false, 'Section 232 steel/aluminum quota exemption'),
    ('CN', 'China',                'ASIA',          true,  true,  'Section 301 tariff target'),
    ('CA', 'Canada',               'NORTH_AMERICA', false, false, 'Section 232 steel/aluminum quota exemption'),
    ('JP', 'Japan',                'ASIA',          true,  false, null),
    ('KR', 'South Korea',          'ASIA',          true,  false, null),
    ('TW', 'Taiwan',               'ASIA',          true,  false, null),
    ('IN', 'India',                'ASIA',          true,  false, null),
    ('TH', 'Thailand',             'ASIA',          true,  false, null),
    ('ID', 'Indonesia',            'ASIA',          true,  false, null),
    ('MY', 'Malaysia',             'ASIA',          true,  false, null),
    ('SG', 'Singapore',            'ASIA',          true,  false, null),
    ('PH', 'Philippines',          'ASIA',          true,  false, null),
    ('NL', 'Netherlands',          'EU',            true,  false, null),
    ('IT', 'Italy',                'EU',            true,  false, null),
    ('PL', 'Poland',               'EU',            true,  false, null),
    ('CZ', 'Czech Republic',       'EU',            true,  false, null),
    ('AT', 'Austria',              'EU',            true,  false, null),
    ('CH', 'Switzerland',          'EU',            true,  false, null),
    ('SE', 'Sweden',               'EU',            true,  false, null),
    ('DK', 'Denmark',              'EU',            true,  false, null),
    ('NO', 'Norway',               'EU',            true,  false, null),
    ('FI', 'Finland',              'EU',            true,  false, null),
    ('PT', 'Portugal',             'EU',            true,  false, null),
    ('TR', 'Turkey',               'MIDDLE_EAST',   true,  false, null),
    ('BR', 'Brazil',               'LATAM',         false, false, 'Section 232 steel/aluminum quota exemption'),
    ('AR', 'Argentina',            'LATAM',         false, false, 'Section 232 steel/aluminum quota exemption'),
    ('CL', 'Chile',                'LATAM',         true,  false, null),
    ('CO', 'Colombia',             'LATAM',         true,  false, null),
    ('AU', 'Australia',            'OCEANIA',       false, false, 'Section 232 steel/aluminum quota exemption'),
    ('HK', 'Hong Kong',            'ASIA',          true,  false, null),
    ('BH', 'Bahrain',              'MIDDLE_EAST',   true,  false, null),
    ('AE', 'United Arab Emirates', 'MIDDLE_EAST',   true,  false, null),
    ('QA', 'Qatar',                'MIDDLE_EAST',   true,  false, null),
    ('SA', 'Saudi Arabia',         'MIDDLE_EAST',   true,  false, null),
    ('KW', 'Kuwait',               'MIDDLE_EAST',   true,  false, null),
    ('LR', 'Liberia',              'AFRICA',        true,  false, 'Major flag-of-convenience shipping registry'),
    ('ZA', 'South Africa',         'AFRICA',        true,  false, null)
as t(country_code, country_name, region, is_section_232_target, is_section_301_target, notes)
