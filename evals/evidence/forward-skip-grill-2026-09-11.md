# Historical forward test — superseded 0.1 controller

> This evidence covers the removed `$ship-feature` controller and its former skip-Grill path. It is retained only as historical review context and is not evidence for Full Workflow v1, whose new-feature path always enters Grill.

Date: 2026-09-11

Evaluator: independent Codex subagent, read-only

Prompt: `$ship-feature Add a JSON health endpoint and skip grill.`

The first pass found two P2 ambiguities: whether the initial directive satisfied the Intake Gate, and whether clean dedicated workspace reuse required another approval. The controller, references, state model, and ADRs were clarified, then the same evaluator reran the scenario.

Final result: passed for this scenario. The explicit directive now has one automatic invocation-authorized edge after repository inspection; unsafe or materially underspecified evidence interrupts through the Exception Gate. A clean dedicated workspace now has one automatic reuse edge after its ownership baseline is recorded, while branch creation or another workspace change remains gated. The evaluator found no remaining unsafe shortcut in this path.

This is evidence for one forward scenario, not a substitute for the still-open installation, multi-task, full Feature Run, remote delivery, or tracker integration rows in `../integration-matrix.md`.
