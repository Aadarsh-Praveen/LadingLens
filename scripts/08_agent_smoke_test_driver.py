"""Runs the Phase 8 agent smoke test (see scripts/08_agent_smoke_test.sql for
the question list and context on the CAT/Walmart swap).

A Python driver is used rather than raw SQL because SNOWFLAKE.CORTEX.DATA_AGENT_RUN
takes its JSON payload as a literal string argument (not PARSE_JSON()'d -- the
function requires a compile-time constant), and reliably quote-escaping a
JSON blob containing arbitrary question text inside a SQL string literal is
impractical to do safely by hand.

Prints each question's latency, tool(s) invoked, any tool errors surfaced
along the way (the agent frequently self-corrects from these -- they don't
necessarily mean the final answer failed), and the synthesized final answer.
"""

import sys
import json
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ingest"))
from _snowflake_conn import connect  # noqa: E402

AGENT = "LADINGLENS_DB.SEMANTIC.LADINGLENS_AGENT"

QUESTIONS = [
    ("Q1", "Which are the top 5 consignees by total landed cost?"),
    ("Q2", "What does Caterpillar disclose about tariff exposure in their 10-K?"),
    ("Q3", "Which of Nike's suppliers are Vietnamese?"),
    ("Q4", "If Section 232 tariffs doubled, what would Caterpillar's exposure be?"),
    ("Q5", "Which companies mention Section 301 risks in their 10-Ks?"),
    ("Q6", "What's my total tariff exposure across all steel imports from Germany?"),
    ("Q7", "For Caterpillar, what happens if Chinese electronics tariffs rise 25 pp?"),
    ("Q8", "How diversified is Nike's supplier base for apparel?"),
    (
        "Q9",
        "What does Caterpillar disclose about supply chain risks and how does that compare to their current supplier concentration?",
    ),
    (
        "Q10",
        "Show me consignees single-sourced for HS chapter 87 and what their 10-Ks say about supplier concentration.",
    ),
]


def run_question(cur, question):
    payload = json.dumps(
        {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]}
    )
    t0 = time.time()
    cur.execute("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(%s, %s)", (AGENT, payload))
    raw = cur.fetchall()[0][0]
    elapsed = time.time() - t0
    data = json.loads(raw)

    tools_used, tool_errors, text_parts = [], [], []
    for block in data.get("content", []):
        t = block.get("type")
        if t == "tool_use" and block["tool_use"].get("name") not in (
            None,
            "system_execute_sql",
            "system_agentic_semantic_context",
        ):
            tools_used.append(block["tool_use"]["name"])
        elif t == "tool_result" and block["tool_result"].get("status") == "error":
            tool_errors.append(
                (
                    block["tool_result"].get("name"),
                    json.dumps(block["tool_result"].get("content"))[:200],
                )
            )
        elif t == "text":
            text_parts.append(block["text"])

    return elapsed, tools_used, tool_errors, "".join(text_parts).strip()


def main():
    conn = connect()
    cur = conn.cursor()
    latencies = []
    for label, question in QUESTIONS:
        elapsed, tools_used, tool_errors, answer = run_question(cur, question)
        latencies.append(elapsed)
        print(f"=== {label} ({elapsed:.1f}s) ===")
        print("Q:", question)
        print("Tools used:", tools_used or "(none surfaced / analyst-only)")
        if tool_errors:
            print("Tool errors (agent may have self-corrected):", tool_errors)
        print("Answer:", answer)
        print()

    latencies.sort()
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[min(len(latencies) - 1, int(len(latencies) * 0.95))]
    print(f"p50={p50:.1f}s p95={p95:.1f}s over {len(latencies)} questions")


if __name__ == "__main__":
    main()
