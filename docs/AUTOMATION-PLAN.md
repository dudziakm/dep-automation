# Hands-free dependency automation — execution plan

> This document is an export of the interactive canvas `plan-automatyzacji-repo.canvas.tsx` to Markdown. Data state: 18.08.2026, export: 18.08.2026.

Account `dudziakm`, state as of 18.08.2026. The plan reflects your decisions: we stay on
GitHub Free, we fix the failing CI, we also cover archived repos, we exclude
10xDevs.

**Status summary:** ~79 repos in scope · 64 pending PRs · 13 PRs raised ·
4 repos genuinely broken, not 16 · 39 repos without CI · Free plan · Renovate as
gatekeeper · no GitHub Pro.

Data collected 2026-08-18 from the GitHub account `dudziakm` (REST + GraphQL), dry-run
Renovate 44.33.2 on `dudziakm/testBasketPw`, and analysis of logs from 14 failing
workflows. User decisions: Free plan, we fix CI, we also cover archived repos,
we exclude 10xDevs.

---
## What is already done — 13 PRs are waiting for you

Phases 1, 1b and 2 are complete, plus peer conflicts. Each PR has the reason,
change and verification in its description, so you can review them without
coming back to this conversation.

| Phase | Repo | PR | What it does |
|---|---|---|---|
| 1b | `testBasketPw` | #5 | removed js-yaml override, npm ci → 28 packages |
| 1b | `code-reviewer` | #11 | removed axios and js-yaml overrides, npm ci → 54 packages |
| 1b | `playwright-lum-project` | #5 | removed js-yaml override, npm ci → 32 packages |
| 1 | `testPwSetup` | #2 | upload-artifact v3→v4, plus checkout and setup-node to v4 |
| 1 | `testPwSetupEnv` | #2 | upload-artifact v3→v4, plus checkout and setup-node to v4 |
| 1 | `playwrightMacka` | #2 | upload-artifact v3→v4, then trigger moved to manual — the test target has disappeared |
| 1 | `globalsQA-banking` | #2 | restored `on:` blocks in two workflows |
| peer | `playwright-lum-project-cypress` | #25 | cucumber preprocessor 18→26, removed syntax error, cypress-on-fix for plugin conflict |
| peer | `coachingDocs` | #17 | migration to Tailwind 4 via `@tailwindcss/vite` — Astro 7 does not tolerate `@astrojs/tailwind` |
| 2 | `dep-automation` | #1 | cross-reference check between presets in CI — the validator does not check them |
| 2 | `testPwSetup` | #3 | `renovate.json` → js layer (pilot) |
| 2 | `etsyTests` | #2 | `renovate.json` → jvm layer (pilot) |
| 2 | `syringe` | #1 | `renovate.json` → silent layer (pilot) |

### CI result: workflow fix confirmed on live runs

`testPwSetup` and `testPwSetupEnv` — green. `globalsQA-banking` — green on
all three browsers, the first time since May 2025. These were not repos with
broken tests, only ones with a broken workflow installation.

`playwrightMacka` after the fix finally ran and revealed the real
fault: `automationpractice.pl` does respond with HTTP 200, but sends a 4.6 KB
"Redirecting…" page that contains not a single `login` — the shop these tests
walk through has disappeared. No selector change will recover it, so the trigger
was moved to `workflow_dispatch`: the tests remain, but the repo no longer hangs
on red and doesn't burn minutes.

### A side finding that changes the gateway design: some E2E suites cannot be a gateway

On the `testBasketPw` PR `npm ci` passes ("added 27 packages"), so the fix
works, but E2E fails waiting for the cookie banner. The cause is not on the
test side: `g2a.com` responds with **HTTP 403 "Access Denied"** in 365 bytes
to a client that is not a real browser. The GitHub runner exits from a data
centre address, so the banner never renders.

**Consequence for the plan: this repo must not be allowed as an automerge gateway.**
Its `npm ci` step is a reliable signal; the E2E step is not one at all. A suite
targeting a commercial service with anti-bot protection requires its own runner or
a different target — and until it has one, it is a source of noise, not evidence.

### One thing I did not touch, because it is your decision

`PicsImprove` was on the list as a "one-liner fix for a missing trigger".
I checked the file history and **the `on:` block was commented out intentionally** — the
commit from 05.12.2025 is explicitly called "Disable Netlify deployment workflow", the day
after a failed attempt to fix the Netlify CLI command.

Restoring the trigger would not fix the error, it would only reverse the decision:
every merge to `main` would deploy to production and write `OPENAI_API_KEY` and
`OPENROUTER_API_KEY` into the Netlify environment. The secrets are configured in
the repo, so it would work — and that is exactly why I did not do it without you.

---
## Most Urgent Finding: The Previous Round of Security Patches Broke CI

### First, a Correction to What I Wrote an Hour Ago

I wrote that six entries in `overrides` are holding vulnerable versions and called
that 41 vulnerabilities. **That impact assessment was wrong** — and wrong in the
right direction.
I checked the lockfile: in `nord-fjord-rag-guide`, five of those packages — `hono`,
`tar`, `postcss`, `picomatch`, `brace-expansion` — **are not in the dependency
tree at all**. Those overrides are dead. In `coachingDocs`, the `nanoid 3.3.17`
pin never applies, and the installed version is the already-patched 3.3.18.

None of those six is therefore a live vulnerability. What remains real: a dead
pin is a **delayed-fuse landmine** — it will take effect the day some dependency
pulls that package into the tree, and at that point it will silently install the
vulnerable version.

### Second Correction, Same Day: "16 Repos with a Drifted Lockfile" Was Also Wrong

The fact holds: in each of the 16 repos the `overrides` block is present in
`package.json`, and in `package-lock.json` there is none at all — zero entries,
in all sixteen. But **the conclusion I drew from that was wrong**. I assumed the
drift meant a broken `npm ci`, and I planned a fix for 16 repos.

Instead of inferring further from the file contents, I measured: clean HEAD,
discarded `node_modules`, `npm ci --dry-run` in each repo. **Four are actually
broken, not sixteen. Seven install without issue — drift and all.**

The mechanism I underestimated: npm compares not "whether overrides are recorded"
but "whether the tree from the lockfile differs from what the overrides enforce".
When a pin targets a version that is already in the tree anyway — or a package
that is not in the tree at all — there is no drift to report. That is why
`3rd-devs-my` with 27 overrides passes, while `playwright-lum-project` with two
does not.

### Measuring Instead of Inferring — Result per Repo

Definitive measurement, 18.08.2026, evening. For each repo: clean HEAD,
discarded `node_modules`, `npm ci --dry-run --ignore-scripts`. Without this
measurement I was inferring from file contents and got it wrong — see "Second
Correction" above.

| Repo | npm ci on clean HEAD | What the measurement showed |
|---|---|---|
| `playwright-lum-project` | broken | EUSAGE — js-yaml override duplicates a direct dependency |
| `coachingDocs` | broken | EUSAGE, but underneath it astro 7 vs @astrojs/tailwind peer ≤5 |
| `jit-old-cypress` | broken | ERESOLVE — cypress-real-events 1.7.6 requires cypress ≤12, repo has 15.18 |
| `playwright-lum-project-cypress` | broken | ERESOLVE — cucumber-preprocessor 18.0.6 requires cypress ≤13, repo has 15.18 |
| `3rd-devs-my` | passes | 27 overrides, 0 in lockfile — npm ci passes anyway |
| `nord-fjord-rag-guide` | passes | 17 overrides, 0 in lockfile — npm ci passes |
| `aidevsApiTasks` | passes | npm ci passes; only my relock failed, not the repo |
| `CoachHomePage` | passes | npm ci passes |
| `api_ai_tracker` | passes | npm ci passes |
| `cypressTodo` | passes | npm ci passes |
| `cypress-play` | passes | npm ci passes |
| `todo_bmad` | n/a | no `package-lock.json` — npm ci has nothing to verify |

The four broken repos fall into two different causes, not one. Only
`playwright-lum-project` responds to the pilot fix. The remaining three are
peer-dependency conflicts — a separate class of work: plugins need to be replaced,
not overrides removed.

### Overrides Entries Absent from the Lockfile

Overrides audit, 18.08.2026. All 16 repos with an `overrides` block checked via
the GitHub API; pins cross-referenced against OSV; causal chain and fix reproduced
locally on clones of `testBasketPw` and `code-reviewer`.

In the canvas this is a horizontal bar chart. Values (number of `overrides` entries
in `package.json`; the lockfile equivalent is zero for all entries):

| Repo | Entries in package.json |
|---|---|
| `3rd-devs-my` | 27 |
| `jit-old-cypress` | 29 |
| `nord-fjord-rag-guide` | 17 |
| `aidevsApiTasks` | 7 |
| `coachingDocs` | 6 |
| `playwright-lum-project-cypress` | 5 |
| remaining 10 repos | 13 |

Source: GitHub API, 18.08.2026. **This chart shows drift, not failure — after
measurement we know those are two different things.**

### Second Issue: The Lockfile Cannot Simply Be Recalculated

The obvious reflex is `npm install --package-lock-only`. I tried it — and it
fails with `EOVERRIDE`: "Override for js-yaml@^5.2.1 conflicts with direct
dependency".

The reason: some overrides target packages that are **also direct dependencies**,
with a different version specifier. npm does not accept this. So CI cannot
install, and the lockfile cannot be recalculated, until the collision is removed.

This is a deadlock, not a single error. That is why simply "bumping versions"
would not have moved it.

### The Fix — Verified on Three Repos, Not Inferred

An override for a package that is already a direct dependency is **redundant** —
you control its version directly in `dependencies`. Removing such entries lifts the
`EOVERRIDE`, allows the lockfile to be recalculated, and unblocks `npm ci`.

| Repo | Removed override | Before | After | What installs |
|---|---|---|---|---|
| `testBasketPw` | `js-yaml: 5.2.2` | npm ci → EUSAGE | npm ci → added 28 packages | js-yaml 5.2.3 — newer than the override wanted, clean in OSV |
| `code-reviewer` | `axios: ^1.18.0, js-yaml: 4.3.1` | npm ci → EUSAGE | npm ci → added 54 packages | axios 1.19.0 and js-yaml 4.3.1 — both clean in OSV |
| `playwright-lum-project` | `js-yaml: 5.2.2` | npm ci → EUSAGE | npm ci → added 32 packages | js-yaml 5.2.3 — newer than the override wanted, clean in OSV |

**The fix does not downgrade versions — I checked this separately.** In
`testBasketPw` and `playwright-lum-project` the override wanted `js-yaml 5.2.2`,
and after removal `5.2.3` installs — i.e. a newer version. In `code-reviewer`
`axios` comes out at `1.19.0`, `js-yaml` stays at `4.3.1`. Each of these versions
is clean in OSV. We lose nothing, and `npm ci` comes back to life.

### What I Consciously Did Not Do: Seven Cosmetic PRs

In the seven repos that pass `npm ci`, my script removed a few dead `overrides`
entries from each. I restored those files and did not open PRs. The OSV audit
showed that none of those pins is holding a vulnerable version, so the change
would provide neither a security benefit nor a functional one — only churn in
working code and seven PRs to review. The dead pins remain on record as
"delayed-fuse landmines" that will be caught by a standing check comparing
overrides against the lockfile.

### coachingDocs Is an Exception and Is Not a One-Liner

There, once the collision is removed, a real conflict surfaces: `@astrojs/tailwind 6.0.2` — which is
the **latest version** — declares `peer astro: ^3 || ^4 || ^5`, while the repo
is on `astro ^7.2.1`. This lockfile could only have been produced with
`--legacy-peer-deps` or `--force`.

The fix is a migration of the Tailwind integration to `@tailwindcss/vite` — hours,
not minutes. It therefore drops out of phase 1b and goes to a separate task.

### What from This Enters Policy Permanently

Two automerge vetoes, both owned by the diff rather than the version — so Renovate
cannot express them, and we implement them as a small required check reading
`git diff`: a PR touching the `overrides` block, and a PR whose lockfile introduces
a package name not previously present.

Plus one new check I had not planned before, which would have caught this entire
situation on the day it arose: **comparing `overrides` in `package.json` with what
is recorded in the lockfile**. One line of `jq`. It does not guard against
failure — because drift by itself does not cause failure, as I have just learned —
but it cuts off dead pins before one of them comes back to life.

---
## Good news: the Free plan does not require its own gatekeeper

I checked the Renovate source code and it turns out that **Renovate itself is the gate**
and does not need branch protection. The `getBranchStatus` function reads both the
combined status and check-runs, and merges only when the state is green. With
zero checks GitHub returns `pending`, which Renovate maps to yellow and
**refuses to merge**. Fail-closed by default.

This means we do not need to write hundreds of lines of YAML that would themselves become
a critical security component. The risk of the Free path drops from "medium" to
"low".

> **Correction:** I wrote earlier that three settings must "remain at their
> default, safe values". For `platformAutomerge` this was incorrect.
> I checked in the Renovate source — this option has **`default: true`**, meaning
> Renovate delegates merging to GitHub by default. This is precisely the path behind
> all documented fail-open incidents (#34967, #28601, #25750):
> GitHub's native auto-merge with zero required checks. Setting
> `platformAutomerge: false` is therefore an **override**, not the default behaviour,
> and must be recorded explicitly. `ignoreTests: false` and
> `internalChecksAsSuccess: false` are in fact defaults — we keep them explicit
> only as a record of intent.

---
## Four plan corrections after the JVM and JS/TS playbooks

### Pitfall: the grace period in npm would be a dummy for you

`min-release-age` requires npm ≥ 11.10.0, and older npm **silently ignores it**.
I checked eight of your workflows: **none of them pins npm**, and `setup-node`
gets node 18, 20 or 22 — all of which ship npm below 11.10.0.

Without one extra line the second grace-period layer does not exist, yet the config
looks like it does. That is the worst kind of safeguard.

The fix is `npm install -g npm@latest` after `setup-node`, plus
`engines.npm: ">=11.10.0"` as a safety belt. On top of that, `globalsQA-banking-VS`
is sitting on node 18, which is already past EOL.

### Simplifies: the entire Spring/OpenRewrite branch does not apply to you

I checked all 7 POMs: **zero Spring, zero BOMs, zero**
`dependencyManagement`. These are straightforward Selenium/TestNG projects.

This removes the most expensive element of the JVM playbook: Spring Boot 4
migrations, OpenRewrite recipes, and the distribution problem behind the Code
Genome Project authorisation wall. For your repos `mvn -B verify` is the full
gate, because without BOMs there is no "green build, wrong version" drift.

One thing remains as a decision: `mdm-selenium` declares Java 1.8. The current LTS
is 25. Migration is a separate task and never happens automatically.

### Saves minutes: 22 archived repos — silent mode instead of PRs

You wanted to cover archived repos — and there is a better setting for that than a
buildability probe: `"mode": "silent"`. Renovate tallies updates and populates the
Dependency Dashboard, but **creates no branches or PRs**.

You get full visibility into CVEs and abandoned packages at nearly zero Actions
minutes consumption, and if you ever return to one of the repos the dashboard is
already ready. This directly takes pressure off the 2,000-minute limit, which was
the biggest cost risk.

We add `abandonmentThreshold: "18 months"` — Renovate will flag packages that have
had no release for eighteen months. In repos from 2016–2019 that will be the most
interesting information, because it tells you where a future CVE will no longer
receive an upstream fix.

### Missing: three settings that were not in my config

| Setting | Why it is necessary for you |
|---|---|
| `rangeStrategy: "update-lockfile"` | Your package.json files use `^` ranges. Without this Renovate rewrites the range instead of touching the lockfile, and half the bumps are superficial. This is the setting that makes these repos automatable in the first place. |
| `playwright` group | 20 repos on Playwright. `@playwright/test`, `playwright`, `playwright-core` and the Docker image tag must move together, otherwise you get a browser version mismatch error instead of a test result. |
| `knip --include unlisted` | detects imports of packages not listed in package.json — exactly what breaks when a bump removes a transitive dependency you were unknowingly relying on. In Java the compiler catches this for free; in JS it does not. |

---
## Two gaps that cannot be closed with configuration

These are the only real risks remaining in this model. Both stem from the
Renovate algorithm, not from a bug, and both have the same solution.

| Gap | Mechanism | Effect |
|---|---|---|
| Check `skipped` or `neutral` counts as success | A workflow whose jobs are skipped via `if:` at the job level produces check-runs with a `skipped` result | the branch turns green and the PR merges without any real verification |
| A single green status from anything is enough | Renovate requires "at least one green check that is not `renovate/`", not "your tests passed" | a status from Netlify, Vercel, or Codecov alone authorises the merge |

**Solution: one minimal, always-running check.** Every repo in which we
enable automerge gets one workflow that **always executes and can never
be skipped**. Key point: no `if:` at the job level, because that
immediately opens gap number one.

This is simultaneously the gate that, for repos with E2E tests, replaces
running those tests — see the section below. And this same solution covers the 39
repos that currently have no workflow at all, meaning without it they will never
receive automerge.

---
## Scope after your decisions

Since you also want to include archived repos, the scope grows from 61 to ~79. The only
exclusions are forks of other people's projects and repos from 10xDevs.

| Measure | Value |
|---|---|
| Repos on account | 101 |
| In scope for automation | 79 |
| Forks — excluded | 16 |
| 10xDevs — excluded | 4 |
| Private among active | 44 |

| Group | Count | Treatment |
|---|---|---|
| Active, with build or tests | ~34 | full automerge patch+minor after adding the verify check |
| Active E2E tests on other people's sites | 27 | automerge on compilation gate, not on tests |
| Archived 2016–2019, included at your request | 22 | probe first — "does this even build" — then decide per repo |
| Forks of other people's projects | 16 | excluded — you don't maintain dependencies in them |
| 10xDevs and derivatives | 4 | `10xCardsAstro`, `my10xCards`, `ai-concept-compass`, `ai-concept-compass-greenfield` |

### Ecosystems across 61 active repos

| Ecosystem | Repo count |
|---|---|
| JS/TS (package.json) | 36 |
| No manifest | 11 |
| Java / Maven | 7 |
| Python | 6 |
| Gradle | 1 |
| .NET | 1 |

Source: file tree scan via GitHub API, 18.08.2026. `learnPython` counts in both
JS/TS and Gradle simultaneously.

### 64 open Dependabot PRs, per repo

| Repo | Open PRs |
|---|---|
| `web-ideas` | 15 |
| `learnPython` | 8 |
| `playwright-lum-project-cypress` | 7 |
| `mdm-cypress` | 6 |
| `rag-course-guide` | 3 |
| `nord-fjord-rag-guide` | 3 |
| `jit-old-cypress` | 3 |
| `cypress-play` | 3 |
| remaining 11 repos | 13 |

Source: GitHub search `is:open is:pr author:app/dependabot user:dudziakm`,
18.08.2026.

---
## CI Status After a Full Recount

### Second correction: the number matches, but the repo composition doesn't

I went through all 61 active repos and took the latest run **excluding
Dependabot workflows**. 14 are red — the same as in my first diagnosis, but
**partly different repos**.

Added: `coachingDocs`, `code-reviewer`, `testBasketPw`, `playwrightDevContainer`
and `fixerTests`. Dropped: those that managed to fix themselves. `coachingDocs` wasn't
on the first list, but has been red since 13.08 — that was a gap in my measurement.

| Metric | Value |
|---|---|
| Repos with red CI | 14 |
| Repos with green CI | 8 |
| Repos with NO CI runs at all | 39 |

**The most important number in this section is 39.** Only **22 out of 61** active repos
have any CI runs at all. The remaining 39 have no workflows whatsoever.
Renovate is fail-closed, so there **nothing will ever be merged automatically** there — and
rightly so, because there is nothing to check. This means that phase 3 of the plan, i.e. adding
a minimal `verify` check, is not a finishing touch at the end, but a prerequisite for
automation to cover more than one third of the repos.

| Repo | Cause | Effort |
|---|---|---|
| `code-reviewer` | npm ci → EUSAGE; overrides axios and js-yaml duplicate direct dependencies | checked, 2 min |
| `testBasketPw` | npm ci → EUSAGE; override js-yaml duplicates a direct dependency | checked, 2 min |
| `testPwSetup, testPwSetupEnv, playwrightMacka` | `actions/upload-artifact@v3` — GitHub fails the job in 4 seconds | PR raised |
| `PicsImprove` | `on:` block commented out INTENTIONALLY — commit "Disable Netlify deployment workflow", 05.12.2025 | do not touch — your decision |
| `globalsQA-banking` | missing `on:` key in playwright.yml and cross-browser.yml — removed by a web UI edit | PR raised |
| `jit-old-cypress, playwright-lum-project-cypress` | cypress 15.18, and plugins declare peer cypress ≤12 and ≤13 — lockfile with `--force` | plugin replacement, separate task |
| `coachingDocs` | npm ci → EUSAGE, but deeper: `@astrojs/tailwind 6.0.2` supports astro ≤5, and the repo is on astro 7 | hours — Tailwind migration |
| `fixerTests` | BUILD FAILURE, 1 expectation failed — a genuinely failing Java test | to be diagnosed |
| `playwrightDevContainer` | logs expired, cause undetermined | to be diagnosed |
| `tobaccoBasketPw, bingAiTests` | test sites that no longer exist | workflow_dispatch |
| `ai-concept-compass, 10xCardsAstro` | 10xDevs — out of scope | skip |

### Repair order — most repos unblocked per unit of effort

| Tier | Work | Unblocks | Time |
|---|---|---|---|
| 1 ✓ | `upload-artifact@v3` → `@v4`, the same diff three times | 3 repos; two returned to green, the third revealed a dead test target | done |
| 2 ✓ | remove redundant entries from `overrides` | code-reviewer, testBasketPw and playwright-lum-project — npm ci installs in each | done |
| 3 ✓ | add the missing `on:` key in two workflows | globalsQA-banking — done, green on 3 browsers; PicsImprove skipped because intentionally disabled | done |
| 4 | permanent check comparing `overrides` with lockfile | after measurement it is clear that drift does not break npm ci on its own — the check is to catch dead pins, not failures | comes with phase 3 |
| 5 | diagnose fixerTests and playwrightDevContainer | two unknown cases; fixerTests is the only genuinely failing test | hours |
| 6 | Tailwind migration in `coachingDocs` (astro 7) | the only real dependency work in this batch | hours |
| 7 | move tobaccoBasketPw and bingAiTests to `workflow_dispatch` | removes two permanently red repos from the board; rewriting buys nothing | ~5 min |

Note on your decision "we fix the tests for real": tiers 1–4 are genuine
fixes and worth doing. But `bingAiTests` tests the Bing Chat interface, which
Microsoft no longer exposes, and `tobaccoBasketPw` targets the rebuilt
ploom.co.uk. "Fixing" those means writing tests from scratch against a different
product and gives no signal about dependencies whatsoever.

---
## Verification gate per repo type

27 out of 61 active repos are E2E tests hitting third-party sites. Their result says
"someone changed their frontend", not "this package broke something". For them the gate is
**compilation, not execution**.

| Repo type | Gate | What it detects | Time |
|---|---|---|---|
| Playwright E2E (20 repos) | `npm ci && tsc --noEmit && npx playwright test --list` | API changes, removed exports, broken types, bad config | ~40 s |
| Cypress E2E (7 repos) | `npm ci && tsc --noEmit && cypress verify` | same plus binary consistency | ~60 s |
| JS/TS Application | `npm ci && tsc --noEmit && lint && build && test` | full verification — automerge fully justified | 1–4 min |
| Java / Maven (7 repos) | `mvn -B verify` | compilation and tests — full gate, because none of the measurements have BOMs | 2–6 min |
| Archived without build | no automerge, Dependency Dashboard only | nothing — automerge would be blind trust in the registry | — |

`playwright test --list` parses and compiles all specs and page objects,
but does not start the browser — hence the speed and determinism.

---
## Architecture

### Core: controller repo + centralized Renovate

One private `dep-automation` repo with its own GitHub App and
`renovatebot/github-action@v46.2.2` in a matrix: one job per repo, token
scoped to that one repo. Policy in a single preset, in every repo a four-line
`renovate.json` with `extends`.

App permissions: Checks, Commit statuses, Contents, Issues, Pull requests,
Workflows — all read+write; Administration and Dependabot alerts read;
Metadata read. Without Administration, Renovate will not detect allowed merge
methods.

Tested: dry-run of Renovate 44.33.2 on `testBasketPw` detected `npm` and
`github-actions` managers, would have generated 5 branches and a Dependency
Dashboard. Config passed `renovate-config-validator`.

### Fail-closed: key gate settings

| Setting | Value | Why |
|---|---|---|
| `platformAutomerge` | `false` | removes GitHub from the merge decision; the only gate is Renovate's status evaluation |
| `ignoreTests` | `false` | `true` would short-circuit the status evaluation to green before any API query |
| `internalChecksAsSuccess` | `false` | a green `renovate/stability-days` alone cannot turn the branch green |
| `automerge` at root | `false` | default-deny; automerge is granted exclusively by one explicit rule |
| `minimumReleaseAge` | `"7 days"` | malicious versions from 2025 lived hours, not weeks |
| `matchCurrentVersion` | `"!/^0/"` | pre-1.0 packages can break the API in a minor |

### Pitfall: known open bug that will affect this config

Issue #45236 (open, 12.08.2026): with any `minimumReleaseAge`,
updates of type `digest`, `pinDigest` and `lockFileMaintenance` receive the
`renovate/stability-days` check, which hangs **forever**, because these types
have no release timestamp. It blocks safely, but silently and permanently.

The workaround is included in the preset from day one:
`minimumReleaseAgeBehaviour: "timestamp-optional"` in a rule matched to those
three types.

### Security: layers protecting against a malicious package

| Control | Configuration | Role |
|---|---|---|
| Grace period in Renovate | `minimumReleaseAge: "7 days"` | no PR is created until the version has served its time |
| Grace period in package manager | `min-release-age=7` | Renovate preset zeroes out the grace period for lockFileMaintenance and pin — this needs to be underlined |
| Install script blocking | `allowScripts` | npm 12 blocks by default; this stops the payload itself |
| Pinning actions to SHA | `helpers:pinGitHubActionDigests` | a moved tag is no longer a silent change |
| Workflow audit | `zizmor` | template injection, excessive permissions |
| Nightly scan of pins in overrides | `api.osv.dev/v1/querybatch` | the only control that catches an override which itself holds a vulnerable version — Dependabot does not see this |

**We never auto-merge** majors, pre-1.0 packages, security PRs,
Docker images, `lockFileMaintenance`, or anything that touches `.github/`. Renovate
enforces security PRs via `force` and they bypass all limits —
which is why they always go to a human.

### AI: agent, only when the build fails

The agent does not open PRs with version bumps — that is what Renovate does,
more cheaply and deterministically. The agent steps in only when a bump **has
broken the build**. Framework: `github/gh-aw` with `engine: gemini`, because
the agent is read-only by default there in a sandbox, with an egress firewall
and a separate job for threat detection.

**Three rules without which this is dangerous:**

1. `persist-credentials: false` in the checkout. It was via exactly that path
   (`.git/config`) that researchers exfiltrated a token from Google's Gemini CLI
   workflow and gained push access to main.
2. Separated permissions: the agent job has `contents: read` and delivers the
   patch as an artifact; a separate job with an App token applies it.
3. PRs written by the agent **never** auto-merge. Your primary risk is not a
   malicious collaborator, but a poisoned package changelog that the agent will
   read as an instruction.

---
## How quickly the backlog of 64 PRs will disappear

Renovate merges at most two branches per repo per run — after the
first merge it breaks the loop and retries the job once. Each merge
puts the remaining branches behind the base, so they are rebased, get
a new commit, and are skipped in that run.

| Factor | Impact |
|---|---|
| Merge ceiling | 2 per repo per Renovate run |
| Realistic drain time for 64 PRs | 1.5–2 days when running every hour |
| `prConcurrentLimit`, `prHourlyLimit` | do not help — they limit creation, not merging; raising them only grows the backlog |
| What actually helps | more frequent runs (every 15–30 min) and a low `branchConcurrentLimit` (3–5) |
| `rebaseWhen: "conflicted"` | do not use as a shortcut — may merge two changes never tested together |

---
## Costs

| Item | Monthly | Notes |
|---|---|---|
| GitHub | $0.00 | staying on Free — Renovate is the gateway, Pro not needed |
| Renovate | $0.00 | self-hosted, AGPL, no repo limit |
| Gemini API — triage and fixes | $2–6 | agent fires only on broken builds, Flash models |
| OpenRouter — escalations | $1–3 | optional, a few difficult cases |
| Actions minutes | $0.00 | with 79 repos ~900–1,100 of 2,000 in the limit; to be monitored |
| zizmor, OSV-Scanner, Trivy | $0.00 | open source |

| Metric | Value |
|---|---|
| Actual monthly cost | $3–9 |
| Estimated Actions minutes / 2,000 | ~750 |

**Correction: the minutes limit has stopped being a bottleneck.** Previously I estimated
~1,100 of 2,000 minutes and called it a real constraint. Moving 22 archived repos
to `mode: "silent"` removes their entire pool from the calculation — no branches,
no PRs, and no CI runs are created there. That leaves **~700–800 minutes**,
with a comfortable margin.

Two conditions unchanged: gates must be fast (`--list` instead of full
tests), and the control repo stays private so that Renovate logs don't publicly expose
the names and dependencies of your 44 private repos.

> Export note: this condition was later changed — the `dep-automation`
> repo is public so that Renovate can fetch presets. See the "Phase 2" section
> below, where the decision is described explicitly.

---
## Phase 2 done: policy lives in one repo

A public repo [dudziakm/dep-automation](https://github.com/dudziakm/dep-automation)
has been created with five presets. Each target repo gets a one-line `renovate.json`,
so 53 repos won't drift apart configuration-wise. Public by design: Renovate must
be able to fetch the preset, and presets contain no secrets.

### Classification of 102 repos — by script, not by eye

| Group | Count | What we do with it |
|---|---|---|
| js — active | 33 | js preset |
| jvm — active | 6 | jvm preset |
| mixed (JS + JVM) | 1 | mixed preset — learnPython |
| dormant >12 months | 13 | silent preset: dashboard yes, PRs no |
| forks of others' repos | 16 | skipped, Renovate skips them anyway |
| other ecosystem (Python, C#) | 11 | out of scope, but they have manifests |
| without manifests | 17 | nothing to update |
| excluded / empty | 4 | 10x and derivatives, 2 empty repos |

53 repos enter automation. The script `scripts/classify.sh` is repeatable —
the classification is a snapshot, not the source of truth.

### Config behaviour measured, not assumed

I ran a real Renovate dry-run against four repos, one from each
layer. The numbers below are the bot's plan, not my estimates.

| Repo | Layer | What it detected | What it would create |
|---|---|---|---|
| `testPwSetup` | js | 7 dependencies / 2 files | 2 branches, including renovate/playwright |
| `etsyTests` | jvm | 13 dependencies / 1 file | 10 branches — worst case |
| `coachingDocs` | js | 18 dependencies / 2 files | 0 branches — everything on hold |
| `syringe` | silent | 8 dependencies / 1 file | 0 branches, dashboard only |

Three things were confirmed: grouping works (Playwright instead of three
separate PRs), silent mode genuinely creates no branches, and in `coachingDocs`
updates exist but are held back by dashboard approval and a stabilisation delay —
exactly as designed. The log also confirms that the brakes
`prConcurrentLimit: 3` and `prHourlyLimit: 2` actually engage, so even
`etsyTests` with ten branches won't flood you with PRs.

### A trap I fell into — and one worth knowing about

I validated the presets with `renovate-config-validator` and assumed that references
between them were checked. They weren't. **The validator does not fetch presets referenced
via `github>`** — a config with a deliberately wrong name `:no-such-preset` passes it
as valid. I verified this with a control test.

This means that renaming a preset file passes validation, but blows up only at the
bot — immediately across all connected repos. That is why the control repo's CI has
a separate step that checks references against files, and the real preset-resolution
test is done via a Renovate dry-run. There, a wrong name produces
`config-presets-invalid`.

### The only step I cannot do for you

Installing the Renovate app requires OAuth in a browser:
[github.com/apps/renovate](https://github.com/apps/renovate). Order matters —
**merge the config PRs first, then install**. Renovate detects an existing
`renovate.json` and skips onboarding; without it you will get onboarding with a
bare `config:recommended`, meaning none of this policy.

Confirmed by dry-run: on a repo without a merged config, Renovate explicitly says "Would
create onboarding PR".

> Export note: this step has already been completed by you — the Renovate
> app is installed and connected.

### By design: zero automerge in this phase

Automerge is disabled in all five presets. First we want to see how many PRs and
what kind the bot generates in production, and open the gates only where CI
actually checks something meaningful. This is the content of Phases 3 and 4.

---
## Deployment Order

| Phase | Scope | Effect | Risk |
|---|---|---|---|
| 1 ✓ | upload-artifact v3→v4 in 3 repos, restored `on:` in globalsQA-banking | 4 repos stop being permanently red; PicsImprove intentionally skipped | done — 4 PRs raised |
| 1b ✓ | Remove redundant entries from `overrides` — actual scope 3 repos, not 16 | unblocks npm ci in testBasketPw, code-reviewer and playwright-lum-project | done — 3 PRs, each verified locally |
| 2 ✓ | Steering repo with 5 presets, classification of 102 repos, 3 pilots seeded | policy in one place; manual GitHub App installation remains | done — 4 PRs; behaviour measured by dry-run |
| 3 | Minimal `verify` workflow in all repos covered by automerge | closes the skipped/neutral gap and provides a real gate | low |
| 4 | Automerge patch+minor on pilots, one week of observation | first truly hands-off merges | medium — we watch this carefully |
| 5 | Buildability probe of 22 archived repos, then a per-repo decision | we know which of the 2016–2019 ones can be automated at all | low — the probe is read-only |
| 6 | Rollout to all 79 repos, draining 64 outstanding PRs | backlog disappears on its own in 1.5–2 days | medium |
| 7 | gh-aw agent + Gemini for failing builds | self-healing bumps; agent's PR always up for review | requires hardening from the AI section |

**Why CI fixes are phase one and not last.** You chose to fix the
tests, and that is the right order: as long as a repo is permanently red, automerge
will never fire, so all the rest of the infrastructure has nothing to watch over there.
Tiers 1–4 are about an hour of work and unblock six repos.

---
## AI Provider Strategy (added 18.08.2026, outside the canvas)

This section does not come from the canvas — it is a refinement of Phase 7 following your decision
on provider selection. The implementation lives in the [`ai/`](../ai/README.md) directory.

### Decision

**DeepSeek is the primary AI access point.** By default **Flash**, for a
harder case **Pro** — same vendor, same key, stronger
model. OpenRouter is the first fallback in case of DeepSeek failure, and Kimi the second.
Gemini is **not a provider here at all**: the free tier returned `limit: 0` on the Pro model,
and the paid tier was rejected. Every Gemini entry was removed from the configuration together
with its secret. Gemini models are still reachable through OpenRouter, which is a different
key and a different bill.

| Role | Provider | Model | Status |
|---|---|---|---|
| default | DeepSeek | `deepseek-v4-flash` | active |
| escalation | DeepSeek | `deepseek-v4-pro` | active |
| fallback | OpenRouter | `google/gemini-3.7-flash` | active |
| second fallback | Kimi (Moonshot) | `kimi-k2.5` | active |

*(Two earlier versions of this section were different. The first had Gemini as the default and
DeepSeek as the fallback; that was reversed after the decision not to enter Gemini's paid tier.
The second kept Gemini described but disabled; it was removed entirely once the free tier proved
to grant no access to the Pro model. I am leaving the trail visible so it is clear these are
changes of decision, not oversights.)*

Kimi rejects `temperature: 0` outright — the API answers `only 1 is allowed for this model`.
That is why the calling script carries per-provider parameter overrides rather than one shared
request body, and it is the reason a new provider is always exercised with a direct call before
being written into the chain.

**Why escalation stayed with the same vendor.** I verified live that
`api.deepseek.com` exposes exactly two models — `deepseek-v4-flash` and
`deepseek-v4-pro` — and that Pro genuinely responds. Pro is three times more expensive and has
a five-times lower concurrency limit (500 vs 2500), meaning it is a different computational
profile, not the same thing under a different name. Escalation is meant to change model
power, not vendor: changing vendor simultaneously changes the model, tokenizer, and thinking
handling, so it would be impossible to say why the result improved. OpenRouter
answers a different question — "what if DeepSeek does not respond" — and that is why it is
the fallback, not the escalation.

### Why switching is cheap: one protocol across all providers

The key finding of this section: **DeepSeek, OpenRouter, and Kimi expose
OpenAI-compatible endpoints**, so switching a provider is a matter of changing three
values — base URL, secret name, and model name — not changing code. Gemini's
endpoint is the same shape, which is why OpenRouter can still serve Gemini models
without this layer talking to Google directly.

| Provider | OpenAI-compatible Base URL |
|---|---|
| DeepSeek | `https://api.deepseek.com` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| Kimi (Moonshot) | `https://api.moonshot.ai/v1` |

Verified empirically: the same script `ai/scripts/ai-call.sh`, without changing a
single line, received a correct response from both DeepSeek models and from OpenRouter, and
via OpenRouter also from Gemini models. Also confirmed live was the fallback drop: with a
substituted invalid DeepSeek key, both its entries failed with HTTP 401, and the response
came from OpenRouter. The Gemini endpoint confirmed as to host and path (responds with
"Please pass a valid API key" on an invalid key), but **not confirmed by an actual call**,
because there was no Gemini key in the environment.

A caveat that should not be smoothed over: Gemini's OpenAI compatibility layer is
**marked as beta** by Google and does not have full feature parity.
Google explicitly recommends the native SDK if you are not already invested in
OpenAI libraries. For our use case — a single chat/completions call without
streaming — this is sufficient, but nothing more elaborate should be built on this layer
without re-verifying.

### Costs — correction of the line items in the cost table

The cost table above lists "Gemini API — triage and fixes: 2–6 USD" and
"OpenRouter — escalations: 1–3 USD". After switching the chain to DeepSeek,
**the first line item drops out of the account** (Gemini was removed as a provider),
and the entire layer comes down markedly: the default model is approximately seven times
cheaper on input and over eleven times cheaper on output than `gemini-3.6-flash`,
which previously held that role.

| Model | Role | Input / 1M | Output / 1M |
|---|---|---|---|
| `deepseek-v4-flash` | default | 0.22 USD off-peak / 0.44 peak | 0.66 / 1.32 USD |
| `deepseek-v4-pro` | escalation | 0.66 / 1.32 USD | 1.98 / 3.96 USD |
| `google/gemini-3.7-flash` (OpenRouter) | fallback | 0.375 USD | 1.875 USD |
| Kimi (`kimi-k2.5`) | second fallback | see Moonshot pricing | see Moonshot pricing |

DeepSeek peak hours are 01:00–04:00 and 06:00–10:00 UTC. Input cache hits are
extremely cheap there (0.007–0.014 USD per million for Flash), which is genuinely relevant
for an agent that repeatedly reads the same build log.

Two things that raise the real cost above this table:

- **Thinking tokens count as output**, at DeepSeek as well — thinking mode is
  the default for both V4 variants. Measured live: a single-word response
  cost 42 thinking tokens with Flash and 67 with Pro, and `gemini-3.7-flash` via
  OpenRouter 124. For Gemini 3 models, thinking **cannot be disabled**.
- **The scale does not change, but the principle holds.** At these prices the entire chain is
  still a matter of single-digit dollars per month, which is not an argument for escalating
  in a loop. One Flash pass, one Pro pass, then a human.

The previous argument about the free tier disappears, however: DeepSeek does not have one, so
there is no temptation to use a tier in which the vendor uses content to improve their
products. Build logs from 44 private repos go exclusively through the paid API.

### Security: the agent is never a gatekeeper

This is a refinement of the third principle from the "AI: agent, only when the build fails"
section, and the most important thing in this entire layer. The agent may **only**
propose a change — open a PR or return a patch as an artifact. It has no right
to assess whether a PR passed, to merge anything, or to set the status of a check on which
the merge decision depends.

The reason is concrete and has already been named in this plan: the primary risk is not
a malicious collaborator, but a poisoned package changelog that the agent will read as
an instruction. A model that can be convinced by the content of its input must not decide
what lands on `main`.

The workflow template (`ai/templates/ai-fix-build.yml`) is **disabled by default** —
it lives outside `.github/workflows/`, so GitHub does not see it, and has only a
`workflow_dispatch` trigger. Permissions: `contents: read` and `actions: read`, nothing more.
Checkout with `persist-credentials: false`.

### Where keys live: one controlling repo, not a hundred

Verified, because it sounded like an assumption: **on a personal account there are no
user-level Actions secrets.** GitHub's documentation lists three levels —
organization, repository, repository environment — and only the organization level
allows sharing a single entry across repositories. The API confirms this: `GET
/user/actions/secrets` returns **404** (endpoint does not exist), whereas `GET
/user/codespaces/secrets` returns **403** with the endpoint's documentation, meaning it
exists — but it is the Codespaces store, which Actions does not read. The `dudziakm`
account is `type=User` with no organization.

The pattern that follows from this: **AI keys live exclusively in `dep-automation`**, that is
where the agent workflow lives, and it reaches target repositories using a fine-grained
token with Contents: Read, Actions: Read, and Metadata: Read permissions — and nothing
more. The full description, including rotation, behaviour with an expired token, and the
drawbacks of this arrangement (token tied to a person, single point of compromise, Actions
minute limits for private repos), is in [`ai/README.md`](../ai/README.md) under the section
"Where secrets live on a personal account".

### `gh-aw`: what is confirmed, what is a workaround

`github/gh-aw` has built-in engines `copilot`, `claude`, `codex`, `gemini`, and
`pi`. **DeepSeek is not on that list**, so the default provider for this layer
requires a workaround route in gh-aw: `engine: copilot` in BYOK mode, via
`COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, and `COPILOT_MODEL` — again
the same three values. This is a known cost of choosing DeepSeek, worth stating
explicitly: if Gemini were the default, `engine: gemini` plus the `GEMINI_API_KEY` secret
would suffice (or keyless Google Workload Identity Federation, which switches the engine to
the Vertex AI backend). With a single `chat/completions` call the difference is minor, but
it stops being minor if the layer were to use the engine's built-in mechanisms.

The Phase 7 entry in the phases table ("Agent gh-aw + Gemini") should therefore be read as
"agent gh-aw + DeepSeek via BYOK".

The gh-aw security mechanisms the plan relies on: the agent job is read-only by default
in a sandbox, an outbound traffic firewall with an allowlist of hosts, and writes to GitHub
exclusively through separate, validated `safe-outputs` jobs.
This is consistent with what the plan assumed in the architecture section. Not executed —
the mapping comes from documentation, not from a running workflow.

---
## Sources of Key Findings

- Automerge behavior and absence of tests: [docs.renovatebot.com/key-concepts/automerge](https://docs.renovatebot.com/key-concepts/automerge/)
- `ignoreTests` and `platformAutomerge`: [configuration-options](https://docs.renovatebot.com/configuration-options/)
- Version grace period: [minimum-release-age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)
- Bug with perpetually pending stability check: [renovate#45236](https://github.com/renovatebot/renovate/issues/45236)
- Ranges vs lockfile: [rangeStrategy](https://docs.renovatebot.com/configuration-options/#rangestrategy)
- Silent mode for archived repos: [mode: silent](https://docs.renovatebot.com/self-hosted-configuration/#mode)
- Vulnerability database used for overrides audit: [osv.dev querybatch](https://google.github.io/osv.dev/post-v1-querybatch/)
- Grace period in npm requires npm ≥ 11.10.0: [npm config](https://docs.npmjs.com/cli/v12/using-npm/config/#min-release-age)
- pnpm hardening: [pnpm.io/supply-chain-security](https://pnpm.io/supply-chain-security)
- GitHub agentic framework: [github.github.com/gh-aw](https://github.github.com/gh-aw/)
- Gemini CLI compromise via prompt injection: [pillar.security](https://www.pillar.security/blog/my-agentic-trust-issues-from-prompt-injection-to-supply-chain-compromise-on-gemini-cli)

Sources added to the AI providers section:

- DeepSeek models and pricing, including OpenAI-compatible base URL and concurrency limits: [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- OpenRouter pricing fetched programmatically: [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models)
- Gemini Developer API pricing: [ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing)
- Gemini OpenAI compatibility (endpoint, limitations, `reasoning_effort`): [ai.google.dev/gemini-api/docs/openai](https://ai.google.dev/gemini-api/docs/openai)
- Gemini API limits and tier thresholds: [ai.google.dev/gemini-api/docs/rate-limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- gh-aw engines and their authentication: [github.github.com/gh-aw/reference/engines](https://github.github.com/gh-aw/reference/engines/), [reference/auth](https://github.github.com/gh-aw/reference/auth/)
- Gemini in gh-aw: [github.github.com/gh-aw/engines/gemini](https://github.github.com/gh-aw/engines/gemini/)

Sources added to the secrets section:

- Actions secrets levels (organization, repository, environment): [docs.github.com/actions/concepts/security/secrets](https://docs.github.com/en/actions/concepts/security/secrets)
- Secret types and sharing scope: [docs.github.com/code-security/reference/secret-security/secret-types](https://docs.github.com/en/code-security/reference/secret-security/secret-types)
- Fine-grained PAT limitations and limits (no Checks API, 50-token limit, validity up to 366 days): [docs.github.com/authentication/.../managing-your-personal-access-tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens-limitations)
- Actions minutes within plan limit: [docs.github.com/billing/reference/product-usage-included](https://docs.github.com/en/billing/reference/product-usage-included)

### Methodology and Known Gaps

Repository data collected on 18.08.2026 via GitHub REST and GraphQL API on the
dudziakm account. Renovate 44.33.2 dry-run performed locally in read-only mode.
Logs of 14 failing workflows analyzed read-only; for four runs from
May 2026 and December 2025 the logs have expired and the cause is marked as
inferred.

The overrides audit proceeded in three steps, because the first one gave a misleading result.
First, 86 exact pins from 16 repos were sent in batch to OSV — six came back as
vulnerable. Then checking the lockfiles showed that five of those packages do not
appear in the dependency tree, so the pins are inactive; the sixth (`nanoid`) does not
apply, and the installed version is already patched. Only the third step — an attempt to
recalculate the lockfile on clones of `testBasketPw` and `code-reviewer` — revealed
the actual defect (`EUSAGE` plus `EOVERRIDE`) and allowed verifying the fix
end-to-end. The conclusions from step one were corrected in the plan, not
removed, so it is visible why a simple read of `package.json` is not sufficient here.
Known gap: 18 entries recorded as ranges (`^`) were skipped, because without
resolving the tree they cannot be unambiguously checked.

Step four, added after expanding the fix to 12 repos produced four
"failures", none of which were failures of the fix. For each repo: clean
HEAD, stashed `node_modules`, `npm ci --dry-run --ignore-scripts`. The first
run of this measurement was skewed by the presence of `node_modules` from my
earlier installations and showed "up to date"; the result in the plan comes from
the run after stashing that directory. Established: seven repos install
correctly despite the mismatch, one yields to the fix, three have
peer-dependency conflicts (a different class of defect), one has no lockfile.
Separately rejected hypothesis for `3rd-devs-my`: `npm ci` was failing there on
compilation of native `canvas` 2.11.2 under node 24 / darwin arm64, i.e. on my
machine, not in the repo — under `--ignore-scripts` it installs 1516 packages and
the build passes.
