## Summary

<!-- What does this PR change and why? -->

## Tracking

<!-- Link issues so the Project board updates: Closes #N / Relates to #N -->
- **Issue(s):**

## Path

- [ ] **Option B (CI only)** — no cluster needed; CI validates on this PR
- [ ] **Option A (Codespaces lab)** — tested with `./scripts/start-lab.sh` in a codespace
- [ ] Docs / scripts only

## Checklist

- [ ] Branch name follows convention (`feat/`, `fix/`, `chore/`, `docs/`)
- [ ] Ran `./scripts/ci-validate.sh` locally (optional but recommended)
- [ ] If GitOps changed: expect **Kind smoke** (~15–30 min) on this PR
- [ ] If Codespaces lab was used: ran `STOP_CODESPACE=true ./scripts/shutdown-lab.sh` when done

## CI expectations

| Changed paths | Workflows that run |
|---------------|-------------------|
| `gitops/**` | GitOps manifests, Kind smoke |
| `terraform/**` | Terraform fmt + validate |
| `docs/**` only | Usually none (fast merge) |

Details: [docs/paths/ci-only.md](../docs/paths/ci-only.md)
