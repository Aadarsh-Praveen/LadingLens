-- Phase 8 smoke test: 10 end-to-end questions against LADINGLENS_AGENT via
-- SNOWFLAKE.CORTEX.DATA_AGENT_RUN. Walmart-centric questions (original doc's
-- Q2/Q4/Q6/Q7) swapped to Caterpillar per the documented Walmart data
-- limitation (see data/sources.md Phase 8 wrap) -- Walmart's real import
-- volume isn't resolvable from this dataset; every consignee matching
-- "WALMART"/"WAL-MART" tops out at 29 shipments (a third-party packaging
-- vendor shipping on Walmart's behalf, not Walmart's direct imports).
--
-- DATA_AGENT_RUN takes the agent name and a JSON string LITERAL (not
-- PARSE_JSON'd) with a `messages` array in the REST chat-completions shape.
-- In practice this is run via a Python driver (see the smoke-test execution
-- notes in data/sources.md) since building the escaped literal reliably in
-- raw SQL is impractical; the calls below show the equivalent shape.

-- Q1: "Which are the top 5 consignees by total landed cost?"                    [structured_only]
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "Which are the top 5 consignees by total landed cost?"}]}]}'
);

-- Q2: "What does Caterpillar disclose about tariff exposure in their 10-K?"     [retrieval_only]
-- Q3: "Which of Nike's suppliers are Vietnamese?"                               [structured_only]
-- Q4: "If Section 232 tariffs doubled, what would Caterpillar's exposure be?"   [structured + scenario]
-- Q5: "Which companies mention Section 301 risks in their 10-Ks?"              [retrieval_only]
-- Q6: "What's my total tariff exposure across all steel imports from Germany?" [structured_only]
-- Q7: "For Caterpillar, what happens if Chinese electronics tariffs rise 25 pp?" [structured + scenario]
-- Q8: "How diversified is Nike's supplier base for apparel?"                    [structured_only]
-- Q9: "What does Caterpillar disclose about supply chain risks and how does
--      that compare to their current supplier concentration?"                   [FUSION]
-- Q10: "Show me consignees single-sourced for HS chapter 87 and what their
--       10-Ks say about supplier concentration."                                [FUSION]
