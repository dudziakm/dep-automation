# Owner checklist — Renovate write access (manual)

Renovate is still silent as of 2026-08-19. Presets are public and reachable
(HTTP 200). The GitHub App is reported Enabled, but `renovate[bot]` has
`permission: none` on sampled repos and there are zero Dependency Dashboard
issues / zero `author:app/renovate` artefacts. This cannot be fixed from the
CLI — it needs an owner action in the GitHub / Mend UI.

## Do this once (order matters)

1. Open **https://github.com/settings/installations** → **Renovate**
   (Mend Renovate).
2. Under **Repository access**, choose **All repositories** (or explicitly
   select every in-scope repo — do **not** include the excluded list below
   unless you intentionally re-permit them).
3. Save.
4. Open **https://developer.mend.io/github/dudziakm** and confirm repos are
   listed with a last-run timestamp (not “Never run”).
5. Click **Re-run** on one pilot (`testPwSetup` or `nord-fjord-rag-guide`).
6. Within ~10–30 minutes expect either a Dependency Dashboard issue or a
   Renovate PR on that pilot.

## Hard-excluded repos (do not grant / do not re-seed)

- `ai-concept-compass`
- `ai-concept-compass-greenfield`
- `10xCardsAstro`
- `my10xCards`
- `ai-rules-builder`

## After Renovate wakes — quick proof

```bash
# Should become >0
gh api -X GET search/issues -f q='user:dudziakm author:app/renovate' --jq .total_count
gh api -X GET search/issues -f q='user:dudziakm is:issue in:title "Dependency Dashboard"' --jq .total_count

# Bot should no longer report permission:none
gh api repos/dudziakm/testPwSetup/collaborators/renovate%5Bbot%5D/permission --jq .permission
```

## Do not do yet

- Do **not** flip `dep-automation` to private until Renovate has successfully
  fetched `github>dudziakm/dep-automation:*` presets and opened real PRs.
  Privatizing breaks preset resolution unless a token/hostRules story is added.
