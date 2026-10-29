#!/usr/bin/env bash
# Publishes the trouble-code catalog the WrenchTime app downloads.
#
# Reads the YAML of the archive's OBDex fork with dtc-catalog.ts and writes
# dtc-generic-en.json, dtc-generic-de.json and a README to the dtc-catalog
# repository, committing only when a file changed.
#
# Needs GH_TOKEN with Contents write on the dtc-catalog repository, and bun.
# Usage: dtc-catalog.sh [--dry-run]

set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE_ORG="${ARCHIVE_ORG:-WrenchTime}"
SOURCE="$ARCHIVE_ORG/OBDex"
TARGET="$ARCHIVE_ORG/dtc-catalog"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if ! gh api "repos/$SOURCE" --silent 2>/dev/null; then
    echo "$SOURCE is not forked yet, skipping the DTC catalog"
    exit 0
fi
if ! gh api "repos/$TARGET" --silent 2>/dev/null; then
    if (( DRY_RUN )); then echo "Dry run: $TARGET would be created"; exit 0; fi
    if ! out=$(gh repo create "$TARGET" --public --disable-wiki --disable-issues \
        --description "Generic OBD-II trouble-code titles the WrenchTime app downloads, built daily from the OBDex fork. CC0." 2>&1); then
        if grep -qiE 'submitted too quickly|too many repositories' <<<"$out"; then
            echo "GitHub's repository creation limit reached, the next run creates $TARGET"
            exit 0
        fi
        echo "$out" >&2; exit 1
    fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 "https://github.com/$SOURCE.git" "$work/obdex"
commit=$(git -C "$work/obdex" rev-parse HEAD)
git clone --quiet "https://x-access-token:${GH_TOKEN}@github.com/$TARGET.git" "$work/out"

bun dtc-catalog.ts "$work/obdex/data/generic" "$work/out"

count() { bun -e "console.log(Object.keys(await Bun.file('$1').json()).length)"; }
en=$(count "$work/out/dtc-generic-en.json")
de=$(count "$work/out/dtc-generic-de.json")

cat > "$work/out/README.md" <<EOF
# dtc-catalog

Generic OBD-II trouble-code titles the WrenchTime app downloads, one flat
\`{ "CODE": "short title" }\` file per language, keys uppercase and sorted.

Built daily by [archive-sync](https://github.com/$ARCHIVE_ORG/archive-sync)
from the YAML under \`data/generic/\` of [$SOURCE](https://github.com/$SOURCE),
a fork of [foerbsnavi/OBDex](https://github.com/foerbsnavi/OBDex). Only the
short \`title\` of each entry is kept.

Licence: **CC0-1.0**, as the OBDex data.

- OBDex commit: \`$commit\`
- \`dtc-generic-en.json\`: $en codes
- \`dtc-generic-de.json\`: $de codes

Do not edit by hand: the next run overwrites every file.
EOF

cd "$work/out"
git add -A
# The README carries the commit, so compare the catalog files alone.
if git diff --cached --quiet -- dtc-generic-en.json dtc-generic-de.json && git rev-parse --verify --quiet HEAD >/dev/null; then
    echo "DTC catalog unchanged ($en codes)"
    exit 0
fi
git diff --cached --stat
if (( DRY_RUN )); then echo "Dry run: not pushed"; exit 0; fi
git -c user.name="WrenchTime archive" -c user.email="mncs.technologies@gmail.com" \
    commit --quiet -m "Catalog from OBDex ${commit:0:7}: $en codes"
git push --quiet origin HEAD:main
echo "DTC catalog published ($en codes)"
