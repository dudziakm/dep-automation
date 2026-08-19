# Owner checklist — Renovate installation is inert on Mend's side

Renovate is still silent as of 2026-08-19 (re-verified live). The earlier
explanation — *"`renovate[bot]` has `permission: none`, owner must grant write
access"* — is **WRONG and must not be repeated**. Access is granted (owner
confirmed All-repositories + read/write on the relevant scopes), and the
`permission: none` reading was a false signal.

## Evidence

- `dep-automation` is `public`; all presets return HTTP 200.
- `renovate-config-validator` → **Config validated successfully** for every
  preset (`default/js/jvm/mixed/silent/automerge`).
- Committed `renovate.json` in the pilots extends the presets and resolves.
- `author:app/renovate` artefacts: **0** (open+closed). Dependency Dashboard
  issues: **0**. Renovate config-warning/error issues: **0**.
- A **fresh push** to `renovate.json` on two pilots produced **no job** within
  23 minutes; the config committed ~12.5h earlier also produced nothing — this
  rules out "the queue is just slow."

### The `permission: none` signal is meaningless

`GET /repos/<owner>/<repo>/collaborators/renovate[bot]/permission` returns
`none` — but so does `dependabot[bot]`, which clearly has access. GitHub App
bots are not collaborators; they act via an installation token, so this endpoint
never reflects App access. Do not use it as proof of anything.

## Root cause

Config, presets, resolution and access are all fine, yet a fresh push webhook
produced no job and the account has never produced a single Renovate artefact.
The Mend Renovate App, though shown as installed with All-repositories access,
is **not executing jobs for this account** — the installation is inert on Mend's
backend (never onboarded into the scheduler, or suspended). The missing "re-run"
control on the Mend dashboard fits an account that was never fully onboarded.

## Owner action (GitHub + Mend UI) — not "grant write access"

1. **https://github.com/settings/installations → Renovate**: if suspended, click
   **Unsuspend**.
2. Toggle **Repository access** off → Save → back to **All repositories** → Save,
   to force GitHub to re-send the installation webhook so Mend re-enqueues jobs.
3. **https://developer.mend.io/github/dudziakm**: if repos are missing,
   **uninstall + reinstall** the App (All repositories) to re-run Mend
   onboarding; if listed, open **Job logs** and read the real run error.
4. Expect a Dependency Dashboard issue or a PR on a pilot within ~10–30 min of a
   successful onboarding.

## Hard-excluded repos (do not grant / do not re-seed)

- `ai-concept-compass`
- `ai-concept-compass-greenfield`
- `10xCardsAstro`
- `my10xCards`
- `ai-rules-builder`

## Do not do yet

- Do **not** flip `dep-automation` to private until Renovate has successfully
  fetched `github>dudziakm/dep-automation:*` presets and opened real PRs.
