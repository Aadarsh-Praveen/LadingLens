{% macro is_placeholder_name(col) %}
  (
    UPPER({{ col }}) LIKE '%UNKNOWN%'
    OR UPPER({{ col }}) LIKE '%TO ORDER%'
    OR UPPER({{ col }}) LIKE '%TO THE ORDER%'
    OR UPPER({{ col }}) LIKE '%OF ORDER%'
    OR UPPER({{ col }}) LIKE '%NOTIFY PARTY%'
    OR UPPER({{ col }}) LIKE '%NOT AVAILABLE%'
    OR UPPER({{ col }}) LIKE '%OF THE ORDER%'
    OR UPPER({{ col }}) = 'NA'
    OR UPPER({{ col }}) = 'N/A'
    OR UPPER({{ col }}) LIKE '%NULL%'
    OR UPPER({{ col }}) LIKE '%TBD%'
    OR UPPER({{ col }}) LIKE '%PENDING%'
    OR TRIM({{ col }}) = ''
    OR LENGTH(TRIM({{ col }})) < 3
  )
{% endmacro %}
