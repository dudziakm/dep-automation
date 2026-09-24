#!/usr/bin/env bash
set -euo pipefail

root="${1:?usage: verify-target.sh <repository-root>}"
cd "$root"

install_node_project() {
  local dir="$1"
  (
    cd "$dir"
    echo "::group::Install Node project: ${dir}"

    if [[ -f pnpm-lock.yaml ]]; then
      corepack enable
      pnpm install --frozen-lockfile --ignore-scripts
    elif [[ -f yarn.lock ]]; then
      corepack enable
      yarn install --immutable --ignore-scripts
    elif [[ -f package-lock.json ]]; then
      npm ci --ignore-scripts --no-audit --no-fund
    else
      npm install --ignore-scripts --no-audit --no-fund
    fi

    echo "::endgroup::"
  )
}

verify_node_project() {
  local dir="$1"
  (
    cd "$dir"
    echo "::group::Verify Node project: ${dir}"

    if [[ -f pnpm-lock.yaml ]]; then
      manager=pnpm
    elif [[ -f yarn.lock ]]; then
      manager=yarn
    else
      manager=npm
    fi

    for script in typecheck type-check build; do
      if node -e "const s=require('./package.json').scripts||{};process.exit(s['${script}']?0:1)"; then
        "$manager" run "$script"
      fi
    done

    echo "::endgroup::"
  )
}

node_project_dirs() {
  while IFS= read -r -d '' package; do
    dir="$(dirname "$package")"
    # A root install handles ordinary npm workspaces. Verify a nested project
    # separately only when it owns a lockfile of its own.
    if [[ "$dir" != "." && -f package.json ]] &&
       [[ ! -f "$dir/package-lock.json" && ! -f "$dir/pnpm-lock.yaml" && ! -f "$dir/yarn.lock" ]]; then
      continue
    fi
    echo "$dir"
  done < <(
    find . -maxdepth 4 -name package.json \
      -not -path '*/node_modules/*' \
      -not -path '*/.next/*' \
      -not -path '*/dist/*' \
      -not -path '*/build/*' \
      -print0
  ) | sort -u
}

# Install every independently locked project before running a root typecheck:
# monorepo roots can include nested source files in their tsconfig.
while IFS= read -r dir; do
  install_node_project "$dir"
done < <(node_project_dirs)

while IFS= read -r dir; do
  verify_node_project "$dir"
done < <(node_project_dirs)

if [[ -x ./mvnw ]]; then
  ./mvnw --batch-mode -DskipTests package
elif [[ -f pom.xml ]]; then
  mvn --batch-mode -DskipTests package
fi

if [[ -x ./gradlew ]]; then
  ./gradlew classes testClasses
fi

if [[ -f pyproject.toml && -f uv.lock ]]; then
  uv sync --frozen
  if uv run python -c 'import importlib.util,sys;sys.exit(0 if importlib.util.find_spec("pytest") else 1)'; then
    uv run pytest
  fi
elif [[ -f requirements.txt ]]; then
  python3 -m venv .verify-venv
  .verify-venv/bin/pip install --disable-pip-version-check -r requirements.txt
  if .verify-venv/bin/python -c 'import importlib.util,sys;sys.exit(0 if importlib.util.find_spec("pytest") else 1)'; then
    .verify-venv/bin/pytest
  fi
fi
