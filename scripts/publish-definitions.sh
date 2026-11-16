#!/usr/bin/env bash
#
# Rebuild an orphan definition-publish branch (e.g. v11, v12) from master:
# - definitions/<ver>/*.yml
# - definitions/v11/*.yml (fallback base for v12+: when a version folder has no
#   definition, the previous version's file is used — mirrors how upstream's
#   definition server serves older schema content under newer version URLs)
# - custom-definitions/<ver>/*.yml (gaucho overrides, same filenames win)
# Packaged into <ver>.zip at the branch root (flat archive, no folders inside).
# Force-pushed to origin/<ver>.

set -euo pipefail

SOURCE_BRANCH="${SOURCE_BRANCH:-master}"
TARGET_BRANCH="${TARGET_BRANCH:-v11}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
BASE_DEFINITIONS_DIR="${BASE_DEFINITIONS_DIR:-definitions/${TARGET_BRANCH}}"
CUSTOM_DEFINITIONS_DIR="${CUSTOM_DEFINITIONS_DIR:-custom-definitions/${TARGET_BRANCH}}"
FALLBACK_DEFINITIONS_DIR="${FALLBACK_DEFINITIONS_DIR:-definitions/v11}"
ZIP_NAME="${ZIP_NAME:-${TARGET_BRANCH}.zip}"

log() {
    echo "[publish-definitions] $*"
}

die() {
    echo "[publish-definitions] ERROR: $*" >&2
    exit 1
}

copy_definition_files() {
    local source_dir="$1"
    local destination_dir="$2"
    local file

    if [[ ! -d "$source_dir" ]]; then
        log "Skipping missing directory: $source_dir"
        return 0
    fi

    shopt -s nullglob
    for file in "$source_dir"/*.yml "$source_dir"/*.yaml; do
        cp -f "$file" "$destination_dir/"
        log "Added $(basename "$file") from ${source_dir}/"
    done
}

create_flat_zip() {
    local source_dir="$1"
    local output_zip="$2"
    local file files=()

    shopt -s nullglob
    for file in "$source_dir"/*.yml "$source_dir"/*.yaml; do
        files+=("$file")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        die "No definition files to include in ${output_zip}"
    fi

    rm -f "$output_zip"
    zip -j -q "$output_zip" "${files[@]}"
}

if ! git show-ref --verify --quiet "refs/heads/${SOURCE_BRANCH}"; then
    die "Source branch '${SOURCE_BRANCH}' does not exist locally"
fi

git checkout "$SOURCE_BRANCH"

SOURCE_SHA="$(git rev-parse --short HEAD)"
TEMP_DIR="$(mktemp -d)"

if [[ -d "$BASE_DEFINITIONS_DIR" ]]; then
    copy_definition_files "$BASE_DEFINITIONS_DIR" "$TEMP_DIR"
fi

# Fall back to the previous schema version's definitions for anything the
# target version folder does not define yet (upstream behaviour).
if [[ -n "${FALLBACK_DEFINITIONS_DIR:-}" ]] && [[ "$FALLBACK_DEFINITIONS_DIR" != "$BASE_DEFINITIONS_DIR" ]] && [[ -d "$FALLBACK_DEFINITIONS_DIR" ]]; then
    shopt -s nullglob
    fallback_count=0
    for file in "$FALLBACK_DEFINITIONS_DIR"/*.yml "$FALLBACK_DEFINITIONS_DIR"/*.yaml; do
        name="$(basename "$file")"
        if [[ ! -e "$TEMP_DIR/$name" ]]; then
            cp -f "$file" "$TEMP_DIR/"
            fallback_count=$((fallback_count + 1))
        fi
    done
    shopt -u nullglob
    if [[ "$fallback_count" -gt 0 ]]; then
        log "Filled ${fallback_count} definition(s) from fallback ${FALLBACK_DEFINITIONS_DIR}"
    fi
fi

copy_definition_files "$CUSTOM_DEFINITIONS_DIR" "$TEMP_DIR"

file_count="$(find "$TEMP_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | wc -l | tr -d ' ')"
if [[ "$file_count" -eq 0 ]]; then
    die "No ${TARGET_BRANCH} definition files found in ${BASE_DEFINITIONS_DIR} or ${CUSTOM_DEFINITIONS_DIR}"
fi

log "Prepared ${file_count} definition file(s) from ${SOURCE_BRANCH} (${SOURCE_SHA})"

command -v zip >/dev/null || die "'zip' is required but not installed"

ZIP_PATH="$(mktemp --suffix=.zip)"
trap 'rm -rf "$TEMP_DIR" "$ZIP_PATH"' EXIT
create_flat_zip "$TEMP_DIR" "$ZIP_PATH"
log "Created ${ZIP_NAME} with ${file_count} file(s) at archive root"

if git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
    git branch -D "$TARGET_BRANCH"
fi

git checkout --orphan "$TARGET_BRANCH"
git reset

find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

cp -f "$ZIP_PATH" "./${ZIP_NAME}"
git add -A

COMMIT_MESSAGE="Publish ${TARGET_BRANCH} definitions from ${SOURCE_BRANCH} (${SOURCE_SHA})"
git commit -m "$COMMIT_MESSAGE"

log "Force pushing ${TARGET_BRANCH} to ${ORIGIN_REMOTE}..."
git push --force "$ORIGIN_REMOTE" "$TARGET_BRANCH"

log "Published ${ZIP_NAME} (${file_count} definition file(s)) to ${ORIGIN_REMOTE}/${TARGET_BRANCH}"
