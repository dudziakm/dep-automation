#!/usr/bin/env bash
# Seed the shared verify workflow into JS/mixed repos (branch + PR).
#
#   ./scripts/seed-verify.sh repos.tsv            # dry-run
#   APPLY=1 ./scripts/seed-verify.sh repos.tsv    # create PRs
#   ONLY=a,b APPLY=1 ./scripts/seed-verify.sh ... # selected repos only
set -euo pipefail

TSV="${1:?provide TSV from classify.sh}"
OWNER="${OWNER:-dudziakm}"
BRANCH="${BRANCH:-chore/verify-gate}"
APPLY="${APPLY:-0}"
ONLY="${ONLY:-}"
WORK="${WORK:-/tmp/seed-verify}"
TPL="${TPL:-templates/verify-js.yml}"

# Hard exclusion: never seed repos listed in EXCLUDED-REPOS.txt (owner policy 2026-08-18).
EXCLUDE_FILE="$(dirname "$0")/../EXCLUDED-REPOS.txt"
# shellcheck disable=SC2317,SC2329  # called from the loop below
is_excluded() {
  [ -f "$EXCLUDE_FILE" ] || return 1
  grep -vE '^[[:space:]]*#' "$EXCLUDE_FILE" | grep -qx "$1"
}

[[ -f "$TPL" ]] || { echo "missing template $TPL" >&2; exit 1; }
TPL_ABS="$(cd "$(dirname "$TPL")" && pwd)/$(basename "$TPL")"

me=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ "$me" != "$OWNER" ]]; then
  echo "STOP: gh authenticated as '${me:-nobody}', but OWNER is '$OWNER'." >&2
  exit 2
fi

mkdir -p "$WORK"
made=0; skipped=0; failed=0

while IFS=$'\t' read -r name _eco activity preset; do
  [[ "$name" == "repo" ]] && continue
  # Active JS/mixed only. Silent mode does not open PRs, so a gate there is wasted.
  [[ "$preset" != "js" && "$preset" != "mixed" ]] && continue
  [[ "$activity" != "active" ]] && continue
  if [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi

  if is_excluded "$name"; then
    printf 'SKIP     %-32s excluded (EXCLUDED-REPOS.txt)\n' "$name"
    skipped=$((skipped+1)); continue
  fi

  # Owner decision: ignore g2a.com E2E harness as a gate.
  if [[ "$name" == "testBasketPw" ]]; then
    printf 'SKIP     %-32s ignored by owner (testBasketPw)\n' "$name"
    skipped=$((skipped+1)); continue
  fi

  if gh api "repos/$OWNER/$name/contents/.github/workflows/verify.yml" --silent >/dev/null 2>&1; then
    printf 'SKIP     %-32s already has verify.yml\n' "$name"; skipped=$((skipped+1)); continue
  fi
  open_pr=$(gh pr list --repo "$OWNER/$name" --head "$BRANCH" --state open \
              --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [[ -n "$open_pr" ]]; then
    printf 'SKIP     %-32s already has PR #%s\n' "$name" "$open_pr"; skipped=$((skipped+1)); continue
  fi

  if [[ "$APPLY" != "1" ]]; then
    printf 'WOULD    %-32s (%s)\n' "$name" "$preset"; made=$((made+1)); continue
  fi

  rm -rf "${WORK:?}/${name:?}"
  if ! gh repo clone "$OWNER/$name" "$WORK/$name" -- --depth 1 --quiet 2>/dev/null; then
    printf 'FAIL     %-32s clone failed\n' "$name"; failed=$((failed+1)); continue
  fi

  rc=0
  (
    cd "$WORK/$name"
    git checkout -q -b "$BRANCH"
    mkdir -p .github/workflows
    cp "$TPL_ABS" .github/workflows/verify.yml
    git add .github/workflows/verify.yml
    git commit -q -m "$(cat <<'EOF'
Add lightweight verify gate for dependency updates

Install, typecheck, and build — no E2E. External E2E targets are noisy as a
merge gate; this workflow should stay green only when a version bump did not
break install/typecheck/build.
EOF
)"
    git push -q -u origin "$BRANCH"
    gh pr create --repo "$OWNER/$name" --head "$BRANCH" \
      --base "$(gh repo view "$OWNER/$name" --json defaultBranchRef --jq .defaultBranchRef.name)" \
      --title "Add lightweight verify gate for dependency updates" \
      --body "$(cat <<'EOF'
Adds `.github/workflows/verify.yml`: lockfile install, `tsc --noEmit` when TypeScript is present, and `build` when that script exists.

**Deliberately does not run E2E.** Playwright/Cypress suites that hit external services are noisy as an automerge gate.

Prerequisite for fail-closed automerge: Renovate only merges on green CI, so a real signal must exist first.
EOF
)" >/dev/null
  ) || rc=$?

  if [[ $rc -eq 0 ]]; then
    printf 'ADDED    %-32s\n' "$name"; made=$((made+1))
  else
    printf 'FAIL     %-32s exit %d\n' "$name" "$rc"; failed=$((failed+1))
  fi
done < "$TSV"

echo
printf 'Added/would-add: %d   skipped: %d   failed: %d\n' "$made" "$skipped" "$failed"
[[ "$APPLY" != "1" ]] && echo 'Dry-run only. Re-run with APPLY=1 to create PRs.'
exit 0
