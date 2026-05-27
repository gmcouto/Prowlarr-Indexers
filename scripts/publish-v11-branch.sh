#!/usr/bin/env bash
#
# Rebuild the orphan v11 branch from master:
# - definitions/v11/*.yml
# - custom-definitions/v11/*.yml (overrides same filenames)
# Packaged into v11.zip at the branch root (flat archive, no folders inside).
# Force-pushed to origin/v11.

set -euo pipefail

SOURCE_BRANCH="${SOURCE_BRANCH:-master}"
TARGET_BRANCH="${TARGET_BRANCH:-v11}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
BASE_DEFINITIONS_DIR="${BASE_DEFINITIONS_DIR:-definitions/v11}"
CUSTOM_DEFINITIONS_DIR="${CUSTOM_DEFINITIONS_DIR:-custom-definitions/v11}"
V11_ZIP_NAME="${V11_ZIP_NAME:-v11.zip}"

log() {
    echo "[publish-v11] $*"
}

die() {
    echo "[publish-v11] ERROR: $*" >&2
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
trap 'rm -rf "$TEMP_DIR"' EXIT

copy_definition_files "$BASE_DEFINITIONS_DIR" "$TEMP_DIR"
copy_definition_files "$CUSTOM_DEFINITIONS_DIR" "$TEMP_DIR"

file_count="$(find "$TEMP_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | wc -l | tr -d ' ')"
if [[ "$file_count" -eq 0 ]]; then
    die "No v11 definition files found in ${BASE_DEFINITIONS_DIR} or ${CUSTOM_DEFINITIONS_DIR}"
fi

log "Prepared ${file_count} definition file(s) from ${SOURCE_BRANCH} (${SOURCE_SHA})"

command -v zip >/dev/null || die "'zip' is required but not installed"

ZIP_PATH="$(mktemp --suffix=.zip)"
trap 'rm -rf "$TEMP_DIR" "$ZIP_PATH"' EXIT
create_flat_zip "$TEMP_DIR" "$ZIP_PATH"
log "Created ${V11_ZIP_NAME} with ${file_count} file(s) at archive root"

if git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
    git branch -D "$TARGET_BRANCH"
fi

git checkout --orphan "$TARGET_BRANCH"
git reset

find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

cp -f "$ZIP_PATH" "./${V11_ZIP_NAME}"
git add -A

COMMIT_MESSAGE="Publish v11 definitions from ${SOURCE_BRANCH} (${SOURCE_SHA})"
git commit -m "$COMMIT_MESSAGE"

log "Force pushing ${TARGET_BRANCH} to ${ORIGIN_REMOTE}..."
git push --force "$ORIGIN_REMOTE" "$TARGET_BRANCH"

log "Published ${V11_ZIP_NAME} (${file_count} definition file(s)) to ${ORIGIN_REMOTE}/${TARGET_BRANCH}"
