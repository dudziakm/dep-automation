# Automerge proof plan

Opt-in automerge (`github>dudziakm/dep-automation:automerge`) is already
seeded into several verify-gated pilots. Real proof is **blocked** until
Renovate opens PRs (see `OWNER-RENOVATE-CHECKLIST.md`).

## Pilots with verify + automerge extends (in-scope)

| Repo | Notes |
|---|---|
| `testPwSetup` | Primary pilot |
| `nord-fjord-rag-guide` | Has `VERIFY_SMOKE=true` |
| `coachingDocs` | Has `VERIFY_SMOKE=true` |
| `web-ideas` | Automerge seeded |
| `code-reviewer` | Automerge seeded |
| `cypressTodo` | Automerge seeded |
| `CoachHomePage` | Automerge seeded |
| `todo_bmad` | Automerge seeded |

## Green-path proof (after Renovate wakes)

1. Wait for a Renovate PR that matches automerge rules (devDependency
   patch/minor, or runtime patch) on `testPwSetup` or `nord-fjord-rag-guide`.
2. Confirm the `verify` check runs and is green.
3. Confirm Renovate automerges the PR (`merged by renovate[bot]`).
4. Record the PR URL in the session progress file.

## Red-control A — PR that must NOT automerge

Open a manual PR on a gated+automerge repo that updates a package listed in
the automerge exclusions (e.g. `typescript`, `eslint`, or a major bump).

Expected: Renovate/manual PR stays open; no automerge.

Minimal recipe (after Renovate is live, or as a human PR):

```bash
# On a throwaway branch in testPwSetup: bump a matchPackageNames exclusion
# (e.g. typescript) by a patch, open PR, wait for verify green, confirm
# it is NOT auto-merged within the Renovate schedule window.
```

## Red-control B — repo with no checks must not get automerge

Do **not** add the `:automerge` extend to any repo that lacks `verify.yml`
(or another required check). Blind automerge on an unchecked repo would merge
on empty status. Seeding scripts and this plan treat “verify first” as a hard
precondition.

## Trigger when Renovate wakes

No extra GitHub Action is required. Once the App has write access and re-runs:

- Dependency Dashboard / first PRs appear automatically.
- Automerge applies on the next matching PR for repos that already extend
  `:automerge`.
- Re-check this file’s green-path steps and paste proof URLs into
  `SESSION-PROGRESS-*.md`.
