#!/usr/bin/env bash
# Keeps the WrenchTime archive in step with its upstreams.
#
#   1. forks every OBDb repository, plus the single repositories in EXTRA_FORKS,
#      into the archive organization (only the ones not forked yet);
#   2. fast-forwards every fork to its upstream (merge-upstream);
#   3. mirrors the repositories in MIRRORS, which cannot be forks because
#      GitHub allows one fork per network per owner.
#
# An upstream that disappears makes its fork's sync fail and leaves the fork
# as it was on the last good run, which is the point of the archive.
#
# Needs GH_TOKEN: a fine-grained token owned by the archive organization with
# Administration, Contents and Workflows read/write on all repositories.
# Usage: sync.sh [--dry-run]

set -uo pipefail

ARCHIVE_ORG="${ARCHIVE_ORG:-WrenchTime}"
UPSTREAM_ORGS=(OBDb)
EXTRA_FORKS=(meatpiHQ/wican-fw foerbsnavi/OBDex)
MIRRORS=(mcgyver78/WiCAN_W906)
# Forked before everything else: what the app reads directly. GitHub caps how
# many repositories an owner may create in a while, so the first run cannot
# fork everything, and these must not wait behind 900 others.
PRIORITY=(OBDb/obdb.community meatpiHQ/wican-fw foerbsnavi/OBDex)
# Names the archive uses for itself; an upstream repository with one of these
# names is forked as "<upstream owner>-<name>" instead.
RESERVED=(.github archive-sync)
FORK_PAUSE="${FORK_PAUSE:-3}"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
forked=0; failed_in_a_row=0; fork_failed=(); deferred=0; creation_paused=0; synced=0; unchanged=0; sync_failed=(); mirrored=0; mirror_failed=()

log() { printf '%s\n' "$*" >&2; }

# GitHub's cap on creating repositories: not a failure, the next run goes on.
is_creation_limit() {
    grep -qiE 'submitted too quickly|too many repositories' <<<"$1"
}

is_reserved() {
    local name="$1" r
    for r in "${RESERVED[@]}"; do [[ "$r" == "$name" ]] && return 0; done
    return 1
}

# Upstream full name -> name of its fork in the archive.
fork_name() {
    local owner="${1%%/*}" name="${1##*/}"
    if is_reserved "$name"; then printf '%s-%s' "$owner" "$name"; else printf '%s' "$name"; fi
}

# Runs a write call, retrying on GitHub's secondary rate limit.
api_write() {
    local attempt out
    for attempt in 1 2 3 4; do
        if out=$(gh api "$@" 2>&1); then printf '%s' "$out"; return 0; fi
        if grep -qiE 'rate limit|abuse detection|HTTP 429' <<<"$out"; then
            log "  rate limited, waiting $((attempt * 90)) s: $out"
            sleep $((attempt * 90))
            continue
        fi
        printf '%s' "$out"; return 1
    done
    printf '%s' "$out"; return 1
}

log "Reading the archive organization"
declare -A archive_branch=() archive_is_fork=()
while IFS=$'\t' read -r name branch fork; do
    archive_branch["$name"]="$branch"
    archive_is_fork["$name"]="$fork"
done < <(gh api "orgs/$ARCHIVE_ORG/repos" --paginate --jq '.[] | [.name, .default_branch, .fork] | @tsv')
log "  ${#archive_branch[@]} repositories"

upstreams=()
for org in "${UPSTREAM_ORGS[@]}"; do
    mapfile -t -O "${#upstreams[@]}" upstreams < <(gh api "orgs/$org/repos" --paginate --jq '.[].full_name')
done
upstreams+=("${EXTRA_FORKS[@]}")
log "  ${#upstreams[@]} upstream repositories"

# Priority first, then everything else once.
ordered=("${PRIORITY[@]}")
for up in "${upstreams[@]}"; do
    [[ " ${PRIORITY[*]} " == *" $up "* ]] || ordered+=("$up")
done

log "Mirroring"
for up in "${MIRRORS[@]}"; do
    name="${up##*/}"
    log "  mirror $up -> $ARCHIVE_ORG/$name"
    (( DRY_RUN )) && continue
    if [[ -z "${archive_branch[$name]+x}" ]]; then
        description=$(gh api "repos/$up" --jq '.description // ""' 2>/dev/null)
        if ! out=$(gh repo create "$ARCHIVE_ORG/$name" --public --disable-wiki --disable-issues \
            --description "Mirror of $up. ${description}" 2>&1); then
            if is_creation_limit "$out"; then
                log "  GitHub's repository creation limit reached, the next run goes on"
                creation_paused=1; deferred=$((deferred + 1))
            else
                log "    failed: $out"; mirror_failed+=("$up")
            fi
            continue
        fi
    fi
    work=$(mktemp -d)
    if git clone --quiet --bare "https://github.com/$up.git" "$work/repo.git" &&
        git -C "$work/repo.git" push --quiet \
            "https://x-access-token:${GH_TOKEN}@github.com/$ARCHIVE_ORG/$name.git" \
            'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'; then
        mirrored=$((mirrored + 1))
    else
        mirror_failed+=("$up")
    fi
    rm -rf "$work"
done

log "Forking what is missing"
for up in "${ordered[@]}"; do
    name=$(fork_name "$up")
    [[ -n "${archive_branch[$name]+x}" ]] && continue
    if (( creation_paused )); then deferred=$((deferred + 1)); continue; fi
    log "  fork $up -> $ARCHIVE_ORG/$name"
    if (( DRY_RUN )); then forked=$((forked + 1)); continue; fi
    if out=$(api_write -X POST "repos/$up/forks" -f organization="$ARCHIVE_ORG" -f name="$name" -F default_branch_only=false); then
        forked=$((forked + 1)); failed_in_a_row=0
    elif is_creation_limit "$out"; then
        log "  GitHub's repository creation limit reached, the next run goes on"
        creation_paused=1; deferred=$((deferred + 1))
        continue
    else
        log "    failed: $out"; fork_failed+=("$up")
        # The same refusal on every fork means the token, not the repository.
        failed_in_a_row=$((failed_in_a_row + 1))
        if (( failed_in_a_row >= 5 )); then log "  5 forks failed in a row, stopping"; break; fi
    fi
    sleep "$FORK_PAUSE"
done

log "Syncing forks"
for name in "${!archive_branch[@]}"; do
    [[ "${archive_is_fork[$name]}" == "true" ]] || continue
    (( DRY_RUN )) && continue
    if out=$(api_write -X POST "repos/$ARCHIVE_ORG/$name/merge-upstream" -f branch="${archive_branch[$name]}"); then
        if grep -q '"merge_type":"none"' <<<"$out"; then unchanged=$((unchanged + 1)); else synced=$((synced + 1)); fi
    else
        log "  $name: $out"; sync_failed+=("$name")
    fi
done


{
    echo "## Archive sync"
    (( DRY_RUN )) && echo "_Dry run: nothing was written._"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| New forks | $forked |"
    echo "| Forks updated | $synced |"
    echo "| Forks already current | $unchanged |"
    echo "| Mirrors pushed | $mirrored |"
    echo "| Left for the next run (creation limit) | $deferred |"
    echo "| Fork failures | ${#fork_failed[@]} |"
    echo "| Sync failures | ${#sync_failed[@]} |"
    echo "| Mirror failures | ${#mirror_failed[@]} |"
    for list in fork_failed sync_failed mirror_failed; do
        declare -n items="$list"
        if (( ${#items[@]} )); then
            echo; echo "**${list/_/ }**"; echo
            printf -- '- `%s`\n' "${items[@]}"
        fi
        unset -n items
    done
} | tee -a "$summary" >&2

# A sync failure is expected when an upstream vanishes, so only failures to
# create something fail the run.
(( ${#fork_failed[@]} + ${#mirror_failed[@]} == 0 ))
