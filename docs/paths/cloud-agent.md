# Work from here (Cursor Cloud Agent)

Run the whole project **through the agent** — you describe what you want; the agent runs commands in this environment.

**Default:** after changes, the agent **fixes CI until green** unless you say otherwise (see `.cursor/rules/ci-until-green.mdc`).

No own machine, no Codespaces tab, no manual `gh` clicks required.

## What works from here

| You say | Agent runs | Result |
|---------|------------|--------|
| "Check my changes" | `./scripts/from-here.sh check local` | kustomize + terraform validate locally |
| "Run the lab" | `./scripts/from-here.sh lab` | **Remote** Kind smoke in GitHub Actions (no Docker here) |
| "Push and open PR" | `./scripts/from-here.sh push` | `git push` + `gh pr create` |
| "What's CI status?" | `./scripts/from-here.sh status` | PR checks + recent workflow runs |
| "Edit X in gitops" | edits files → check → push | Full change loop |

## Why not a local kind cluster here?

This Cloud Agent VM has **no Docker**. Option A's interactive lab (`start-lab.sh`) needs Docker.

**Substitute:** `./scripts/from-here.sh lab` triggers **Kind smoke** on GitHub Actions — same bootstrap + verify scripts, ephemeral cluster, auto-deleted when done. You don't manage anything.

If you later use **Codespaces** (browser), `./scripts/start-lab.sh` runs the real interactive lab there.

## Daily workflow (recommended)

```text
1. You: "Add alert for cert expiry" (or any task)
2. Agent: edits files
3. Agent: ./scripts/from-here.sh check local
4. Agent: ./scripts/from-here.sh push
5. Agent: ./scripts/from-here.sh lab        # remote smoke if gitops changed
6. Agent: ./scripts/from-here.sh status     # wait for green
7. You: "Merge the PR" → agent merges
```

## CI monitor / fix loop (event-driven)

**Do not** poll Kind smoke for 90 minutes in chat. Use this instead:

| Event | Command | What happens |
|-------|---------|--------------|
| After push | *(automatic)* | GitHub Actions runs; PR gets a **comment on Kind smoke failure** |
| You want status | `./scripts/from-here.sh status` | One-shot check |
| Waiting for green | `./scripts/from-here.sh monitor` | Polls until pass/fail (max 120m) |
| CI failed | `./scripts/from-here.sh fix-ci` | Local validate + failed step + log tail |
| Agent fix loop | You: **"fix CI until green"** | Agent runs fix-ci → patch → push → repeat |

```text
push → fast checks (ci-validate) → Kind smoke in Actions
  → fail? PR comment with failed step
  → agent: fix-ci → edit → push → status/monitor
  → green → merge
```

## Commands reference

```bash
./scripts/from-here.sh check local          # fast — no cluster
./scripts/from-here.sh check remote         # trigger GitOps + Terraform workflows
./scripts/from-here.sh lab                  # Kind smoke on current branch (Actions)
./scripts/from-here.sh lab feat/my-branch   # Kind smoke on another branch
./scripts/from-here.sh status               # PR + workflow run status
./scripts/from-here.sh monitor              # poll until green or failure
./scripts/from-here.sh fix-ci               # diagnose Kind smoke failure
./scripts/from-here.sh push                 # push branch + create PR
./scripts/from-here.sh shutdown             # noop here; Actions runners are ephemeral
```

## Quota impact

| Action | Quota |
|--------|-------|
| `check local` | **Free** — runs in agent VM |
| `lab` (remote) | Uses **GitHub Actions minutes** (~15–30 min per run) |
| Codespaces | **Not used** when you work only through the agent |

See [quota-automation.md](../operations/quota-automation.md).

## Compared to Option A and B

| Path | Where | When to use |
|------|-------|-------------|
| **Cloud Agent (this doc)** | Cursor chat | Default — agent does everything |
| **Option A** | Codespaces | You want Argo CD UI / kubectl shell |
| **Option B** | GitHub PR + CI | Same as agent `push` + `check` — agent automates it |

## Authentication

The agent environment uses `gh` (GitHub CLI). If a command fails with auth errors, the repo owner may need to connect GitHub in Cursor settings.

## Related

- [getting-started.md](../start/getting-started.md)
- [ci-only.md](ci-only.md)
- [codespaces.md](codespaces.md)
