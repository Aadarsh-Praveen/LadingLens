# LinkedIn Post Draft

Post the day after submission. ~200 words, matching the template in `docs/phases/phase-10-observability-and-demo.md` Step 9, updated with corrected metrics (5 panels, not 4; honest UDTF-fix phrasing per `docs/metrics.md`) and observability panel mention.

---

**COPY THIS INTO THE POST:**

```
Just shipped LadingLens — a tariff exposure and supplier concentration copilot built solo for a Snowflake hackathon.

The stack: a dbt medallion pipeline (Bronze → Silver → Gold) turning 3.8M US customs shipment records into 89,200 in-scope shipments, entity-resolved via Cortex embeddings, HS-classified via retrieval-augmented Cortex + Snowpark, exposed through a native Semantic View and Cortex Search over 24 SEC 10-K filings, and orchestrated by a Cortex Agent behind a 5-panel Streamlit UI (including live agent observability).

3 things I'm proud of:

[1] A naive SQL cross-join for HS classification retrieval never finished after 10+ hours. A vectorized Snowpark UDTF does the same job in 17 seconds.

[2] 40+ documented data-quality catches across the build, each with root cause analysis — including a dormant Bronze extraction bug that contaminated 13 of 24 indexed 10-K filings, only caught because downstream Cortex Search retrieval quality looked wrong.

[3] Agent fusion queries actually work: asking what a company discloses about tariffs and how that compares to its current supplier concentration correctly chains structured lookup + unstructured retrieval + scenario simulation into one answer.

GitHub: [URL]
Demo: [URL]

#Snowflake #Cortex #DataEngineering #AI
```

Word count: ~185 (within the ~200-word target).

**JUDGMENT CALL — please review:** I dropped the original template's hackathon-name reference ("Snowflake CoCo CLI Hackathon 2026") since I couldn't verify the exact official event name from anything in this repo — fill in the real name before posting if you want it named explicitly. Everything else is drawn directly from `docs/metrics.md` and `docs/roadmap.md`.
