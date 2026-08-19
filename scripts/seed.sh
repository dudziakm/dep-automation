#!/usr/bin/env bash

# Hard exclusion: never seed repos listed in EXCLUDED-REPOS.txt (owner policy 2026-08-18).
EXCLUDE_FILE="$(dirname "$0")/../EXCLUDED-REPOS.txt"
# shellcheck disable=SC2317,SC2329  # called from the loop below; shellcheck cannot see indirect use
is_excluded() {
  [ -f "$EXCLUDE_FILE" ] || return 1
  grep -vE '^[[:space:]]*#' "$EXCLUDE_FILE" | grep -qx "$1"
}
# Seed renovate.json into target repos (branch + PR).
#
#   ./scripts/seed.sh repos.tsv          # dry-run, print only
#   APPLY=1 ./scripts/seed.sh repos.tsv  # create branch + PR
#   ONLY=name1,name2 APPLY=1 ...         # limit to selected repos
#
# Idempotent: repos that already have renovate.json (or .github/renovate.json
# or .renovaterc.json) are skipped.
set -euo pipefail

TSV="${1:?provide TSV from classify.sh}"
OWNER="${OWNER:-dudziakm}"
BRANCH="${BRANCH:-chore/renovate-config}"
APPLY="${APPLY:-0}"
ONLY="${ONLY:-}"
WORK="${WORK:-/tmp/seed-renovate}"

mkdir -p "$WORK"

# Identity guard. On a machine with several gh accounts, a different user can be
# active than expected: push still succeeds (git has its own credentials), but
# 'gh pr create' fails with "must be a collaborator" and leaves orphan branches.
me=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ "$me" != "$OWNER" ]]; then
  echo "STOP: gh is authenticated as '${me:-nobody}', but OWNER is '$OWNER'." >&2
  echo "      Set GH_TOKEN for the right account, e.g.:" >&2
  echo "      export GH_TOKEN=\"\$(gh auth token --user $OWNER --hostname github.com)\"" >&2
  exit 2
fi

pr_body() {
  cat <<EOF
Adds \`renovate.json\` pointing at the \`$1\` layer in [dudziakm/dep-automation](https://github.com/$OWNER/dep-automation).

The config must exist **before** installing the Renovate App — otherwise the bot onboards with bare \`config:recommended\` and bypasses this policy.

Automerge is off at this stage: first we want to measure how many and which PRs the bot opens.
EOF
}

seeded=0; skipped=0; failed=0

while IFS=$'\t' read -r name eco activity preset; do
  [[ "$name" == "repo" ]] && continue
  [[ "$preset" == skip* || -z "$preset" ]] && continue

  if [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi

  if is_excluded "$name"; then
    printf 'SKIP     %-32s excluded (EXCLUDED-REPOS.txt)\n' "$name"
    skipped=$((skipped+1)); continue
  fi

  # Renovate only reads config from the default branch.
  existing=""
  for f in renovate.json .renovaterc.json .github/renovate.json renovate.json5; do
    if gh api "repos/$OWNER/$name/contents/$f" --silent >/dev/null 2>&1; then
      existing="$f"; break
    fi
  done
  if [[ -n "$existing" ]]; then
    printf 'SKIP     %-32s already has %s\n' "$name" "$existing"
    skipped=$((skipped+1)); continue
  fi

  if [[ "$APPLY" != "1" ]]; then
    printf 'WOULD    %-31s preset=%-7s (%s, %s)\n' "$name" "$preset" "$eco" "$activity"
    seeded=$((seeded+1)); continue
  fi

  # Branch may already exist after an interrupted run (push happens before PR
  # creation). In that case do not re-clone; just finish the PR.
  if gh api "repos/$OWNER/$name/branches/$BRANCH" --silent >/dev/null 2>&1; then
    open_pr=$(gh pr list --repo "$OWNER/$name" --head "$BRANCH" --state open \
                --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [[ -n "$open_pr" ]]; then
      printf 'SKIP     %-32s already has PR #%s\n' "$name" "$open_pr"
      skipped=$((skipped+1)); continue
    fi
    base=$(gh api "repos/$OWNER/$name" --jq '.default_branch')
    if gh pr create --repo "$OWNER/$name" --head "$BRANCH" --base "$base" \
         --title "chore: point repo at central Renovate presets" \
         --body "$(pr_body "$preset")" >/dev/null 2>&1; then
      printf 'CLOSED   %-31s preset=%s (branch already existed)\n' "$name" "$preset"
      seeded=$((seeded+1))
    else
      printf 'FAIL     %-32s branch exists, PR was not created\n' "$name"
      failed=$((failed+1))
    fi
    continue
  fi

  rm -rf "${WORK:?}/${name:?}"
  if ! gh repo clone "$OWNER/$name" "$WORK/$name" -- --depth 1 --quiet 2>/dev/null; then
    printf 'FAIL     %-32s clone failed\n' "$name"
    failed=$((failed+1)); continue
  fi

  # Read rc via '|| rc=$?' because under set -e a failing subshell would abort.
  rc=0
  (
    cd "$WORK/$name"
    git checkout -q -b "$BRANCH"
    cat > renovate.json <<EOF
{
  "\$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>$OWNER/dep-automation:$preset"]
}
EOF
    git add renovate.json
    git commit -q -m "$(cat <<EOF
chore: point repo at central Renovate presets

Dependency-update policy lives in dudziakm/dep-automation.
Layer: $preset. Automerge is off at this stage — first we want to see
how many and which PRs the bot opens.
EOF
)"
    git push -q -u origin "$BRANCH"
    # --head explicitly: after 'gh repo clone', gh does not recognise the freshly
    # pushed branch and aborts with "you must first push the current branch".
    gh pr create --head "$BRANCH" \
      --base "$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)" \
      --title "chore: point repo at central Renovate presets" \
      --body "$(pr_body "$preset")" >/dev/null
  ) || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'SEEDED   %-32s preset=%s\n' "$name" "$preset"
    seeded=$((seeded+1))
  else
    printf 'FAIL     %-32s seed failed (exit %d)\n' "$name" "$rc"
    failed=$((failed+1))
  fi

done < "$TSV"

echo
printf 'Seeded/would-seed: %d   skipped: %d   failed: %d\n' "$seeded" "$skipped" "$failed"
[[ "$APPLY" != "1" ]] && echo 'Dry-run only. Re-run with APPLY=1 to create PRs.'
exit 0
