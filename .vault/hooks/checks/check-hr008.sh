#!/usr/bin/env bash
# ==============================================================================
# HR-008: Index Registration
# ==============================================================================
# Rule: Every wiki/ file (except index.md, index-*.md sub-indexes, and log.md)
# must appear in wiki/index.md OR in any wiki/index-*.md sub-index (split
# index layout — see `vault-tools.sh index-split`).
# Enforcement: Rejects commits with unregistered wiki pages.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr008() {
    info "HR-008: Checking index registration..."
    local index_path="${VAULT_ROOT}/${INDEX_FILE}"

    if [[ ! -f "$index_path" ]]; then
        warn "HR-008: Index file not found at ${INDEX_FILE}. Skipping."
        return
    fi

    # Registration surface: the root index plus any split sub-indexes.
    # A page registered only in a sub-index counts as registered.
    local index_content sub
    index_content=$(cat "$index_path")
    for sub in "${VAULT_ROOT}/${WIKI_DIR}/index-"*.md; do
        [[ -f "$sub" ]] || continue
        index_content+=$'\n'"$(cat "$sub")"
    done

    while IFS= read -r -d '' file; do
        local relative_path="${file#${VAULT_ROOT}/}"
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip structural files: index.md, index-*.md sub-indexes, log.md
        if [[ "$relative_path" == "${WIKI_DIR}/index.md" ]] \
            || [[ "$relative_path" == "${WIKI_DIR}/index-"*.md ]] \
            || [[ "$relative_path" == "${WIKI_DIR}/log.md" ]]; then
            continue
        fi

        # Check if the file path or filename appears in the index surface.
        # Bash literal substring match: safe against regex metacharacters in
        # filenames, and avoids `echo | grep -q`, whose early exit can SIGPIPE
        # echo — under `set -o pipefail` that turns a successful match into a
        # false violation on large index content.
        local basename
        basename=$(basename "$relative_path")
        if [[ "$index_content" != *"$basename"* && "$index_content" != *"$relative_path"* ]]; then
            violation "HR-008" "$relative_path" "Not registered in ${INDEX_FILE} or any ${WIKI_DIR}/index-*.md sub-index. Run: bash .vault/scripts/vault-tools.sh index-update"
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-008: Index registration check complete"
}
