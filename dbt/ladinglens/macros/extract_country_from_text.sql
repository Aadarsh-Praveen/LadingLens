{#
  extract_country_from_text: derives a country code from a PARTY'S
  REGISTERED ADDRESS only (address_col).

  Semantic scope: this answers "what country is this shipper/consignee
  entity registered/addressed in" -- appropriate for entity-resolution
  blocking (int_supplier_name_normalized / int_consignee_name_normalized),
  where the same real-world entity's name variants should share a country.

  Deliberately does NOT use port information. An earlier version fell back to
  foreign_port_of_lading when the address gave no signal, but that measures
  where cargo TRANSITS, not who the party IS -- verified in Phase 4 Silver
  that ~71-95% of ES/DE tags were port-fallback artifacts (e.g. Bahraini/UAE/
  Qatari/Liberian companies shipping via the Algeciras/Valencia
  transshipment hub, tagged 'ES' despite having no connection to Spain).

  For shipment ORIGIN country analysis (a different question), derive
  separately from foreign_port_of_lading in silver_bol_shipments.sql --
  do not reuse this macro for that purpose.

  IMPORTANT: Snowflake REGEXP_LIKE requires a FULL-STRING match by default.
  REGEXP_LIKE('foo bar US', 'US$') returns FALSE.
  REGEXP_LIKE('foo bar US', '.*US$') returns TRUE.
  Every pattern in this macro is prefixed with .* to enable substring/anchor
  matching. If you edit this macro, preserve the .* prefix on every
  REGEXP_LIKE pattern -- its absence silently turned the entire SECONDARY
  branch (and the first version of the US fallback) into dead code for
  several rounds of Phase 4 Silver before being caught.
#}
{% macro extract_country_from_text(address_col) %}
  COALESCE(
    -- PRIMARY: full country names (unambiguous)
    CASE
      WHEN UPPER({{ address_col }}) LIKE '%GERMANY%'         THEN 'DE'
      WHEN UPPER({{ address_col }}) LIKE '%BELGIUM%'         THEN 'BE'
      WHEN UPPER({{ address_col }}) LIKE '%VIETNAM%'         THEN 'VN'
      WHEN UPPER({{ address_col }}) LIKE '%CHINA%'
       AND UPPER({{ address_col }}) NOT LIKE '%MADE IN CHINA%'
       AND UPPER({{ address_col }}) NOT LIKE '%FROM CHINA%'  THEN 'CN'
      WHEN UPPER({{ address_col }}) LIKE '%HONG KONG%'       THEN 'HK'
      WHEN UPPER({{ address_col }}) LIKE '%TAIWAN%'          THEN 'TW'
      WHEN UPPER({{ address_col }}) LIKE '%MEXICO%'          THEN 'MX'
      WHEN UPPER({{ address_col }}) LIKE '%SPAIN%'
       AND UPPER({{ address_col }}) NOT LIKE '%PORT OF SPAIN%'
       AND UPPER({{ address_col }}) NOT LIKE '%PORT-OF-SPAIN%'
       AND UPPER({{ address_col }}) NOT LIKE '%TRINIDAD%'    THEN 'ES'
      WHEN UPPER({{ address_col }}) LIKE '%FRANCE%'          THEN 'FR'
      WHEN UPPER({{ address_col }}) LIKE '%UNITED KINGDOM%'
        OR UPPER({{ address_col }}) LIKE '%ENGLAND%'
        OR UPPER({{ address_col }}) LIKE '%SCOTLAND%'
        OR UPPER({{ address_col }}) LIKE '%WALES%'           THEN 'GB'
      WHEN UPPER({{ address_col }}) LIKE '%NETHERLANDS%'
        OR UPPER({{ address_col }}) LIKE '%HOLLAND%'         THEN 'NL'
      WHEN UPPER({{ address_col }}) LIKE '%ITALY%'           THEN 'IT'
      WHEN UPPER({{ address_col }}) LIKE '%JAPAN%'           THEN 'JP'
      WHEN UPPER({{ address_col }}) LIKE '%KOREA%'           THEN 'KR'
      WHEN UPPER({{ address_col }}) LIKE '%INDIA%'           THEN 'IN'
      WHEN UPPER({{ address_col }}) LIKE '%THAILAND%'        THEN 'TH'
      WHEN UPPER({{ address_col }}) LIKE '%INDONESIA%'       THEN 'ID'
      WHEN UPPER({{ address_col }}) LIKE '%MALAYSIA%'        THEN 'MY'
      WHEN UPPER({{ address_col }}) LIKE '%SINGAPORE%'       THEN 'SG'
      WHEN UPPER({{ address_col }}) LIKE '%PHILIPPINES%'     THEN 'PH'
      WHEN UPPER({{ address_col }}) LIKE '%BRAZIL%'          THEN 'BR'
      WHEN UPPER({{ address_col }}) LIKE '%ARGENTINA%'       THEN 'AR'
      WHEN UPPER({{ address_col }}) LIKE '%CHILE%'           THEN 'CL'
      WHEN UPPER({{ address_col }}) LIKE '%COLOMBIA%'        THEN 'CO'
      WHEN UPPER({{ address_col }}) LIKE '%POLAND%'          THEN 'PL'
      WHEN UPPER({{ address_col }}) LIKE '%CZECH%'           THEN 'CZ'
      WHEN UPPER({{ address_col }}) LIKE '%AUSTRIA%'         THEN 'AT'
      WHEN UPPER({{ address_col }}) LIKE '%SWITZERLAND%'     THEN 'CH'
      WHEN UPPER({{ address_col }}) LIKE '%SWEDEN%'          THEN 'SE'
      WHEN UPPER({{ address_col }}) LIKE '%DENMARK%'         THEN 'DK'
      WHEN UPPER({{ address_col }}) LIKE '%NORWAY%'          THEN 'NO'
      WHEN UPPER({{ address_col }}) LIKE '%FINLAND%'         THEN 'FI'
      WHEN UPPER({{ address_col }}) LIKE '%PORTUGAL%'        THEN 'PT'
      WHEN UPPER({{ address_col }}) LIKE '%TURKEY%'          THEN 'TR'
      WHEN UPPER({{ address_col }}) LIKE '%CANADA%'          THEN 'CA'
      WHEN UPPER({{ address_col }}) LIKE '%AUSTRALIA%'       THEN 'AU'
      WHEN UPPER({{ address_col }}) LIKE '%GEORGIA%'
        AND UPPER({{ address_col }}) NOT LIKE '%ATLANTA%'
        AND UPPER({{ address_col }}) NOT LIKE '%GA %'
        AND UPPER({{ address_col }}) NOT LIKE '%USA%'
        AND UPPER({{ address_col }}) NOT LIKE '%U.S.A%'      THEN 'GE'
      WHEN UPPER({{ address_col }}) LIKE '%BAHRAIN%'         THEN 'BH'
      WHEN UPPER({{ address_col }}) LIKE '%UNITED ARAB EMIRATES%'
        OR UPPER({{ address_col }}) LIKE '%DUBAI%'
        OR UPPER({{ address_col }}) LIKE '%ABU DHABI%'       THEN 'AE'
      WHEN UPPER({{ address_col }}) LIKE '%QATAR%'           THEN 'QA'
      WHEN UPPER({{ address_col }}) LIKE '%SAUDI%'           THEN 'SA'
      WHEN UPPER({{ address_col }}) LIKE '%KUWAIT%'          THEN 'KW'
      WHEN UPPER({{ address_col }}) LIKE '%LIBERIA%'         THEN 'LR'
      WHEN UPPER({{ address_col }}) LIKE '%SOUTH AFRICA%'    THEN 'ZA'
      WHEN UPPER({{ address_col }}) LIKE '%EGYPT%'           THEN 'EG'
      WHEN UPPER({{ address_col }}) LIKE '%NIGERIA%'         THEN 'NG'
      WHEN UPPER({{ address_col }}) LIKE '%RUSSIA%'          THEN 'RU'
      ELSE NULL
    END,

    -- SECONDARY: two-letter codes ONLY when clearly at end of address
    -- (comma or space then code, then optionally a postal code and end).
    CASE
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]DE[\\s,][- 0-9]{0,15}$') THEN 'DE'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]BE[\\s,][- 0-9]{0,15}$') THEN 'BE'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]VN[\\s,][- 0-9]{0,15}$') THEN 'VN'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]CN[\\s,][- 0-9]{0,15}$') THEN 'CN'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]ES[\\s,][- 0-9]{0,15}$') THEN 'ES'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]FR[\\s,][- 0-9]{0,15}$') THEN 'FR'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]MX[\\s,][- 0-9]{0,15}$') THEN 'MX'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]GB[\\s,][- 0-9]{0,15}$') THEN 'GB'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]NL[\\s,][- 0-9]{0,15}$') THEN 'NL'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]IT[\\s,][- 0-9]{0,15}$') THEN 'IT'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]JP[\\s,][- 0-9]{0,15}$') THEN 'JP'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[,\\s]KR[\\s,][- 0-9]{0,15}$') THEN 'KR'
      ELSE NULL
    END,

    -- TERTIARY: US fallback for domestic-format addresses (CBP AMS
    -- convention: US consignees omit "USA" from their address because it's
    -- implicit in an inbound-import filing). Handles four patterns:
    --   a1/a2. Explicit US/USA/UNITED STATES token, trailing-bare or interior
    --   b. State abbreviation + ZIP at/near end (US-only postal shape)
    --   c. Bare 5-digit ZIP at end (US-only among covered countries)
    -- Anchored with ^/$ throughout so "US" inside a company name (e.g.
    -- "SUSAN'S FOODS") can never false-positive -- only a genuine trailing
    -- token or a preceding space/comma/period counts.
    -- Deliberately last in the COALESCE so it never overrides an actual
    -- foreign-country match above.
    CASE
      -- a1. Trailing bare token at literal end of address
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*(^|[\\s,.])US\\s*$')
        THEN 'US'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*(^|[\\s,.])USA\\s*$')
        THEN 'US'
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*UNITED\\s+STATES\\s*$')
        THEN 'US'

      -- a2. Interior mentions
      WHEN UPPER({{ address_col }}) LIKE '%UNITED STATES %'
        OR UPPER({{ address_col }}) LIKE '% USA %'
        OR UPPER({{ address_col }}) LIKE '% USA,%'
        OR UPPER({{ address_col }}) LIKE '%U.S.A%'
        OR UPPER({{ address_col }}) LIKE '% US %'
        OR UPPER({{ address_col }}) LIKE '% US,%'
        THEN 'US'

      -- b. State abbreviation + ZIP anywhere near end, with or without a
      -- trailing US/USA token after the ZIP (e.g. "...SC 29715" or
      -- "...SC 29715 US" or "...SC 29715-1234"). All 50 states + DC.
      WHEN REGEXP_LIKE(UPPER({{ address_col }}),
           '.*[,\\s](A[LKZR]|C[AOT]|D[EC]|FL|GA|HI|I[DLNA]|K[SY]|LA|M[EDAIMNSO T]|N[EVHJMYCD]|OH|OK|OR|PA|RI|S[CD]|TN|TX|UT|V[TA]|W[AVIY])\\s+[0-9]{5}(-[0-9]{4})?(\\s+US[A]?)?\\s*$')
        THEN 'US'

      -- c. Bare 5-digit ZIP at end (only if no other country name/marker
      -- appears in the address -- Germany, France, Mexico, Turkey, Italy,
      -- and Spain all use 5-digit postal codes too. Mexico specifically was
      -- confirmed as a real false-positive source in Phase 4 Silver: 59
      -- consignees with clear Mexican address markers were tagged 'US'
      -- before these guards were added.)
      WHEN REGEXP_LIKE(UPPER({{ address_col }}), '.*[\\s,][0-9]{5}(-[0-9]{4})?\\s*$')
       AND UPPER({{ address_col }}) NOT LIKE '%GERMANY%'
       AND UPPER({{ address_col }}) NOT LIKE '%FRANCE%'
       AND UPPER({{ address_col }}) NOT LIKE '%MEXICO%'
       AND UPPER({{ address_col }}) NOT LIKE '% MX %'
       AND UPPER({{ address_col }}) NOT LIKE '%S.A. DE C.V%'
       AND UPPER({{ address_col }}) NOT LIKE '%S.A DE C.V%'
       AND UPPER({{ address_col }}) NOT LIKE '%COLONIA%'
       AND UPPER({{ address_col }}) NOT LIKE '%DELEGACION%'
       AND UPPER({{ address_col }}) NOT LIKE '%C.P. %'
       AND UPPER({{ address_col }}) NOT LIKE '%TURKEY%'
       AND UPPER({{ address_col }}) NOT LIKE '%ITALY%'
       AND UPPER({{ address_col }}) NOT LIKE '%SPAIN%'
        THEN 'US'

      ELSE NULL
    END
    -- No port-based branch. Port location != party registration.
  )
{% endmacro %}
