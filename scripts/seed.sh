#!/usr/bin/env bash
# Zasiewa renovate.json do repo docelowych na gałęzi + PR.
#
#   ./scripts/seed.sh repos.tsv          # dry-run, tylko wypis
#   APPLY=1 ./scripts/seed.sh repos.tsv  # realnie tworzy gałąź i PR
#   ONLY=nazwa1,nazwa2 APPLY=1 ...       # ogranicz do wybranych repo
#
# Idempotentny: repo, które już ma renovate.json (lub .github/renovate.json
# albo .renovaterc.json), jest pomijane.
set -euo pipefail

TSV="${1:?podaj plik TSV z classify.sh}"
OWNER="${OWNER:-dudziakm}"
BRANCH="${BRANCH:-chore/renovate-config}"
APPLY="${APPLY:-0}"
ONLY="${ONLY:-}"
WORK="${WORK:-/tmp/seed-renovate}"

mkdir -p "$WORK"

seeded=0; skipped=0; failed=0

while IFS=$'\t' read -r name eco activity preset; do
  [[ "$name" == "repo" ]] && continue
  [[ "$preset" == skip* || -z "$preset" ]] && continue

  if [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi

  # Renovate czyta config tylko z gałęzi domyślnej.
  existing=""
  for f in renovate.json .renovaterc.json .github/renovate.json renovate.json5; do
    if gh api "repos/$OWNER/$name/contents/$f" --silent >/dev/null 2>&1; then
      existing="$f"; break
    fi
  done
  if [[ -n "$existing" ]]; then
    printf 'POMIJAM  %-32s ma juz %s\n' "$name" "$existing"
    skipped=$((skipped+1)); continue
  fi

  if [[ "$APPLY" != "1" ]]; then
    printf 'ZASIALBYM %-31s preset=%-7s (%s, %s)\n' "$name" "$preset" "$eco" "$activity"
    seeded=$((seeded+1)); continue
  fi

  rm -rf "${WORK:?}/${name:?}"
  if ! gh repo clone "$OWNER/$name" "$WORK/$name" -- --depth 1 --quiet 2>/dev/null; then
    printf 'BLAD     %-32s klon nie wyszedl\n' "$name"
    failed=$((failed+1)); continue
  fi

  # rc czytamy przez '|| rc=$?', bo przy set -e nieudany podshell przerwalby skrypt.
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
    git commit -q -m "chore: podłącz repo pod centralne presety Renovate

Polityka aktualizacji zależności mieszka w dudziakm/dep-automation.
Warstwa: $preset. Automerge na tym etapie wyłączony — najpierw chcemy
zobaczyć, ile i jakich PR-ów bot generuje."
    git push -q -u origin "$BRANCH"
    # --head jawnie: po sklonowaniu przez 'gh repo clone' gh nie rozpoznaje
    # swiezo wypchnietej galezi i przerywa z "you must first push the current
    # branch to a remote".
    gh pr create --head "$BRANCH" \
      --base "$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)" \
      --title "chore: podłącz repo pod centralne presety Renovate" \
      --body "Dodaje \`renovate.json\` wskazujący na warstwę \`$preset\` w [dudziakm/dep-automation](https://github.com/$OWNER/dep-automation).

Config musi istnieć **przed** instalacją aplikacji Renovate — inaczej bot zrobi onboarding z gołym \`config:recommended\` i ominie tę politykę.

Na tym etapie \`automerge\` jest wyłączony." >/dev/null
  ) || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'ZASIANE  %-32s preset=%s\n' "$name" "$preset"
    seeded=$((seeded+1))
  else
    printf 'BLAD     %-32s zasiew nie wyszedl (kod %d)\n' "$name" "$rc"
    failed=$((failed+1))
  fi

done < "$TSV"

echo
printf 'Zasiane/do zasiewu: %d   pominiete: %d   bledy: %d\n' "$seeded" "$skipped" "$failed"
[[ "$APPLY" != "1" ]] && echo 'To byl dry-run. Uruchom z APPLY=1, zeby realnie utworzyc PR-y.'
exit 0
