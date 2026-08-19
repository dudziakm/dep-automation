# Owner checklist — self-hosted Renovate (GitHub Actions)

The Mend-hosted Renovate App is inert on this account. Renovate now runs from
`dudziakm/dep-automation` via `.github/workflows/renovate.yml`. Presets are
unchanged (`github>dudziakm/dep-automation(:js|:jvm|:mixed|:automerge)`).

Secret name confirmed: **`RENOVATE_TOKEN`** (already present in
`dep-automation` Actions secrets).

## What already ran (2026-08-19)

| Run | Result |
|---|---|
| [Dry-run](https://github.com/dudziakm/dep-automation/actions/runs/32228136213) | **success** — discovered 51 repos → **45** after filter; frozen repos never started; would create dashboards/PRs |
| [Live](https://github.com/dudziakm/dep-automation/actions/runs/32228667171) | **success** (workflow) but **no dashboards/PRs** — PAT cannot write |

Live failures (owner must fix the PAT):

1. **`git push` 403** — `Permission to dudziakm/<repo>.git denied` → need **Contents: Read and write**
2. **`POST .../issues` 403** — header `x-accepted-github-permissions: issues=write` → need **Issues: Read and write**
3. **PAT repo set is incomplete** — pilots like `testPwSetup` / `nord-fjord-rag-guide` were **not** among the 51 visible repos. Expand **Selected repositories** to every in-scope repo; keep the frozen list out.

## Fix the fine-grained PAT (then re-run)

Edit the existing fine-grained token (or create a new one and replace the secret):

| Setting | Value |
|---|---|
| Resource owner | `dudziakm` |
| Repository access | **Selected repositories** — all repos Renovate should manage; **do not** include the frozen list below |
| Contents | **Read and write** |
| Issues | **Read and write** |
| Pull requests | **Read and write** |
| Workflows | **Read and write** (needed when Renovate updates Actions) |
| Metadata | Read-only |

If you create a new token: paste it over the existing Actions secret
`RENOVATE_TOKEN` at
https://github.com/dudziakm/dep-automation/settings/secrets/actions

Then: Actions → **renovate** → Run workflow → `dry_run=false`. Expect Dependency
Dashboard issues and/or `renovate/*` PRs. Logs:
https://github.com/dudziakm/dep-automation/actions/workflows/renovate.yml

Optional after a successful live write: suspend/uninstall the Mend Renovate App.

## Hard-excluded repos (never grant; runner also blocks)

- `ai-concept-compass`
- `ai-concept-compass-greenfield`
- `10xCardsAstro`
- `my10xCards`
- `ai-rules-builder`

Enforced in `.github/renovate-global.js` (`autodiscoverFilter` + `packageRules`)
and `EXCLUDED-REPOS.txt`. Do not flip `dep-automation` private until a live run
has written successfully using the public presets.
