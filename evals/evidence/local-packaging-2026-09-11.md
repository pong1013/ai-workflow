# Local packaging evidence — 2026-09-11

Command:

```text
bash evals/run-local.sh
```

Expected and observed result:

```text
PASS clean temporary USER-scope copy
PASS repeat install stops on conflict
PASS installed source matches validated package
```

This proves only local package copying, conflict refusal, and source validation in a disposable directory. It does not prove GitHub installation, Codex restart discovery, agent behavior, tracker integrations, or delivery to a remote.
