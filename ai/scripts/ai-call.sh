#!/usr/bin/env bash
#
# ai-call.sh — a single model call through a provider defined in ai/providers.json.
#
# All providers in the configuration use the same protocol (OpenAI
# /chat/completions), so switching providers does not change a single line of
# code below: only the base_url, secret name, and model name change.
#
# Secrets: the script reads only environment variables named in the configuration.
# The key never enters process arguments (it is passed to curl through a
# configuration file on stdin) and is scrubbed from every error message.
#
# Exit codes:
#   0  success — model response on stdout
#   1  usage or configuration error
#   2  required tool missing (jq, curl)
#   3  no provider in the chain has its secret set
#   4  all providers in the chain failed

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
SYSTEM_PROMPT_DEFAULT="You are an assistant that fixes failing CI builds after dependency upgrades. Answer concisely and specifically. Do not assess whether a PR may be merged; only deterministic CI gates decide that."
SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-$SYSTEM_PROMPT_DEFAULT}"
MODE="call"
PROMPT_FILE=""

log() { printf '%s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

scrub() {
  # Scrubs the key value from any text before it reaches the log.
  local text="$1" key="$2"
  if [ -n "$key" ]; then
    printf '%s' "${text//"$key"/<KEY-REDACTED>}"
  else
    printf '%s' "$text"
  fi
}

usage() {
  cat <<'EOF'
Usage: ai-call.sh [OPTIONS] [PROMPT_FILE|-]

The prompt is read from the file supplied as an argument, or from stdin when the
argument is "-" or omitted.

Options:
  -p, --provider NAME    force a specific provider, with no escalation or fallback
      --escalate         start with the escalation provider (harder case)
      --no-escalate      use only the default provider, with no escalation or fallback
  -m, --model NAME       override the model name
      --max-tokens N     override the response token limit
      --reasoning-effort minimal|low|medium|high
      --system TEXT      override the system prompt
  -c, --config FILE      alternate path to providers.json
      --list             list providers from the configuration and exit
      --check            check the configuration and presence of secrets, without calls
      --dry-run          show what would be called and by whom
  -h, --help             show this help

Environment variables:
  AI_PROVIDERS_CONFIG    path to providers.json
  AI_SYSTEM_PROMPT       default system prompt
  <SECRET>               each provider's key, under the name in its "secret" field
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
    -*) err "unknown option: $1"; usage >&2; exit 1 ;;
    *) PROMPT_FILE="$1"; shift ;;
  esac
done

for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 || { err "required tool missing: $tool"; exit 2; }
done

[ -f "$CONFIG" ] || { err "provider configuration not found: $CONFIG"; exit 1; }
jq -e . "$CONFIG" >/dev/null 2>&1 || { err "configuration is not valid JSON: $CONFIG"; exit 1; }

cfg() { jq -r "$1" "$CONFIG"; }

role_members() {
  # A role in the chain is a provider name or a list of names tried in order.
  # Both forms are equivalent, so adding another fallback does not change code.
  cfg "[.lancuch[\"$1\"]] | flatten | map(select(type == \"string\" and . != \"\")) | .[]"
}

# --- informational modes --------------------------------------------------

table() {
  # Leave column alignment to the tool because printf counts bytes rather than
  # characters.
  if command -v column >/dev/null 2>&1; then column -t -s "$(printf '\t')"; else cat; fi
}

if [ "$MODE" = "list" ]; then
  {
    printf 'NAME\tMODEL\tSTATUS\tSECRET\tROLE\n'
    cfg '.providers | to_entries[] | [.key, .value.model, .value.status, .value.secret, .value.rola] | @tsv'
  } | table
  exit 0
fi

# --- provider chain construction -----------------------------------------

chain=""

add_to_chain() {
  # Appends providers to the chain, skipping duplicates. The chain is a
  # space-separated list, so a provider name cannot contain whitespace; a
  # separate validate-ai.yml rule enforces this.
  local p
  for p in "$@"; do
    [ -n "$p" ] || continue
    case " $chain " in *" $p "*) ;; *) chain="${chain:+$chain }$p" ;; esac
  done
}

if [ -n "$FORCE_PROVIDER" ]; then
  cfg '.providers | keys[]' | grep -qx -- "$FORCE_PROVIDER" ||
    { err "provider '$FORCE_PROVIDER' does not exist in $CONFIG"; exit 1; }
  chain="$FORCE_PROVIDER"
  if [ "$(cfg ".providers[\"$FORCE_PROVIDER\"].status // empty")" = "wyłączony" ]; then
    log "WARNING: provider '$FORCE_PROVIDER' is disabled in the configuration. Using it because it was explicitly requested with --provider."
  fi
else
  domyslny=$(role_members domyslny)
  eskalacja=$(role_members eskalacja)
  zapas=$(role_members zapas)
  [ -n "$domyslny" ] || { err ".lancuch.domyslny is missing in $CONFIG"; exit 1; }
  # The word splitting below is intentional: role_members returns a name list.
  if [ "$START_AT" = "eskalacja" ] && [ -n "$eskalacja" ]; then
    # shellcheck disable=SC2086
    add_to_chain $eskalacja
  else
    # shellcheck disable=SC2086
    add_to_chain $domyslny
  fi
  if [ "$NO_ESCALATE" -eq 0 ]; then
    # shellcheck disable=SC2086
    add_to_chain $eskalacja $zapas
  fi
fi

secret_name_of() { cfg ".providers[\"$1\"].secret // empty"; }
status_of() { cfg ".providers[\"$1\"].status // empty"; }
model_of() { cfg ".providers[\"$1\"].model // empty"; }
base_url_of() { cfg ".providers[\"$1\"].base_url // empty"; }

param_of() {
  # A provider parameter, or the configuration default when it is not set.
  # Providers differ in what they accept: Kimi rejects a temperature other than
  # 1 with a 400 error, so this must be data rather than a code constant.
  local value
  value=$(cfg ".providers[\"$1\"].parametry.$2 // empty")
  [ -n "$value" ] || value=$(cfg ".domyslne_parametry.$2 // empty")
  printf '%s' "$value"
}

secret_present() {
  # Returns 0 when the secret is set and non-empty. Its value is never returned.
  local name value
  name=$(secret_name_of "$1")
  [ -n "$name" ] || return 1
  value=$(printenv "$name" 2>/dev/null || true)
  [ -n "$value" ]
}

if [ "$MODE" = "check" ]; then
  log "Configuration: $CONFIG"
  log "Chain: $chain"
  problems=0
  for p in $chain; do
    secret_present "$p" || problems=$((problems + 1))
  done
  {
    printf 'PROVIDER\tSTATUS\tSECRET\tPRESENT\n'
    for p in $chain; do
      if secret_present "$p"; then present="yes"; else present="NO"; fi
      printf '%s\t%s\t%s\t%s\n' "$p" "$(status_of "$p")" "$(secret_name_of "$p")" "$present"
    done
  } | table
  if [ "$problems" -gt 0 ]; then
    log ""
    log "Warning: $problems provider(s) in the chain do not have their secret set."
  fi
  exit 0
fi

# --- prompt ---------------------------------------------------------------

if [ -z "$PROMPT_FILE" ] || [ "$PROMPT_FILE" = "-" ]; then
  PROMPT=$(cat)
else
  [ -f "$PROMPT_FILE" ] || { err "prompt file not found: $PROMPT_FILE"; exit 1; }
  PROMPT=$(cat -- "$PROMPT_FILE")
fi
[ -n "$PROMPT" ] || { err "prompt is empty"; exit 1; }

# Resolve max_tokens and temperature per provider because each can have its own
# values. The --max-tokens flag overrides all of them.
TIMEOUT_S=$(cfg '.domyslne_parametry.timeout_s // 120')

if [ -n "$MAX_TOKENS" ]; then
  case "$MAX_TOKENS" in
    *[!0-9]*) err "--max-tokens must be an integer; got: $MAX_TOKENS"; exit 1 ;;
  esac
fi
if [ -n "$REASONING_EFFORT" ]; then
  case "$REASONING_EFFORT" in
    minimal|low|medium|high) ;;
    *) err "--reasoning-effort accepts: minimal, low, medium, high"; exit 1 ;;
  esac
fi

TMPDIR_RUN=$(mktemp -d "${TMPDIR:-/tmp}/ai-call.XXXXXX")
# shellcheck disable=SC2329,SC2317  # called by the trap below, not directly
cleanup() {
  # shellcheck disable=SC2317
  # No rm -rf: remove only files created here and their directory.
  rm -f -- "${TMPDIR_RUN}/payload.json" "${TMPDIR_RUN}/body.json" "${TMPDIR_RUN}/curl.err"
  # shellcheck disable=SC2317
  rmdir -- "$TMPDIR_RUN" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
chmod 700 "$TMPDIR_RUN"

# --- one attempt with one provider ---------------------------------------

RESPONSE_TEXT=""
LAST_REASON=""

try_provider() {
  local provider="$1"
  local model base_url secret_name key payload body http finish content errmsg
  local ptokens ctokens rtokens max_tokens temperature

  model="${OVERRIDE_MODEL:-$(model_of "$provider")}"
  base_url=$(base_url_of "$provider")
  secret_name=$(secret_name_of "$provider")
  max_tokens="${MAX_TOKENS:-$(param_of "$provider" max_tokens)}"
  temperature=$(param_of "$provider" temperature)
  [ -n "$max_tokens" ] || max_tokens=4096
  [ -n "$temperature" ] || temperature=0

  if [ -z "$model" ] || [ -z "$base_url" ] || [ -z "$secret_name" ]; then
    LAST_REASON="incomplete provider entry for '$provider' in the configuration"
    return 1
  fi

  key=$(printenv "$secret_name" 2>/dev/null || true)
  if [ -z "$key" ]; then
    LAST_REASON="missing secret \$${secret_name} for provider '$provider'"
    return 1
  fi
  # The key goes into curl's configuration file, so allow only characters that
  # cannot break quoting or the HTTP header. Reject rather than guess.
  if ! printf '%s' "$key" | grep -Eq '^[A-Za-z0-9._~+/=:-]+$'; then
    LAST_REASON="value of \$${secret_name} contains a character forbidden in the authorization header"
    return 1
  fi

  payload="${TMPDIR_RUN}/payload.json"
  body="${TMPDIR_RUN}/body.json"

  jq -n \
    --arg model "$model" \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$PROMPT" \
    --argjson max_tokens "$max_tokens" \
    --argjson temperature "$temperature" \
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
    LAST_REASON="failed to construct a request for '$provider' — check domyslne_parametry in the configuration"
    return 1
  }

  log "-> provider=${provider} model=${model} host=$(printf '%s' "$base_url" | sed -E 's#^https?://([^/]+).*#\1#') max_tokens=${max_tokens} temperature=${temperature}"

  # The URL and authorization header go through stdin so the key does not appear
  # in the process list. printf is a Bash builtin, so it does not create argv either.
  http=$(
    printf 'url = "%s/chat/completions"\nrequest = "POST"\nheader = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\ndata-binary = "@%s"\nmax-time = "%s"\n' \
      "$base_url" "$key" "$payload" "$TIMEOUT_S" |
      curl --silent --show-error --output "$body" --write-out '%{http_code}' --config - 2>"${TMPDIR_RUN}/curl.err"
  ) || {
    LAST_REASON="curl could not make a request to '$provider': $(scrub "$(cat "${TMPDIR_RUN}/curl.err")" "$key")"
    return 1
  }

  if [ "$http" != "200" ]; then
    errmsg=$(jq -r '.error.message // .error // empty' "$body" 2>/dev/null || true)
    [ -n "$errmsg" ] || errmsg=$(head -c 300 "$body" 2>/dev/null || true)
    LAST_REASON="provider '$provider' returned HTTP ${http}: $(scrub "$errmsg" "$key")"
    return 1
  fi

  content=$(jq -r '.choices[0].message.content // empty' "$body" 2>/dev/null || true)
  finish=$(jq -r '.choices[0].finish_reason // "?"' "$body" 2>/dev/null || true)
  ptokens=$(jq -r '.usage.prompt_tokens // "?"' "$body" 2>/dev/null || true)
  ctokens=$(jq -r '.usage.completion_tokens // "?"' "$body" 2>/dev/null || true)
  rtokens=$(jq -r '.usage.completion_tokens_details.reasoning_tokens // 0' "$body" 2>/dev/null || true)

  log "   http=200 finish=${finish} tokens: prompt=${ptokens} response=${ctokens} (reasoning=${rtokens})"

  if [ -z "$content" ]; then
    LAST_REASON="provider '$provider' returned empty content (finish_reason=${finish}). For finish_reason=length, increase --max-tokens: reasoning tokens consume the response budget."
    return 1
  fi

  RESPONSE_TEXT="$content"
  return 0
}

# --- dry-run mode ---------------------------------------------------------

if [ "$MODE" = "dryrun" ]; then
  log "Configuration: $CONFIG"
  log "Attempt chain: $chain"
  for p in $chain; do
    if secret_present "$p"; then avail="secret present"; else avail="SECRET MISSING - provider would be skipped"; fi
    log "  $p  model=${OVERRIDE_MODEL:-$(model_of "$p")}  base_url=$(base_url_of "$p")  max_tokens=${MAX_TOKENS:-$(param_of "$p" max_tokens)}  temperature=$(param_of "$p" temperature)  [$avail]"
  done
  log "timeout=${TIMEOUT_S}s reasoning_effort=${REASONING_EFFORT:-default}"
  log "Prompt: $(printf '%s' "$PROMPT" | wc -c | tr -d ' ') bytes; no network call."
  exit 0
fi

# --- chain execution ------------------------------------------------------

available=0
for p in $chain; do
  if secret_present "$p"; then available=$((available + 1)); fi
done
if [ "$available" -eq 0 ]; then
  err "no provider in the chain ($chain) has its secret set."
  err "check secret names with: $0 --check"
  exit 3
fi

for p in $chain; do
  if try_provider "$p"; then
    printf '%s\n' "$RESPONSE_TEXT"
    exit 0
  fi
  log "   skipped: ${LAST_REASON}"
done

err "all attempts failed. Last reason: ${LAST_REASON}"
exit 4
