#!/usr/bin/env bash
# Dodaje workflow verify do repo JS na galezi + PR.
#
#   ./scripts/seed-verify.sh repos.tsv            # dry-run
#   APPLY=1 ./scripts/seed-verify.sh repos.tsv    # tworzy PR-y
#   ONLY=a,b APPLY=1 ./scripts/seed-verify.sh ... # tylko wybrane
set -euo pipefail

TSV="${1:?podaj plik TSV z classify.sh}"
OWNER="${OWNER:-dudziakm}"
BRANCH="${BRANCH:-chore/verify-gate}"
APPLY="${APPLY:-0}"
ONLY="${ONLY:-}"
WORK="${WORK:-/tmp/seed-verify}"
TPL="${TPL:-templates/verify-js.yml}"

[[ -f "$TPL" ]] || { echo "brak szablonu $TPL" >&2; exit 1; }
TPL_ABS="$(cd "$(dirname "$TPL")" && pwd)/$(basename "$TPL")"

me=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ "$me" != "$OWNER" ]]; then
  echo "STOP: gh uwierzytelniony jako '${me:-nikt}', a OWNER to '$OWNER'." >&2
  exit 2
fi

mkdir -p "$WORK"
made=0; skipped=0; failed=0

while IFS=$'\t' read -r name _eco activity preset; do
  [[ "$name" == "repo" ]] && continue
  # Tylko aktywne repo JS. Tryb cichy nie generuje PR-ow, wiec bramka jest tam zbedna.
  [[ "$preset" != "js" && "$preset" != "mixed" ]] && continue
  [[ "$activity" != "active" ]] && continue
  if [[ -n "$ONLY" ]] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi

  if gh api "repos/$OWNER/$name/contents/.github/workflows/verify.yml" --silent >/dev/null 2>&1; then
    printf 'POMIJAM  %-32s ma juz verify.yml\n' "$name"; skipped=$((skipped+1)); continue
  fi
  open_pr=$(gh pr list --repo "$OWNER/$name" --head "$BRANCH" --state open \
              --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [[ -n "$open_pr" ]]; then
    printf 'POMIJAM  %-32s ma juz PR #%s\n' "$name" "$open_pr"; skipped=$((skipped+1)); continue
  fi

  if [[ "$APPLY" != "1" ]]; then
    printf 'DODALBYM %-32s (%s)\n' "$name" "$preset"; made=$((made+1)); continue
  fi

  rm -rf "${WORK:?}/${name:?}"
  if ! gh repo clone "$OWNER/$name" "$WORK/$name" -- --depth 1 --quiet 2>/dev/null; then
    printf 'BLAD     %-32s klon nie wyszedl\n' "$name"; failed=$((failed+1)); continue
  fi

  rc=0
  (
    cd "$WORK/$name"
    git checkout -q -b "$BRANCH"
    mkdir -p .github/workflows
    cp "$TPL_ABS" .github/workflows/verify.yml
    git add .github/workflows/verify.yml
    git commit -q -m "Dodaj lekka bramke verify dla aktualizacji zaleznosci

Instalacja, typecheck i build — bez E2E. Zestawy E2E w tych repo celuja w
zewnetrzne serwisy, ktore znikaja albo blokuja ruch z centrow danych, wiec
jako bramka daja szum zamiast dowodu. Ta bramka ma byc zielona wtedy i tylko
wtedy, gdy podbicie wersji niczego nie zepsulo."
    git push -q -u origin "$BRANCH"
    gh pr create --repo "$OWNER/$name" --head "$BRANCH" \
      --base "$(gh repo view "$OWNER/$name" --json defaultBranchRef --jq .defaultBranchRef.name)" \
      --title "Dodaj lekką bramkę verify dla aktualizacji zależności" \
      --body "Dodaje \`.github/workflows/verify.yml\`: instalacja z lockfile'a, \`tsc --noEmit\` jeśli repo ma TypeScript, oraz \`build\` jeśli istnieje taki skrypt.

**Świadomie nie uruchamia E2E.** Zestawy Playwrighta i Cypressa w tych repo celują w zewnętrzne serwisy — część z nich zniknęła, część blokuje ruch z adresów centrów danych. Jako bramka automerge dają szum, nie dowód.

To warunek wstępny dla automerge: Renovate scala tylko przy zielonym CI, więc najpierw musi istnieć sygnał, który realnie coś sprawdza." >/dev/null
  ) || rc=$?

  if [[ $rc -eq 0 ]]; then
    printf 'DODANE   %-32s\n' "$name"; made=$((made+1))
  else
    printf 'BLAD     %-32s nie wyszlo (kod %d)\n' "$name" "$rc"; failed=$((failed+1))
  fi
done < "$TSV"

echo
printf 'Dodane: %d   pominiete: %d   bledy: %d\n' "$made" "$skipped" "$failed"
[[ "$APPLY" != "1" ]] && echo 'To byl dry-run. Uruchom z APPLY=1.'
exit 0
