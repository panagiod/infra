# GitHub Project and backlog

How planning is tracked in this repository alongside PR-driven delivery.

## Layers

| Layer | Purpose |
|-------|---------|
| [project-status.md](project-status.md) | Narrative: scope, maturity path, lab vs production-proven |
| [`.github/project-backlog.json`](../../.github/project-backlog.json) | Machine-readable backlog (issues to open/close/update) |
| **GitHub Issues** | Actionable work items with labels |
| **GitHub Project** | Kanban view: Backlog → In progress → Done |
| **Pull requests** | How work ships; link with `Closes #N` in the PR body |

PRs remain the delivery engine. Issues and the Project board make **what’s next** visible without digging through chat history.

**Agents:** follow `.cursor/rules/github-project.mdc` — update the backlog in the same PR when work starts, finishes, or supersedes tracked issues.

## One-time setup (repo owner)

Run locally with the GitHub CLI as `panagiod` (not the Cursor bot):

```bash
gh auth refresh -s project,read:project
./scripts/setup-github-project.sh
```

That creates **infra — Phase 1**, links this repo, and adds open issues/PRs.

In the Project UI, use the default **Status** field: `Todo` → `In Progress` → `Done`. Optionally group by **Area** label.

## Sync backlog (automated)

After merging changes to `project-backlog.json`, either:

- Wait for the **Sync project backlog** workflow on `main`, or
- Run manually: **Actions → Sync project backlog → Run workflow**

The workflow will:

1. Close superseded issues (#14–#17) with explanatory comments
2. Refresh #18 (cloud staging soak)
3. Create/update roadmap issues (release, security hardening)

Labels sync similarly via **Sync labels** when `.github/labels.yml` changes.

Local dry run (needs a PAT with `repo` scope):

```bash
export GH_TOKEN="$(gh auth token)"
python3 scripts/sync-github-backlog.py
```

## Adding new roadmap items

1. Edit `.github/project-backlog.json` → add an entry under `upsert`
2. Merge to `main` (or run the workflow)
3. Re-run `./scripts/setup-github-project.sh` to add new issues to the board (or add manually in the UI)

For one-off bugs, use the **Task** issue template instead.

## PR hygiene

In every PR body:

```markdown
Closes #18
```

or `Relates to #18` when the PR does not fully complete the issue.

## Current backlog (after sync)

| Issue | Area | Summary |
|-------|------|---------|
| Cloud staging soak | cloud-soak | Bootstrap real staging, verify, destroy |
| First KubeShip production release | app | Semver tag via `release.yml` |
| Security hardening | security | Helm pins, API CIDRs, secret rotation |

Closed as superseded: separate app repo (#15), Argo registration (#16), generic backing services (#17) — all covered by KubeShip Phase 1 (PR #21).
