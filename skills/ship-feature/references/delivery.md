# Delivery

Use this reference only after complete verification and independent review pass.

## Prepare the bundle

Read the Project Contract's delivery mode. Present one exact bundle containing:

- run-owned paths and, for files with pre-existing changes, exact hunks to stage;
- commit message;
- current and target branches;
- remote;
- whether the operation will commit, push, and create a pull or merge request;
- proposed request title and concise summary;
- verification and review evidence.

Always stop at the Delivery Gate and ask for explicit approval of the displayed bundle. For `none`, show an explicit no-Git bundle whose only result is the reviewed handoff; approval performs no stage, commit, push, or review-request operation.

Before showing the bundle, compare current status and diff with the Workspace Gate baseline and the latest reviewer post-verification check. Exclude unrelated paths and hunks. If a shared file cannot be staged without absorbing pre-existing work, keep the gate closed until ownership is safely separated.

## Execute only what was approved

After approval, revalidate status and diff, then perform only the displayed path- or hunk-scoped stage, commit, push, and pull/merge-request operations without routine confirmation between them. Stop and request a new decision if any target changes or if delivery encounters:

- an unknown or different remote;
- a protected or unexpected branch;
- a force operation;
- unrelated file changes;
- authentication or permission failure;
- a request to merge rather than merely create a review request;
- any action not shown in the approved bundle.

Do not infer broader authority from the original feature request or an earlier gate. Report the final commit and review-request URL only after the corresponding operations succeed.
