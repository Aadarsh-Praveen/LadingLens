{% macro generate_schema_name(custom_schema_name, node) -%}
    {#- Use the custom schema (bronze/silver/gold) as-is instead of dbt's
        default "<target_schema>_<custom_schema>" suffix behavior, since
        scripts/bootstrap_snowflake.sql already provisions BRONZE/SILVER/GOLD
        as top-level schemas in LADINGLENS_DB. -#}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
