#!/usr/bin/env bash
#
# ai-call.sh — jedno wywołanie modelu przez providera opisanego w ai/providers.json.
#
# Wszyscy providerzy w konfiguracji mówią tym samym protokołem (OpenAI
# /chat/completions), więc przełączenie providera nie zmienia ani jednej linii
# kodu poniżej: zmienia się base_url, nazwa sekretu i nazwa modelu.
#
# Sekrety: skrypt czyta wyłącznie zmienne środowiskowe o nazwach z konfiguracji.
# Klucz nigdy nie trafia do argumentów procesu (przekazujemy go curlowi przez
# plik konfiguracyjny na stdin) i jest wycierany z każdego komunikatu błędu.
#
# Kody wyjścia:
#   0  sukces — odpowiedź modelu na stdout
#   1  błąd użycia albo błąd konfiguracji
#   2  brak wymaganego narzędzia (jq, curl)
#   3  żaden provider z łańcucha nie ma ustawionego sekretu
#   4  wszyscy providerzy z łańcucha zawiedli

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONFIG_DEFAULT="${SCRIPT_DIR}/../providers.json"

CONFIG="${AI_PROVIDERS_CONFIG:-$CONFIG_DEFAULT}"
FORCE_PROVIDER=""
OVERRIDE_MODEL=""
START_AT=""
NO_ESCALATE=0
MAX_TOKENS=""
REASONING_EFFORT=""
SYSTEM_PROMPT_DEFAULT="Jestes asystentem naprawiajacym padajace buildy CI po podbiciu zaleznosci. Odpowiadasz zwiezle i konkretnie. Nie oceniasz, czy PR moze zostac scalony - o tym decyduja wylacznie deterministyczne bramki CI."
SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-$SYSTEM_PROMPT_DEFAULT}"
MODE="call"
PROMPT_FILE=""

log() { printf '%s\n' "$*" >&2; }
err() { printf 'BLAD: %s\n' "$*" >&2; }

scrub() {
  # Wyciera wartosc klucza z dowolnego tekstu, zanim trafi do logu.
  local text="$1" key="$2"
  if [ -n "$key" ]; then
    printf '%s' "${text//"$key"/<KLUCZ-UKRYTY>}"
  else
    printf '%s' "$text"
  fi
}

usage() {
  cat <<'EOF'
Uzycie: ai-call.sh [OPCJE] [PLIK_Z_PROMPTEM|-]

Prompt czytany z pliku podanego jako argument, albo ze stdin gdy argument to "-"
lub gdy go brak.

Opcje:
  -p, --provider NAZWA   wymus konkretnego providera, bez eskalacji i zapasu
      --escalate         zacznij od providera eskalacyjnego (trudniejszy przypadek)
      --no-escalate      tylko provider domyslny, bez eskalacji i zapasu
  -m, --model NAZWA      nadpisz nazwe modelu
      --max-tokens N     nadpisz limit tokenow odpowiedzi
      --reasoning-effort minimal|low|medium|high
      --system TEKST     nadpisz prompt systemowy
  -c, --config PLIK      inna sciezka do providers.json
      --list             wypisz providerow z konfiguracji i wyjdz
      --check            sprawdz konfiguracje i obecnosc sekretow, bez wywolan
      --dry-run          pokaz, co i przez kogo zostaloby wywolane
  -h, --help             ta pomoc

Zmienne srodowiskowe:
  AI_PROVIDERS_CONFIG    sciezka do providers.json
  AI_SYSTEM_PROMPT       domyslny prompt systemowy
  <SECRET>               klucz kazdego providera, pod nazwa z pola "secret"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--provider) FORCE_PROVIDER="${2:-}"; shift 2 ;;
    -m|--model) OVERRIDE_MODEL="${2:-}"; shift 2 ;;
    -c|--config) CONFIG="${2:-}"; shift 2 ;;
    --max-tokens) MAX_TOKENS="${2:-}"; shift 2 ;;
    --reasoning-effort) REASONING_EFFORT="${2:-}"; shift 2 ;;
    --system) SYSTEM_PROMPT="${2:-}"; shift 2 ;;
    --escalate) START_AT="eskalacja"; shift ;;
    --no-escalate) NO_ESCALATE=1; shift ;;
    --list) MODE="list"; shift ;;
    --check) MODE="check"; shift ;;
    --dry-run) MODE="dryrun"; shift ;;
    -h|--help) usage; exit 0 ;;
    -) PROMPT_FILE="-"; shift ;;
    -*) err "nieznana opcja: $1"; usage >&2; exit 1 ;;
    *) PROMPT_FILE="$1"; shift ;;
  esac
done

for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 || { err "brak wymaganego narzedzia: $tool"; exit 2; }
done

[ -f "$CONFIG" ] || { err "nie znalazlem konfiguracji providerow: $CONFIG"; exit 1; }
jq -e . "$CONFIG" >/dev/null 2>&1 || { err "konfiguracja nie jest poprawnym JSON-em: $CONFIG"; exit 1; }

cfg() { jq -r "$1" "$CONFIG"; }

# --- tryby informacyjne ---------------------------------------------------

table() {
  # Wyrownanie kolumn zostawiamy narzedziu, bo statusy sa po polsku i printf
  # liczylby bajty zamiast znakow.
  if command -v column >/dev/null 2>&1; then column -t -s "$(printf '\t')"; else cat; fi
}

if [ "$MODE" = "list" ]; then
  {
    printf 'NAZWA\tMODEL\tSTATUS\tSEKRET\tROLA\n'
    cfg '.providers | to_entries[] | [.key, .value.model, .value.status, .value.secret, .value.rola] | @tsv'
  } | table
  exit 0
fi

# --- budowa lancucha providerow ------------------------------------------

chain=""
if [ -n "$FORCE_PROVIDER" ]; then
  cfg '.providers | keys[]' | grep -qx -- "$FORCE_PROVIDER" ||
    { err "provider '$FORCE_PROVIDER' nie istnieje w $CONFIG"; exit 1; }
  chain="$FORCE_PROVIDER"
  if [ "$(cfg ".providers[\"$FORCE_PROVIDER\"].status // empty")" = "wyłączony" ]; then
    log "UWAGA: provider '$FORCE_PROVIDER' ma w konfiguracji status 'wyłączony'. Uzywam go, bo zazadano go jawnie przez --provider."
  fi
else
  domyslny=$(cfg '.lancuch.domyslny // empty')
  eskalacja=$(cfg '.lancuch.eskalacja // empty')
  zapas=$(cfg '.lancuch.zapas // empty')
  [ -n "$domyslny" ] || { err "brak .lancuch.domyslny w $CONFIG"; exit 1; }
  if [ "$START_AT" = "eskalacja" ] && [ -n "$eskalacja" ]; then
    chain="$eskalacja"
  else
    chain="$domyslny"
  fi
  if [ "$NO_ESCALATE" -eq 0 ]; then
    for extra in "$eskalacja" "$zapas"; do
      [ -n "$extra" ] || continue
      case " $chain " in *" $extra "*) ;; *) chain="$chain $extra" ;; esac
    done
  fi
fi

secret_name_of() { cfg ".providers[\"$1\"].secret // empty"; }
status_of() { cfg ".providers[\"$1\"].status // empty"; }
model_of() { cfg ".providers[\"$1\"].model // empty"; }
base_url_of() { cfg ".providers[\"$1\"].base_url // empty"; }

secret_present() {
  # 0 gdy sekret jest ustawiony i niepusty. Wartosci nigdy nie zwracamy.
  local name value
  name=$(secret_name_of "$1")
  [ -n "$name" ] || return 1
  value=$(printenv "$name" 2>/dev/null || true)
  [ -n "$value" ]
}

if [ "$MODE" = "check" ]; then
  log "Konfiguracja: $CONFIG"
  log "Lancuch: $chain"
  problems=0
  for p in $chain; do
    secret_present "$p" || problems=$((problems + 1))
  done
  {
    printf 'PROVIDER\tSTATUS\tSEKRET\tOBECNY\n'
    for p in $chain; do
      if secret_present "$p"; then present="tak"; else present="NIE"; fi
      printf '%s\t%s\t%s\t%s\n' "$p" "$(status_of "$p")" "$(secret_name_of "$p")" "$present"
    done
  } | table
  if [ "$problems" -gt 0 ]; then
    log ""
    log "Uwaga: $problems provider(ow) z lancucha nie ma ustawionego sekretu."
  fi
  exit 0
fi

# --- prompt ---------------------------------------------------------------

if [ -z "$PROMPT_FILE" ] || [ "$PROMPT_FILE" = "-" ]; then
  PROMPT=$(cat)
else
  [ -f "$PROMPT_FILE" ] || { err "nie znalazlem pliku z promptem: $PROMPT_FILE"; exit 1; }
  PROMPT=$(cat -- "$PROMPT_FILE")
fi
[ -n "$PROMPT" ] || { err "prompt jest pusty"; exit 1; }

[ -n "$MAX_TOKENS" ] || MAX_TOKENS=$(cfg '.domyslne_parametry.max_tokens // 4096')
TEMPERATURE=$(cfg '.domyslne_parametry.temperature // 0')
TIMEOUT_S=$(cfg '.domyslne_parametry.timeout_s // 120')

case "$MAX_TOKENS" in
  ''|*[!0-9]*) err "--max-tokens musi byc liczba calkowita, jest: $MAX_TOKENS"; exit 1 ;;
esac
if [ -n "$REASONING_EFFORT" ]; then
  case "$REASONING_EFFORT" in
    minimal|low|medium|high) ;;
    *) err "--reasoning-effort przyjmuje: minimal, low, medium, high"; exit 1 ;;
  esac
fi

TMPDIR_RUN=$(mktemp -d "${TMPDIR:-/tmp}/ai-call.XXXXXX")
# shellcheck disable=SC2329,SC2317  # wywolywane przez trap ponizej, nie wprost
cleanup() {
  # shellcheck disable=SC2317
  # Bez rm -rf: usuwamy tylko pliki, ktore sam tworze, i katalog po nich.
  rm -f -- "${TMPDIR_RUN}/payload.json" "${TMPDIR_RUN}/body.json" "${TMPDIR_RUN}/curl.err"
  # shellcheck disable=SC2317
  rmdir -- "$TMPDIR_RUN" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
chmod 700 "$TMPDIR_RUN"

# --- jedna proba u jednego providera -------------------------------------

RESPONSE_TEXT=""
LAST_REASON=""

try_provider() {
  local provider="$1"
  local model base_url secret_name key payload body http finish content errmsg
  local ptokens ctokens rtokens

  model="${OVERRIDE_MODEL:-$(model_of "$provider")}"
  base_url=$(base_url_of "$provider")
  secret_name=$(secret_name_of "$provider")

  if [ -z "$model" ] || [ -z "$base_url" ] || [ -z "$secret_name" ]; then
    LAST_REASON="niekompletny wpis providera '$provider' w konfiguracji"
    return 1
  fi

  key=$(printenv "$secret_name" 2>/dev/null || true)
  if [ -z "$key" ]; then
    LAST_REASON="brak sekretu \$${secret_name} dla providera '$provider'"
    return 1
  fi
  # Klucz idzie do pliku konfiguracyjnego curla, wiec dopuszczamy tylko znaki,
  # ktore nie moga zepsuc cytowania ani naglowka HTTP. Odrzucamy zamiast zgadywac.
  if ! printf '%s' "$key" | grep -Eq '^[A-Za-z0-9._~+/=:-]+$'; then
    LAST_REASON="wartosc \$${secret_name} zawiera znak niedozwolony w naglowku autoryzacji"
    return 1
  fi

  payload="${TMPDIR_RUN}/payload.json"
  body="${TMPDIR_RUN}/body.json"

  jq -n \
    --arg model "$model" \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$PROMPT" \
    --argjson max_tokens "$MAX_TOKENS" \
    --argjson temperature "$TEMPERATURE" \
    --arg effort "$REASONING_EFFORT" \
    '{
       model: $model,
       messages: [
         { role: "system", content: $system },
         { role: "user", content: $prompt }
       ],
       max_tokens: $max_tokens,
       temperature: $temperature,
       stream: false
     }
     | if $effort == "" then . else . + { reasoning_effort: $effort } end' >"$payload" || {
    LAST_REASON="nie udalo sie zlozyc zapytania dla '$provider' — sprawdz domyslne_parametry w konfiguracji"
    return 1
  }

  log "-> provider=${provider} model=${model} host=$(printf '%s' "$base_url" | sed -E 's#^https?://([^/]+).*#\1#')"

  # Adres i naglowek autoryzacji ida przez stdin, zeby klucz nie pojawil sie
  # w liscie procesow. printf jest wbudowany w basha, wiec tez nie tworzy argv.
  http=$(
    printf 'url = "%s/chat/completions"\nrequest = "POST"\nheader = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\ndata-binary = "@%s"\nmax-time = "%s"\n' \
      "$base_url" "$key" "$payload" "$TIMEOUT_S" |
      curl --silent --show-error --output "$body" --write-out '%{http_code}' --config - 2>"${TMPDIR_RUN}/curl.err"
  ) || {
    LAST_REASON="curl nie zdolal wykonac zapytania do '$provider': $(scrub "$(cat "${TMPDIR_RUN}/curl.err")" "$key")"
    return 1
  }

  if [ "$http" != "200" ]; then
    errmsg=$(jq -r '.error.message // .error // empty' "$body" 2>/dev/null || true)
    [ -n "$errmsg" ] || errmsg=$(head -c 300 "$body" 2>/dev/null || true)
    LAST_REASON="provider '$provider' odpowiedzial HTTP ${http}: $(scrub "$errmsg" "$key")"
    return 1
  fi

  content=$(jq -r '.choices[0].message.content // empty' "$body" 2>/dev/null || true)
  finish=$(jq -r '.choices[0].finish_reason // "?"' "$body" 2>/dev/null || true)
  ptokens=$(jq -r '.usage.prompt_tokens // "?"' "$body" 2>/dev/null || true)
  ctokens=$(jq -r '.usage.completion_tokens // "?"' "$body" 2>/dev/null || true)
  rtokens=$(jq -r '.usage.completion_tokens_details.reasoning_tokens // 0' "$body" 2>/dev/null || true)

  log "   http=200 finish=${finish} tokeny: prompt=${ptokens} odpowiedz=${ctokens} (myslenie=${rtokens})"

  if [ -z "$content" ]; then
    LAST_REASON="provider '$provider' zwrocil pusta tresc (finish_reason=${finish}). Przy finish_reason=length podnies --max-tokens: tokeny myslenia zjadaja budzet odpowiedzi."
    return 1
  fi

  RESPONSE_TEXT="$content"
  return 0
}

# --- tryb dry-run --------------------------------------------------------

if [ "$MODE" = "dryrun" ]; then
  log "Konfiguracja: $CONFIG"
  log "Lancuch prob: $chain"
  for p in $chain; do
    if secret_present "$p"; then avail="sekret obecny"; else avail="SEKRET BRAK - provider bylby pominiety"; fi
    log "  $p  model=${OVERRIDE_MODEL:-$(model_of "$p")}  base_url=$(base_url_of "$p")  [$avail]"
  done
  log "max_tokens=${MAX_TOKENS} temperature=${TEMPERATURE} timeout=${TIMEOUT_S}s reasoning_effort=${REASONING_EFFORT:-domyslny}"
  log "Prompt: $(printf '%s' "$PROMPT" | wc -c | tr -d ' ') bajtow, brak wywolania sieciowego."
  exit 0
fi

# --- przebieg lancucha ---------------------------------------------------

available=0
for p in $chain; do
  if secret_present "$p"; then available=$((available + 1)); fi
done
if [ "$available" -eq 0 ]; then
  err "zaden provider z lancucha ($chain) nie ma ustawionego sekretu."
  err "sprawdz nazwy sekretow komenda: $0 --check"
  exit 3
fi

for p in $chain; do
  if try_provider "$p"; then
    printf '%s\n' "$RESPONSE_TEXT"
    exit 0
  fi
  log "   pominiety: ${LAST_REASON}"
done

err "wszystkie proby zawiodly. Ostatnia przyczyna: ${LAST_REASON}"
exit 4
