#!/usr/bin/env bash
# Proves verify-target.sh runs test:unit and does not run test.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
verify="$here/verify-target.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${VERIFY_LOG:?}"
if [[ "${1:-}" == "run" && "${2:-}" == "${NPM_FAIL_ON:-}" ]]; then
  exit 1
fi
exit 0
EOF
cat > "$work/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
printf 'pnpm %s\n' "$*" >> "${VERIFY_LOG:?}"
exit 0
EOF
cat > "$work/bin/corepack" <<'EOF'
#!/usr/bin/env bash
printf 'corepack %s\n' "$*" >> "${VERIFY_LOG:?}"
exit 0
EOF
chmod +x "$work/bin/npm" "$work/bin/pnpm" "$work/bin/corepack"

run_verify() {
  local proj="$1"
  VERIFY_LOG="$work/log" \
  NPM_FAIL_ON="${NPM_FAIL_ON:-}" \
  PATH="$work/bin:$PATH" \
    bash "$verify" "$proj"
}

assert_log() {
  local expected="$1"
  if ! grep -Fxq -- "$expected" "$work/log"; then
    echo "missing log line: $expected" >&2
    echo "--- log ---" >&2
    cat "$work/log" >&2
    exit 1
  fi
}

refuse_log() {
  local unexpected="$1"
  if grep -Fxq -- "$unexpected" "$work/log"; then
    echo "unexpected log line: $unexpected" >&2
    cat "$work/log" >&2
    exit 1
  fi
}

# test:unit runs after typecheck and build; test does not.
proj="$work/with-unit"
mkdir -p "$proj"
cat > "$proj/package.json" <<'EOF'
{
  "name": "with-unit",
  "private": true,
  "scripts": {
    "typecheck": "true",
    "build": "true",
    "test": "true",
    "test:unit": "true"
  }
}
EOF
: > "$work/log"
unset NPM_FAIL_ON
run_verify "$proj"
assert_log "install --ignore-scripts --no-audit --no-fund"
assert_log "run typecheck"
assert_log "run build"
assert_log "run test:unit"
refuse_log "run test"
refuse_log "run type-check"
awk '
  $0 == "run typecheck" { typecheck = NR }
  $0 == "run build" { build = NR }
  $0 == "run test:unit" { unit = NR }
  END {
    if (!(typecheck && build && unit && typecheck < build && build < unit)) exit 1
  }
' "$work/log"

# A project with only test does not run it.
proj="$work/test-only"
mkdir -p "$proj"
cat > "$proj/package.json" <<'EOF'
{
  "name": "test-only",
  "private": true,
  "scripts": { "test": "true" }
}
EOF
: > "$work/log"
run_verify "$proj"
refuse_log "run test"
refuse_log "run test:unit"

# pnpm lockfile selects pnpm for test:unit.
proj="$work/pnpm-unit"
mkdir -p "$proj"
printf '{}\n' > "$proj/pnpm-lock.yaml"
cat > "$proj/package.json" <<'EOF'
{
  "name": "pnpm-unit",
  "private": true,
  "scripts": { "test": "true", "test:unit": "true" }
}
EOF
: > "$work/log"
run_verify "$proj"
assert_log "pnpm install --frozen-lockfile --ignore-scripts"
assert_log "pnpm run test:unit"
refuse_log "pnpm run test"
refuse_log "run test"

# A failing test:unit fails verification.
proj="$work/failing-unit"
mkdir -p "$proj"
cat > "$proj/package.json" <<'EOF'
{
  "name": "failing-unit",
  "private": true,
  "scripts": { "test:unit": "true" }
}
EOF
: > "$work/log"
NPM_FAIL_ON=test:unit
if run_verify "$proj"; then
  echo "expected verify-target.sh to fail when test:unit fails" >&2
  exit 1
fi
unset NPM_FAIL_ON
assert_log "run test:unit"

echo "ok"
