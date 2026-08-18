#!/usr/bin/env bash
# Klasyfikuje repozytoria pod preset Renovate.
#
# Wypisuje TSV: repo, ekosystem, aktywnosc, preset
#   ekosystem: js | jvm | mixed | none
#   aktywnosc: active (push <12 mies.) | stale (>12 mies.) | archived
#   preset:    js | jvm | silent | skip
#
# Wymaga: gh, jq. Bez argumentow bierze wszystkie repo uzytkownika.
set -euo pipefail

OWNER="${OWNER:-dudziakm}"
CUTOFF_DAYS="${CUTOFF_DAYS:-365}"

# Repozytoria wylaczone z automatyzacji na zyczenie.
EXCLUDE_RE="${EXCLUDE_RE:-^(10x|3rd-devs)}"

now=$(date +%s)
cutoff=$(( now - CUTOFF_DAYS * 86400 ))

gh repo list "$OWNER" --limit 1000 \
  --json name,isArchived,isFork,pushedAt,defaultBranchRef,visibility \
  > /tmp/classify-repos.json

printf 'repo\tekosystem\taktywnosc\tpreset\n'

jq -r '.[] | [.name, (.isArchived|tostring), (.isFork|tostring),
              (.pushedAt // "1970-01-01T00:00:00Z"),
              (.defaultBranchRef.name // "")] | @tsv' /tmp/classify-repos.json \
| while IFS=$'\t' read -r name archived fork pushed branch; do

  if [[ "$name" =~ $EXCLUDE_RE ]]; then
    printf '%s\t-\t-\tskip (wykluczone)\n' "$name"; continue
  fi
  if [[ "$archived" == "true" ]]; then
    printf '%s\t-\tarchived\tskip (zarchiwizowane)\n' "$name"; continue
  fi
  # Renovate i tak pomija forki w trybie autodiscover (forkProcessing).
  if [[ "$fork" == "true" ]]; then
    printf '%s\t-\t-\tskip (fork)\n' "$name"; continue
  fi
  if [[ -z "$branch" ]]; then
    printf '%s\t-\t-\tskip (puste repo)\n' "$name"; continue
  fi

  pushed_s=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$pushed" +%s 2>/dev/null \
             || date -d "$pushed" +%s 2>/dev/null || echo 0)
  if (( pushed_s < cutoff )); then activity="stale"; else activity="active"; fi

  # Jedno zapytanie na repo: pelne drzewo domyslnej galezi.
  tree=$(gh api "repos/$OWNER/$name/git/trees/$branch?recursive=1" \
           --jq '.tree[]?.path' 2>/dev/null || true)

  # Manifesty na dowolnej glebokosci, ale bez vendored kopii zaleznosci.
  IGNORE='(^|/)(node_modules|vendor|fixtures?|examples?)/'

  js_hits=$(printf '%s\n' "$tree" | grep -E '(^|/)package\.json$' \
              | grep -vE "$IGNORE" || true)
  jvm_hits=$(printf '%s\n' "$tree" \
              | grep -E '(^|/)(pom\.xml|build\.gradle(\.kts)?|gradle/libs\.versions\.toml)$' \
              | grep -vE "$IGNORE" || true)

  # Inne ekosystemy wykrywamy tylko po to, by ich nie nazwac "brak manifestow".
  other_hits=$(printf '%s\n' "$tree" \
              | grep -E '(^|/)(requirements[^/]*\.txt|pyproject\.toml|Pipfile|poetry\.lock|uv\.lock|[^/]+\.csproj|[^/]+\.sln|go\.mod|Cargo\.toml|composer\.json|Gemfile)$' \
              | grep -vE "$IGNORE" || true)

  if   [[ -n "$js_hits" && -n "$jvm_hits" ]]; then eco=mixed
  elif [[ -n "$js_hits"                   ]]; then eco=js
  elif [[ -n "$jvm_hits"                  ]]; then eco=jvm
  elif [[ -n "$other_hits"                ]]; then eco=other
  else                                            eco=none
  fi

  if [[ "$eco" == "other" ]]; then
    preset="skip (poza zakresem js/jvm)"
  elif [[ "$eco" == "none" ]]; then
    preset="skip (brak manifestow)"
  elif [[ "$activity" == "stale" ]]; then
    preset="silent"
  else
    preset="$eco"
  fi

  printf '%s\t%s\t%s\t%s\n' "$name" "$eco" "$activity" "$preset"
done
