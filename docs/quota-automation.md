# Quota automation (Codespaces + GitHub Actions)

Automations to avoid burning free-tier quota on **Option A** (Codespaces) and **Option B** (CI).

## Option A — Codespaces (your lab)

### Built into this repo

| Automation | Setting | Effect |
|------------|---------|--------|
| **Idle shutdown** | `idleTimeout: 15` in `.devcontainer/devcontainer.json` | Codespace stops after **15 minutes** with no activity |
| **Max session length** | `openDuration: 120` | Codespace stops after **2 hours** even if active |
| **Cleanup on stop** | `postStopCommand` → `stop-cleanup.sh` | Deletes kind cluster + prunes Docker when the codespace stops |
| **Manual full shutdown** | `STOP_CODESPACE=true ./scripts/shutdown-lab.sh` | Destroys kind **and** stops the codespace |

### What you should do

```bash
# When finished for the day — one command
STOP_CODESPACE=true ./scripts/shutdown-lab.sh
```

Or click **Stop codespace** in the GitHub UI (cleanup still runs via `postStopCommand`).

### Check your quota

GitHub → **Settings** → **Billing and plans** → **Codespaces** → view usage.

Personal free tier: ~**120 core-hours/month** (4-core machine ≈ 30 wall-clock hours).

### Override timeouts (optional)

Edit `.devcontainer/devcontainer.json`:

```json
"codespaces": {
  "idleTimeout": 15,
  "openDuration": 120
}
```

Recreate the codespace for changes to apply.

---

## Option B — GitHub Actions (CI on PRs)

### Built into this repo

| Automation | Where | Effect |
|------------|-------|--------|
| **Ephemeral runners** | All workflows | VM destroyed when job ends — nothing stays running |
| **Job timeout** | `kind-smoke.yml` | Hard stop after **45 minutes** |
| **Cancel duplicate runs** | `concurrency` on workflows | New push cancels in-progress run for same PR |
| **Path filters** | Each workflow | Only runs when relevant files change |
| **Explicit kind delete** | `kind-smoke.yml` cleanup step | `kind delete cluster` even if job fails |

### What costs Actions minutes

| Workflow | When it runs | Typical duration |
|----------|--------------|------------------|
| `gitops.yml` | `gitops/**` changes | ~1–2 min |
| `terraform.yml` | `terraform/**` changes | ~3–5 min |
| `kind-smoke.yml` | `gitops/**` changes | ~15–30 min |
| `terraform-plan.yml` | AWS TF PRs (needs OIDC vars) | ~5 min |

**Kind smoke is the expensive one** — it only runs when GitOps files change.

### Reduce CI usage

- **Draft PRs** — open as draft while iterating; mark ready when you want full checks (optional habit)
- **Batch commits** — push once instead of many pushes (each push can re-trigger)
- **Avoid editing `gitops/**`** if you only change docs — kind-smoke won't run

### Check Actions usage

GitHub → **Settings** → **Billing** → **Actions** (public repos: usually unlimited minutes).

---

## Quick reference

```bash
# Start lab (Codespaces terminal)
./scripts/bootstrap-local.sh

# End lab + stop codespace (save quota)
STOP_CODESPACE=true ./scripts/shutdown-lab.sh

# End lab only (codespace keeps running — still uses quota!)
DESTROY=true ./scripts/bootstrap-local.sh
```

```text
Option A quota  →  Stopped by idle timeout + shutdown-lab.sh
Option B quota  →  Jobs auto-end; concurrency cancels duplicates
```

See also: [codespaces.md](codespaces.md) · [getting-started.md](getting-started.md)
