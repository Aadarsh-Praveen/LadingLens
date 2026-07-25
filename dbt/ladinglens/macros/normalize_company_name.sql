{% macro normalize_company_name(col) %}
    TRIM(
      LOWER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE({{ col }}, ',\\s+', ' ', 1, 0, 'i'),
                '\\b(inc|incorporated|corp|corporation|co|company|ltd|limited|llc|llp|gmbh|sarl|sa|sarl|bv|ag|kk|spa|srl|pty|plc|nv|as|oy|ab)\\b',
                '', 1, 0, 'i'),
              '[^a-z0-9 ]', '', 1, 0, 'i'),
            '\\s+', ' ', 1, 0, 'i'),
          '^the |^\\s+|\\s+$', '', 1, 0, 'i')
      )
    )
{% endmacro %}
