#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Source Citations
# ==============================================================================
# Purpose: Verify every `sources:` citation in wiki frontmatter resolves to
#          an existing file in raw/ — dangling citations break provenance.
# Usage: vault-tools.sh verify-sources
# Dependencies: Requires lib-utils.sh to be sourced first.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# Normalize citation entries (one per line): trim whitespace and quotes,
# unwrap the [[ ]] wikilink, drop any |display suffix, discard empties.
_strip_wikilinks() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e 's/^["'"'"']//' -e 's/["'"'"']$//' \
        -e 's/^\[\[//' -e 's/\]\]$//' \
        -e 's/|.*$//' \
        | { grep -v '^$' || true; }
}

# Get sources from frontmatter as newline-separated paths.
# Handles both the block-list and inline [] YAML forms, quoted or not.
# Usage: _fm_sources "$frontmatter"
_fm_sources() {
    local fm="$1"
    local in_sources=false
    echo "$fm" | while IFS= read -r line; do
        if [[ "$line" =~ ^sources: ]]; then
            in_sources=true
            if [[ "$line" =~ \[.*\] ]]; then
                # Inline form: sources: ["[[raw/a.md]]", "[[raw/b.md]]"] or []
                echo "$line" | sed 's/^sources:[[:space:]]*\[//' | sed 's/\][[:space:]]*$//' | tr ',' '\n'
                in_sources=false
            fi
            continue
        fi
        if $in_sources; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                # Drop the list marker; _strip_wikilinks trims the rest.
                echo "${line#*-}"
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done | _strip_wikilinks
}

cmd_verify_sources() {
    header "Verify Source Citations"

    local pages_with_sources=0
    local pages_verified=0
    local pages_dangling=0
    local missing_total=0

    subheader "Checking sources: citations against raw/"
    while IFS= read -r file; do
        local relative="${file#"${VAULT_ROOT}"/}"
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue

        local sources
        sources=$(_fm_sources "$fm")
        [[ -z "$sources" ]] && continue

        pages_with_sources=$((pages_with_sources + 1))
        local missing=()
        local src
        while IFS= read -r src; do
            [[ -z "$src" ]] && continue
            # Only raw/ citations are checked — that is what `sources:` is for.
            [[ "$src" != raw/* ]] && continue
            if [[ ! -f "${VAULT_ROOT}/${src}" ]]; then
                missing+=("$src")
            fi
        done <<< "$sources"

        if [[ ${#missing[@]} -gt 0 ]]; then
            pages_dangling=$((pages_dangling + 1))
            missing_total=$((missing_total + ${#missing[@]}))
            error "dangling: ${relative}"
            local m
            for m in "${missing[@]}"; do
                echo "      missing: ${m}"
            done
        else
            pages_verified=$((pages_verified + 1))
            ok "verified: ${relative}"
        fi
    done < <(wiki_files)

    subheader "Summary"
    echo "  Pages citing sources:  ${pages_with_sources}"
    echo "  Verified:              ${pages_verified}"
    echo "  Dangling:              ${pages_dangling}"
    echo "  Missing citations:     ${missing_total}"
    echo ""

    if [[ ${pages_dangling} -gt 0 ]]; then
        error "${pages_dangling} page(s) cite missing raw/ files"
        echo ""
        return 1
    fi
    ok "All source citations verified"
    echo ""
}
