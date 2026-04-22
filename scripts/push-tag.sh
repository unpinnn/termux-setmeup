#!/usr/bin/env bash
set -euo pipefail

# Push a release tag in v* format to trigger GitHub Actions release/publish flows.
# Workflow policy:
# 1) Require clean working tree.
# 2) Auto-bump Cargo.toml + package.json versions and commit.
# 3) Push current branch to origin.
# 4) Tag the latest remote commit (origin/<branch>), not local-only state.
# Usage:
#   ./scripts/push-tag.sh                       # auto bump patch from latest v* tag
#   ./scripts/push-tag.sh 0.0.10
#   ./scripts/push-tag.sh v0.0.10

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [version|vX.Y.Z]"
  exit 1
fi

auto_next_tag() {
  local latest major minor patch
  latest="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1 || true)"
  if [[ -z "$latest" ]]; then
    echo "v0.0.1"
    return
  fi
  latest="${latest#v}"
  IFS='.' read -r major minor patch <<<"$latest"
  patch=$((patch + 1))
  echo "v${major}.${minor}.${patch}"
}

set_cargo_version() {
  local version="$1"
  awk -v new_ver="$version" '
    BEGIN { replaced = 0 }
    /^version = "/ && replaced == 0 {
      print "version = \"" new_ver "\""
      replaced = 1
      next
    }
    { print }
  ' Cargo.toml > Cargo.toml.tmp
  mv Cargo.toml.tmp Cargo.toml
}

set_package_json_version() {
  local version="$1"
  awk -v new_ver="$version" '
    BEGIN { replaced = 0 }
    /^[[:space:]]*"version"[[:space:]]*:/ && replaced == 0 {
      match($0, /^[[:space:]]*/)
      indent = substr($0, RSTART, RLENGTH)
      print indent "\"version\": \"" new_ver "\","
      replaced = 1
      next
    }
    { print }
  ' package.json > package.json.tmp
  mv package.json.tmp package.json
}

read_cargo_version() {
  awk -F'"' '/^version = "/{print $2; exit}' Cargo.toml
}

read_npm_version() {
  if command -v node >/dev/null 2>&1; then
    node -p "require('./package.json').version"
    return
  fi
  awk -F'"' '/"version"\s*:\s*"/{print $4; exit}' package.json
}

arg1="${1:-}"
branch="$(git branch --show-current)"

if [[ -z "$branch" ]]; then
  echo "Detached HEAD is not supported for this release flow."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before tagging."
  exit 1
fi

git fetch --tags origin

if [[ -z "$arg1" ]]; then
  tag="$(auto_next_tag)"
else
  if ! [[ "$arg1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid tag format: $arg1"
    echo "Expected: vMAJOR.MINOR.PATCH (example: v0.0.10)"
    exit 1
  fi
  tag="${arg1#v}"
  tag="v${tag}"
fi

if ! [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid tag format: $tag"
  echo "Expected: vMAJOR.MINOR.PATCH (example: v0.0.10)"
  exit 1
fi

tag_version="${tag#v}"
if git rev-parse --verify "$tag" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Tag already exists: $tag"
  exit 1
fi

echo "Bumping versions to ${tag_version}..."
set_cargo_version "$tag_version"
set_package_json_version "$tag_version"

cargo_version="$(read_cargo_version)"
npm_version="$(read_npm_version)"
if [[ "$cargo_version" != "$tag_version" || "$npm_version" != "$tag_version" ]]; then
  echo "Failed to set versions correctly."
  echo "Cargo.toml:   $cargo_version"
  echo "package.json: $npm_version"
  exit 1
fi

git add Cargo.toml package.json
git commit -m "release: bump version to ${tag_version}"

echo "Pushing current branch '${branch}' to origin..."
git push origin "$branch"
git fetch origin "$branch" --quiet

echo "Creating tag ${tag} at origin/${branch}..."
git tag "$tag" "origin/${branch}"

echo "Pushing tag ${tag} to origin..."
git push origin "$tag"

echo "Done. GitHub workflows listening on tags 'v*' should now start."
