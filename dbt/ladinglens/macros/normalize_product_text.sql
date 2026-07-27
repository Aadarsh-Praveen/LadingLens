{#
  normalize_product_text: strips per-shipment metadata noise (PO numbers,
  style/SKU codes, reference/invoice/order numbers, embedded HS code
  fragments, ISO container IDs, weight/quantity tokens, bare 5+ digit
  reference numbers, UN dangerous-goods codes) from a BoL product
  description, then collapses punctuation and whitespace.

  This is the EXACT same chain originally built inline in
  int_product_text_universe.sql, extracted here so silver_bol_shipments_
  classified.sql can look up int_hs_classified.product_text without risking
  the two copies drifting apart. Order matters -- each step operates on the
  previous step's output, matching the original named-CTE chain exactly:
  upper -> strip_po -> strip_style -> strip_ref -> strip_hs ->
  strip_container -> strip_weight_qty -> strip_long_numbers ->
  strip_un_codes -> strip_punctuation -> collapse_whitespace -> trim.

  Returns the FULL normalized text, untruncated -- callers that need the
  200-char lookup key used for embedding/classification should wrap this in
  LEFT(normalize_product_text(col), 200).
#}
{% macro normalize_product_text(col) %}
trim(
  regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(
                    regexp_replace(
                      upper({{ col }}),
                      'PO[#: ]*[0-9]+', '', 1, 0, 'i'),
                    'STYLE[#: ]*[A-Z0-9-]+', '', 1, 0, 'i'),
                  '(REF|INVOICE|INV|ORDER)[#: ]*[A-Z0-9-]+', '', 1, 0, 'i'),
                'HS[- ]?CODE[: ]*[0-9]{4,10}', '', 1, 0, 'i'),
              '[A-Z]{4}[0-9]{7}', '', 1, 0, 'i'),
            '[0-9]+[.,]?[0-9]* ?(KG|KGS|LBS|MT|CBM|CTN|PLT|PKG|PCS|CTNS)', '', 1, 0, 'i'),
          '\\b[0-9]{5,}\\b', '', 1, 0, 'i'),
        'UN[ ]?[0-9]{4}', '', 1, 0, 'i'),
      '[^A-Z0-9 ]', ' ', 1, 0, 'i'),
    '\\s+', ' ', 1, 0, 'i')
)
{% endmacro %}
