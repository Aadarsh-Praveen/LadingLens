"""Panel 4: Ask LadingLens -- conversational interface calling LADINGLENS_AGENT.

Latency-aware loading state is critical: Phase 8's smoke test measured p50 38s /
p95 93s for fusion queries. A frozen-looking UI for that long reads as broken.

Uses a background thread + polling progress bar to fake progress narrative,
since Cortex Agent has no native streaming via DATA_AGENT_RUN. If Snowpark
session reuse across threads misbehaves in the deployed SiS environment
(a real, known risk -- see Phase 9 doc Gotchas), this falls back to a plain
st.spinner with the same result correctness, just without the animated
narrative.
"""

import json
import threading
import time

import streamlit as st

from utils.snowflake_queries import run_agent_query, log_agent_trace

EXAMPLE_QUESTIONS = [
    "What does Caterpillar disclose about tariff exposure in their 10-K?",
    "Which consignees have the highest supplier concentration for HS chapter 84?",
    "If Section 232 tariffs doubled, what would BMW's exposure be?",
    "Which of Nike's suppliers are Vietnamese?",
    "For Caterpillar, what happens if Chinese electronics tariffs rise 25 pp?",
]

PROGRESS_TEXTS = [
    "Analyzing question...",
    "Selecting tools...",
    "Querying shipment data...",
    "Retrieving 10-K excerpts...",
    "Synthesizing answer...",
]


def _run_with_progress(question: str):
    """Runs the agent call in a background thread while animating a progress
    bar in the main thread. Falls back to a plain spinner if the thread
    approach raises (e.g. session-context issues)."""
    result = {"data": None, "error": None}

    def call_agent():
        try:
            result["data"] = run_agent_query(question)
        except Exception as exc:  # noqa: BLE001
            result["error"] = exc

    try:
        progress_placeholder = st.empty()
        with progress_placeholder.container():
            progress_bar = st.progress(0, text=PROGRESS_TEXTS[0])
            thread = threading.Thread(target=call_agent)
            thread.start()

            elapsed = 0
            while thread.is_alive() and elapsed < 120:
                time.sleep(2)
                elapsed += 2
                progress_val = min(int(elapsed / 90 * 100), 90)
                text_idx = min(int(elapsed / 20), len(PROGRESS_TEXTS) - 1)
                progress_bar.progress(progress_val, text=PROGRESS_TEXTS[text_idx])
            thread.join(timeout=5)
        progress_placeholder.empty()

        if result["error"] is not None:
            raise result["error"]
        if result["data"] is None:
            raise RuntimeError("Agent call did not complete within 120s.")
        return result["data"]

    except Exception:  # noqa: BLE001
        # Threading misbehaved (or timed out) -- fall back to a direct,
        # blocking call with a plain spinner. Same correctness, no narrative.
        with st.spinner("Analyzing question... this can take up to 90 seconds."):
            return run_agent_query(question)


def render():
    st.markdown("## Ask LadingLens")
    st.markdown(
        "Ask questions about supply chain concentration, tariff exposure, or "
        "10-K risk disclosures. The agent orchestrates structured queries, "
        "10-K retrieval, and tariff scenario simulation to answer. "
        "**Fusion questions (combining both) can take 40-90 seconds.**"
    )

    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []

    st.markdown("### Try an example question")
    cols = st.columns(len(EXAMPLE_QUESTIONS))
    for i, (col, question) in enumerate(zip(cols, EXAMPLE_QUESTIONS)):
        label = question if len(question) <= 40 else question[:37] + "..."
        if col.button(label, key=f"example_{i}"):
            st.session_state.pending_question = question

    st.markdown("### Conversation")
    for entry in st.session_state.chat_history:
        with st.chat_message(entry["role"]):
            st.markdown(entry["content"])
            if entry.get("tool_trace"):
                with st.expander("Tools used"):
                    for tool_call in entry["tool_trace"]:
                        st.code(f"{tool_call['tool_name']}({json.dumps(tool_call['arguments'])})")

    user_question = st.chat_input("Ask a question...")
    if "pending_question" in st.session_state:
        user_question = st.session_state.pending_question
        del st.session_state.pending_question

    if user_question:
        st.session_state.chat_history.append({"role": "user", "content": user_question})
        with st.chat_message("user"):
            st.markdown(user_question)

        t0 = time.time()
        response = _run_with_progress(user_question)
        total_latency_ms = int((time.time() - t0) * 1000)

        try:
            log_agent_trace(user_question, response, total_latency_ms)
        except Exception:  # noqa: BLE001
            pass  # observability logging must never break the chat UI

        st.session_state.chat_history.append(
            {
                "role": "assistant",
                "content": response["final_answer"],
                "tool_trace": response.get("tool_calls", []),
            }
        )
        st.rerun()
