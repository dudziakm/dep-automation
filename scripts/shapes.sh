#!/usr/bin/env bash
# Rozpoznaje ksztalt repo JS pod szablon workflow verify.
# TSV: repo, korzen(tak/nie), workspaces, manager, skrypty, tsconfig, katalogi
set -euo pipefail

TSV="${1:?podaj repos.tsv}"
OWNER="${OWNER:-dudziakm}"

printf 'repo\tkorzen\tworkspaces\tmanager\tbuild\ttypecheck\ttest\ttsconfig\tpakietow\n'

while IFS=$'\t' read -r name _eco activity preset; do
  [[ "$name" == "repo" ]] && continue
  [[ "$preset" != "js" && "$preset" != "mixed" ]] && continue
  [[ "$activity" != "active" ]] && continue

  branch=$(gh api "repos/$OWNER/$name" --jq '.default_branch' 2>/dev/null || true)
  [[ -z "$branch" ]] && continue
  tree=$(gh api "repos/$OWNER/$name/git/trees/$branch?recursive=1" --jq '.tree[]?.path' 2>/dev/null || true)

  pkgs=$(printf '%s\n' "$tree" | grep -E '(^|/)package\.json$' \
           | grep -vE '(^|/)(node_modules|vendor|fixtures?|examples?)/' || true)
  npkgs=$(printf '%s\n' "$pkgs" | grep -c . || true)

  if printf '%s\n' "$pkgs" | grep -qx 'package.json'; then korzen=tak; else korzen=nie; fi

  mgr=npm
  printf '%s\n' "$tree" | grep -qx 'pnpm-lock.yaml' && mgr=pnpm
  printf '%s\n' "$tree" | grep -qx 'yarn.lock' && mgr=yarn
  printf '%s\n' "$tree" | grep -qx 'package-lock.json' && mgr=npm
  printf '%s\n' "$tree" | grep -qE '(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$' || mgr="$mgr(brak-lock)"

  ws=nie; build=nie; tc=nie; tst=nie
  if [[ "$korzen" == "tak" ]]; then
    root=$(gh api "repos/$OWNER/$name/contents/package.json" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || echo '{}')
    printf '%s' "$root" | jq -e '.workspaces' >/dev/null 2>&1 && ws=tak
    printf '%s' "$root" | jq -e '.scripts.build' >/dev/null 2>&1 && build=tak
    printf '%s' "$root" | jq -e '.scripts.typecheck // .scripts["type-check"] // .scripts.tsc' >/dev/null 2>&1 && tc=tak
    printf '%s' "$root" | jq -e '.scripts.test' >/dev/null 2>&1 && tst=tak
  fi

  ts=nie
  printf '%s\n' "$tree" | grep -qx 'tsconfig.json' && ts=tak

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$korzen" "$ws" "$mgr" "$build" "$tc" "$tst" "$ts" "$npkgs"
done < "$TSV"
