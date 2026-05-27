#!/usr/bin/env bash
#
# Merge upstream Prowlarr/Indexers master into this fork's master branch.
# Fork-only paths (custom definitions) are preserved on merge conflicts.

set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/Prowlarr/Indexers.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
TARGET_BRANCH="${TARGET_BRANCH:-master}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
CUSTOM_PATHS="${CUSTOM_PATHS:-custom-definitions}"

log() {
    echo "[sync-upstream] $*"
}

die() {
    echo "[sync-upstream] ERROR: $*" >&2
    exit 1
}

is_under_custom_paths() {
    local file="$1"
    local prefix

    IFS=',' read -ra custom_prefixes <<< "$CUSTOM_PATHS"
    for prefix in "${custom_prefixes[@]}"; do
        prefix="${prefix// /}"
        [[ -z "$prefix" ]] && continue
        if [[ "$file" == "$prefix" || "$file" == "$prefix/"* ]]; then
            return 0
        fi
    done

    return 1
}

resolve_custom_conflicts() {
    local unresolved=0
    local file

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if is_under_custom_paths "$file"; then
            log "Keeping fork version for custom path: $file"
            git checkout --ours -- "$file"
            git add -- "$file"
        else
            unresolved=1
            log "Unresolved conflict remains: $file"
        fi
    done < <(git diff --name-only --diff-filter=U)

    if [[ "$unresolved" -eq 1 ]]; then
        return 1
    fi

    return 0
}

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    log "Adding upstream remote: $UPSTREAM_REPO"
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_REPO"
fi

log "Fetching ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}..."
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" --prune

if git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
    git checkout "$TARGET_BRANCH"
else
    die "Target branch '${TARGET_BRANCH}' does not exist locally"
fi

if [[ "${FORCE_SYNC:-false}" != "true" ]] && git merge-base --is-ancestor "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" HEAD; then
    log "Already up to date with ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
    exit 0
fi

UPSTREAM_SHA="$(git rev-parse --short "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")"
MERGE_MESSAGE="Sync upstream Prowlarr/Indexers ${UPSTREAM_BRANCH} (${UPSTREAM_SHA})"

log "Merging ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} (${UPSTREAM_SHA}) into ${TARGET_BRANCH}..."
set +e
git merge --no-edit "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" -m "$MERGE_MESSAGE"
merge_status=$?
set -e

if [[ "$merge_status" -ne 0 ]]; then
    if git diff --name-only --diff-filter=U | grep -q .; then
        log "Attempting to preserve custom definition paths: ${CUSTOM_PATHS}"
        if resolve_custom_conflicts; then
            git commit --no-edit
            log "Merge completed after preserving custom paths"
        else
            git merge --abort
            die "Merge failed with unresolved conflicts outside custom definition paths"
        fi
    else
        git merge --abort || true
        die "Merge failed (exit code ${merge_status})"
    fi
fi

if git diff --quiet "$ORIGIN_REMOTE/$TARGET_BRANCH"..HEAD 2>/dev/null; then
    log "Merge produced no changes to push"
    exit 0
fi

log "Pushing ${TARGET_BRANCH} to ${ORIGIN_REMOTE}..."
git push "$ORIGIN_REMOTE" "$TARGET_BRANCH"

log "Upstream sync completed successfully"
