# Owner checklist — self-hosted Renovate (GitHub Actions)

The Mend-hosted Renovate App is inert on this account (never ran a job). Renovate
now runs as a scheduled workflow in `dudziakm/dep-automation`. Presets are
unchanged: target repos still extend `github>dudziakm/dep-automation(:js|:jvm|:mixed|:automerge)`.

## 1. PAT (fine-grained) → Actions secret `RENOVATE_TOKEN`

Create a **fine-grained personal access token** (GitHub → Settings → Developer
settings → Personal access tokens → Fine-grained tokens):

| Setting | Value |
|---|---|
| Resource owner | `dudziakm` |
| Expiration | your choice (rotate before it expires) |
| Repository access | **Selected repositories** — every repo you want Renovate to manage, **excluding** the frozen list below. Do not grant the frozen repos. |

Repository permissions (minimum):

| Permission | Access |
|---|---|
| Contents | Read and write |
| Issues | Read and write |
| Pull requests | Read and write |
| Workflows | Read and write |
| Metadata | Read-only (always present) |

Account permissions: none required.

Add the token as a repository secret:

1. Open https://github.com/dudziakm/dep-automation/settings/secrets/actions
2. New repository secret → name **`RENOVATE_TOKEN`** → paste the PAT → Save

If the secret already exists under that exact name, skip this step.

## 2. First run

1. Open https://github.com/dudziakm/dep-automation/actions/workflows/renovate.yml
2. **Run workflow** → leave **dry_run = true** → Run
3. Open the run log. Confirm frozen repos are not processed (filter / skip lines).
4. Run again with **dry_run = false** (live). Expect Dependency Dashboard issues and/or Renovate PRs on pilots (`testPwSetup`, `nord-fjord-rag-guide`, …).

Scheduled runs (every 6 hours) are live, not dry-run. Logs: same Actions URL.

## 3. Optional — retire the Mend App

After a successful live run (dashboard or PR on a pilot): GitHub → Settings →
Applications → **Renovate** → Suspend or Uninstall. Self-hosted replaces it.

## Hard-excluded repos (never grant the PAT; runner also blocks them)

- `ai-concept-compass`
- `ai-concept-compass-greenfield`
- `10xCardsAstro`
- `my10xCards`
- `ai-rules-builder`

Enforced in `.github/renovate-global.js` (`autodiscoverFilter` + `packageRules`
deny) and in `EXCLUDED-REPOS.txt` / seeders. Do not flip `dep-automation` to
private until a live run has fetched the public presets successfully.
