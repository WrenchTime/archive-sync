#!/usr/bin/env bash
# Runs sync.sh on this machine with your own `gh` login, inside a container so
# macOS's bash 3.2 is not a problem. Same arguments as sync.sh (--dry-run).
# Needs Docker, and a `gh` login with the repo and workflow scopes.

set -euo pipefail
cd "$(dirname "$0")"

token=$(gh auth token)
docker run --rm -e GH_TOKEN="$token" -v "$PWD:/w:ro" -w /w alpine:3.20 \
    sh -c 'apk add -q bash github-cli git >/dev/null && bash sync.sh "$@"' sh "$@"
