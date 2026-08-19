# dep-automation

Central Renovate presets for `dudziakm` repositories. Every repo covered by
automation has a single-line `renovate.json`, the entire policy lives here.

The repo is **public** intentionally: Renovate must be able to fetch the preset via
`github>dudziakm/dep-automation`, and the presets do not contain any secrets.
## Presets

| File | Reference | For whom |
|---|---|---|
| `default.json` | `github>dudziakm/dep-automation` | Base. Not sufficient on its own — use the layer below. |
| `js.json` | `github>dudziakm/dep-automation:js` | JS/TS/Node repo |
| `jvm.json` | `github>dudziakm/dep-automation:jvm` | Maven/Gradle repo |
| `mixed.json` | `github>dudziakm/dep-automation:mixed` | Repo with JS **and** JVM manifests |
| `silent.json` | `github>dudziakm/dep-automation:silent` | Dormant repo: dashboard yes, PRs no |

`js.json`, `jvm.json` and `silent.json` extend `default.json` themselves, so the config
in the target repo is a single line:

```json
{ "extends": ["github>dudziakm/dep-automation:js"] }
```
## Phase 2 deliberately does not do automerge

In this phase, `automerge` is disabled **everywhere**. The goal is first to
see how many and what kind of PRs Renovate generates, and only then open the gates.
We will enable automerge per layer when the repo has a real CI gate.

Three settings determine whether automerge would be fail-closed, and all three
are explicitly set here in `default.json`:

- `platformAutomerge: false` — **this is an override, not the default value.** In the
  Renovate source, this option has `default: true`. By default, Renovate would delegate
  merging to GitHub, and without branch protection (unavailable for private repos on the
  Free plan) GitHub can merge a PR before tests start or even after their
  failure. Setting `false` moves the decision to Renovate, which itself checks
  the status of checks.
- `ignoreTests: false` — default, kept explicitly. `true` would merge without tests.
- `internalChecksAsSuccess: false` — default, kept explicitly. Prevents
  treating Renovate's own checks (e.g., `renovate/stability-days`) as
  green CI when the repo does not have any real workflow.

`minimumReleaseAgeBehaviour`, `internalChecksFilter`, and
`dependencyDashboardReportAbandonment` are also set to their default
values. This is deliberate: we record the intent so that a change in the default on the
Renovate side does not silently change our policy.
## Key decisions

**7-day quarantine (`minimumReleaseAge`).** The cheapest real defense against a
poisoned package. It does not protect the existing tree — `npm ci` does not perform
dependency re-resolution — only new resolutions, and that is the intended behavior.
Security patches bypass quarantine via the `vulnerabilityAlerts` block.

**We do not touch the `overrides` block** (`js.json`, `matchDepTypes: overrides`). It is
a manually written security policy, not a dependency. Renovate and Dependabot are not
tools for fixing transitive vulnerabilities and this should not be handed over to them.

**We do not touch dependencies managed by a BOM** (`jvm.json`). Renovate does not
run Maven, so it does not see that Maven will reset the version to the one from the BOM anyway.
A PR would be created that passes the build and at the same time lies about what will actually
be used.

**Cypress and Playwright in groups.** Plugins have narrow `peer` ranges for the runner
version. Having them diverge is exactly the class of error that we fixed manually
in `playwright-lum-project-cypress`.

**`osvVulnerabilityAlerts` is marked as experimental in Renovate.**
I am leaving it enabled because the OSV database is queried locally (no rate limits),
but treat this as a signal, not a guarantee, and expect behavior changes.

**`silent.json` does not use `mode: silent`.** The preset name is misleading and this is an intentional
compromise — the name remained, the behavior changed. `mode: silent` blocks not
only PRs and branches, but **also the creation of the Dependency Dashboard itself**, so
a repo in this mode is completely invisible. Verified by running:

```
INFO: Repository is running with mode=silent and will not make Issues or PRs by default
```

and in the same run, the `Would ensure Dependency Dashboard` line, which
Renovate prints for a repo in normal mode, was **missing**. Instead, we use
`dependencyDashboardApproval: true`: the dashboard is created and populated with the list of
updates, but no branch or PR is created until a human checks off an
item. The effect is what was intended — visibility at no cost.

Note on override precedence: `mode` from the preset wins over `RENOVATE_MODE` in
environment variables, so this cannot be bypassed from the command line.
## Pitfall: validator does not check remote presets

`renovate-config-validator` **does not fetch** presets specified by `github>`.
A config with an intentionally invalid `github>dudziakm/dep-automation:nie-ma-takiego`
passes as valid for it (verified). This means that renaming a preset file
would not be caught by validation, and would only fail on the bot,
in every repo at once.

Therefore, the workflow has a separate step checking references between presets across
files. Full, true preset resolution is only provided by running Renovate:

```bash
mkdir -p /tmp/rnvdry && cd /tmp/rnvdry
cat > config.js <<'EOF'
module.exports = {
  platform: 'github',
  repositories: ['dudziakm/testPwSetup'],
  extends: ['github>dudziakm/dep-automation:js'],
  requireConfig: 'optional',
  dryRun: 'extract',
};
EOF
RENOVATE_CONFIG_FILE=/tmp/rnvdry/config.js \
RENOVATE_TOKEN="$(gh auth token)" GITHUB_COM_TOKEN="$(gh auth token)" \
  npx --package renovate@latest renovate
```

An invalid name then produces `config-presets-invalid` and `Cannot find preset's
package`.
## Scripts

```bash
# Repo classification for preset. Outputs TSV to stdout.
./scripts/classify.sh > repos.tsv

# Seed renovate.json to target repos (PR on branch). Dry-run by default.
./scripts/seed.sh repos.tsv            # shows what it would do
APPLY=1 ./scripts/seed.sh repos.tsv    # actually creates PRs

# Merge seeded PRs from the chore/renovate-config branch.
./scripts/merge-seeded.sh repos.tsv

# JS repo shape detection (manager, build, typecheck, tsconfig, number of packages).
./scripts/shapes.sh repos.tsv

# Seed verify gate to active JS repos. Dry-run by default.
./scripts/seed-verify.sh repos.tsv            # shows what it would do
APPLY=1 ./scripts/seed-verify.sh repos.tsv    # actually creates PRs
ONLY=repoA,repoB APPLY=1 ./scripts/seed-verify.sh repos.tsv
```

`repos.tsv` in the repo is a snapshot of the classification, not a source of truth. Regenerate
it before any major scope change.

Every script that writes anything starts by comparing `gh api user` with
`OWNER` and aborts on mismatch. This is not excessive caution: on a
machine with multiple `gh` accounts, push goes through (git has its own credentials), and
only `gh pr create` ends with `must be a collaborator` — leaving pushed
branches without PRs.
## The verify gate and its real scope

`templates/verify-js.yml` is an automerge prerequisite: installation from lockfile,
`tsc --noEmit` when the repo has TypeScript in dependencies, `build` when such a
script exists. It deliberately **does not run E2E** — Playwright and Cypress suites in these
repos target external services, some of which no longer exist, and some block traffic
from data center IP addresses. As a gate, they would produce noise instead of proof.

The gate is confirmed by a control test, not just reasoning. In
`testPwSetup`, `@playwright/test` was replaced with the non-existent version `1.99.99`;
the workflow went red on the `Instalacja` step with `npm error code ETARGET`.
After reading the result, the branch and PR were deleted.

However, one must know the limits of this signal:

- **Repos without `build` and without TypeScript in dependencies get an
  install-only gate.** This applies to most test repos. `npm ci` still catches
  a non-existent version, an out-of-sync lockfile, a `peer` conflict, and conflicting
  `overrides` — but it will not catch behavioral regressions.
- **`tsc --noEmit` with `skipLibCheck: true` is weaker than it seems.**
  Verified on `web-ideas/projects/program-tv`: downgrading `next` from `^16.3.0` to
  `14` and `lucide-react` from `^0.525.0` to `0.100.0` passed both typecheck and
  build green.
- Therefore, the workflow ends with a step that outputs to the job summary
  which stages actually executed. A green install-only gate is meant to state
  this directly, instead of pretending to have full coverage.

Do not spread the gate wider than necessary: the repositories are private, so
Actions minutes are actually consumed. For the same reason, the workflow has no schedule —
it runs on PRs, on `push` to the default branch, and manually.
## Self-hosted Renovate (GitHub Actions)

The Mend-hosted Renovate App is **not** used on this account (it never executed
jobs). Renovate runs from [`.github/workflows/renovate.yml`](.github/workflows/renovate.yml)
in this repository, with discovery rules in
[`.github/renovate-global.js`](.github/renovate-global.js).

- Schedule: every 6 hours, plus `workflow_dispatch` (dry-run toggle, log level).
- Secret: `RENOVATE_TOKEN` (fine-grained PAT). See
  [`docs/OWNER-RENOVATE-CHECKLIST.md`](docs/OWNER-RENOVATE-CHECKLIST.md).
- Frozen repos are excluded in the runner config **and** in `EXCLUDED-REPOS.txt`.

Target repos still only need their one-line `renovate.json` extending these
presets; do not duplicate policy into the runner.

Checking whether Renovate has produced artefacts:

```bash
gh api -X GET search/issues -f q='user:dudziakm author:app/renovate' --jq .total_count
# Self-hosted commits as the PAT owner — also check:
gh api -X GET search/issues -f q='user:dudziakm "Dependency Dashboard" in:title' --jq .total_count
```

## Documentation and AI layer

- [`docs/OWNER-RENOVATE-CHECKLIST.md`](docs/OWNER-RENOVATE-CHECKLIST.md) — PAT secret, first run, optional Mend uninstall
- [`docs/AUTOMERGE-PROOF-PLAN.md`](docs/AUTOMERGE-PROOF-PLAN.md) — green-path and red-control plan once Renovate wakes
- [`docs/AUTOMATION-PLAN.md`](docs/AUTOMATION-PLAN.md) — full execution plan:
  measurements, corrections of earlier conclusions, rollout order. The previous
  Polish copy at `docs/PLAN-AUTOMATYZACJI.md` now redirects here.
- [`ai/`](ai/README.md) — AI provider layer for the Phase 7 agent that tries to
  fix a build broken by a dependency bump. **DeepSeek Flash by default**, DeepSeek
  Pro for escalation, OpenRouter as the first fallback, Kimi as the second.
  Gemini is not a provider in this layer: the free tier granted no access to the
  Pro model, and the paid tier was rejected. Gemini models remain reachable only
  through OpenRouter. Switching a provider is a change of three values in
  `ai/providers.json`, because every remaining vendor speaks the OpenAI protocol.
  The same document explains where keys live: a personal GitHub account has no
  user-level Actions secrets, so they sit in this one control repository.

The AI agent **is never a gate**: it can only propose a change, and whether anything makes it onto `main` is decided by deterministic CI checks and status evaluation by Renovate.
## Excluded repositories (hard rule, owner policy 2026-08-18)

The repositories listed in [`EXCLUDED-REPOS.txt`](EXCLUDED-REPOS.txt) are
permanently out of scope for dependency automation until the owner officially
re-permits them: no Renovate onboarding, no verify gate, no automerge, no
override or security PRs, no commits or merges.

This currently covers `ai-concept-compass`, `ai-concept-compass-greenfield`,
`10xCardsAstro`, `my10xCards`, `ai-rules-builder`, and the "10x devs" / "concept
AI" repositories in general. The exclusion is the owner's final decision after
an earlier temporary opt-in was reversed; a generic "do all repos" instruction
does not override it.
