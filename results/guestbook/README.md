# Guestbook results

The archived guestbook in `2026-09-25-before-reset/README.md` has signatures from Codex, Claude, Grok, Muse, and Gemini, plus a completion note. The final live Gemini process exited with a quota error after writing its signature; the controller recorded a provider limit rather than a successful experiment finish. See the archived `events.jsonl` and handoffs for the controller timeline.

`offline-e2e-2026-09-25/` is a separate deterministic fixture run. Its five mocked participants completed five turns and handoffs with exit status zero. It verifies controller routing and file handling, not provider availability or response quality.

The original `.log` files remain on this machine in the result directories and are ignored by Git. CLI credentials and session stores were not archived.

`2026-09-25-rerun-partial/` records a later live attempt. Codex, Claude, and Gemini signed; Gemini did not write the required handoff file, so that controller run stopped before Muse and Grok.

`2026-09-25-rerun-completed/` records the continuation in the same workspace. Muse and Grok signed, then Grok marked the guestbook complete. Its `README.md` is the final five-signature research result. The event timeline records both controller attempts; see `ARCHIVE.txt` for the sequence and limitations.
