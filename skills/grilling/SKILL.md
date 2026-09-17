---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask exactly one consequential decision question per user-facing reply, chosen from the frontier, and give your recommended answer. Then wait for the user's answer before asking another. Show the current question number, its prerequisite (or "none"), and any currently known queued decisions. Do not invent a final question count: answers can change the tree.

Format a round like so:

```
❓ **Q<n>** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

Prerequisite: <settled decision or none>
Known next decisions: <titles, or none>
```

Each answer reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and choose one next question. A question whose answer depends on an unsettled decision waits until that prerequisite is answered. The queued-decision list is context, not additional questions for the user to answer.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask one other ready question when available. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not implement the plan. When called by `$ai-workflow`, return the settled tree, unresolved decisions, and `complete` or `blocked` status without advancing the Feature Run.

## Provenance

Vendored from Matt Pocock's `grilling` at the commit recorded in [UPSTREAM.md](UPSTREAM.md), with a controller handoff added.
