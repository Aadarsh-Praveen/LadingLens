{% macro is_freight_forwarder(name_col) %}
    (UPPER({{ name_col }}) LIKE '%DHL%' OR
     UPPER({{ name_col }}) LIKE '%SCHENKER%' OR
     UPPER({{ name_col }}) LIKE '%EXPEDITORS%' OR
     UPPER({{ name_col }}) LIKE '%YUSEN%' OR
     UPPER({{ name_col }}) LIKE '%MAERSK%' OR
     UPPER({{ name_col }}) LIKE '%PANALPINA%' OR
     UPPER({{ name_col }}) LIKE '%CEVA%' OR
     UPPER({{ name_col }}) LIKE '%KUEHNE%' OR
     UPPER({{ name_col }}) LIKE '%NAGEL%' OR
     UPPER({{ name_col }}) LIKE '%GEODIS%' OR
     UPPER({{ name_col }}) LIKE '%DSV%' OR
     UPPER({{ name_col }}) LIKE '%NIPPON EXPRESS%' OR
     UPPER({{ name_col }}) LIKE '%DAMCO%' OR
     UPPER({{ name_col }}) LIKE '%HELLMANN%' OR
     -- Ocean carriers/Ro-Ro lines added in Phase 4 Silver: act as
     -- consignee-of-record for consolidated/positioning cargo, not the true
     -- importer. Confirmed against Query 1's worst-case-consolidation
     -- spot-check (MSC/Hapag-Lloyd/OOCL dominating top-20 by container
     -- count) and the user's Ro-Ro carrier callout.
     UPPER({{ name_col }}) LIKE '%MITSUI OSK%' OR
     UPPER({{ name_col }}) LIKE '%MITSUI LINES%' OR
     UPPER({{ name_col }}) LIKE '%WWL%' OR
     UPPER({{ name_col }}) LIKE '%HYUNDAI GLOVIS%' OR
     UPPER({{ name_col }}) LIKE '%K LINE%' OR
     UPPER({{ name_col }}) LIKE '%KLINE%' OR
     UPPER({{ name_col }}) LIKE '%NYK%' OR
     UPPER({{ name_col }}) LIKE '%NIPPON YUSEN%' OR
     UPPER({{ name_col }}) LIKE '%MOL%' OR
     UPPER({{ name_col }}) LIKE '%OCEAN NETWORK EXPRESS%' OR
     UPPER({{ name_col }}) LIKE '%COSCO%' OR
     UPPER({{ name_col }}) LIKE '%HMM%' OR
     UPPER({{ name_col }}) LIKE '%CMA CGM%' OR
     UPPER({{ name_col }}) LIKE '%ZIM%' OR
     UPPER({{ name_col }}) LIKE '%ARC%' OR
     UPPER({{ name_col }}) LIKE '%KING OCEAN%' OR
     UPPER({{ name_col }}) LIKE '%HAPAG%' OR
     UPPER({{ name_col }}) LIKE '%UWL%' OR
     UPPER({{ name_col }}) LIKE '%EVERGREEN LINE%' OR
     UPPER({{ name_col }}) LIKE '%YANG MING%' OR
     UPPER({{ name_col }}) LIKE '%WAN HAI%' OR
     UPPER({{ name_col }}) LIKE '%PIL%' OR
     UPPER({{ name_col }}) LIKE '%APL%' OR
     UPPER({{ name_col }}) LIKE '%MSC%' OR
     UPPER({{ name_col }}) LIKE '%OOCL%')
{% endmacro %}
