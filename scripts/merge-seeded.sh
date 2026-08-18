#!/usr/bin/env bash
# Scala otwarte PR-y z konfiguracja Renovate (galaz chore/renovate-config).
# Uzycie: ./scripts/merge-seeded.sh repos.tsv
set -euo pipefail

TSV="${1:?podaj plik TSV z classify.sh}"
OWNER="${OWNER:-dudziakm}"
BRANCH="${BRANCH:-chore/renovate-config}"

me=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ "$me" != "$OWNER" ]]; then
  echo "STOP: gh uwierzytelniony jako '${me:-nikt}', a OWNER to '$OWNER'." >&2
  exit 2
fi

merged=0; failed=0
declare -a failedlist=()

while IFS=$'\t' read -r name _eco _activity preset; do
  [[ "$name" == "repo" || "$preset" == skip* || -z "$preset" ]] && continue

  n=$(gh pr list --repo "$OWNER/$name" --head "$BRANCH" --state open \
        --json number --jq '.[0].number // empty' 2>/dev/null || true)
  [[ -z "$n" ]] && continue

  if gh pr merge "$n" --repo "$OWNER/$name" --squash --delete-branch >/dev/null 2>&1; then
    merged=$((merged+1))
    printf 'OK    %-32s #%s\n' "$name" "$n"
  else
    failed=$((failed+1)); failedlist+=("$name#$n")
    printf 'BLAD  %-32s #%s\n' "$name" "$n"
  fi
done < "$TSV"

echo
printf 'Scalone: %d   nieudane: %d\n' "$merged" "$failed"
if [[ ${#failedlist[@]} -gt 0 ]]; then
  printf 'Do recznego sprawdzenia: %s\n' "${failedlist[@]}"
fi
