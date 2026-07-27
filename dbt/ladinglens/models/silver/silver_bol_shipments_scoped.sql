{{
    config(
        materialized='table'
    )
}}

-- The final analytical base for Phase 6+: silver_bol_shipments_classified
-- filtered to the target HS chapters, AFTER classification -- see
-- silver_bol_shipments.sql's header comment for why the HS-chapter filter
-- had to move here (Phase 5 refactor) instead of living in the
-- origin-country-scoped base table.
--
-- Excludes llm_unclassifiable (999999) rows deliberately: a chapter can't
-- be trusted from a code the classifier itself flagged as a refusal, even
-- though hs_2_final would technically evaluate to '99' for those rows and
-- never match the target chapter list anyway -- the explicit exclusion
-- makes that intent unambiguous rather than relying on a coincidence.

select *
from {{ ref('silver_bol_shipments_classified') }}
where hs_2_final in ('87', '84', '39', '61', '62', '73')
  and hs_code_unified is not null
  and hs_source_final != 'llm_unclassifiable'
