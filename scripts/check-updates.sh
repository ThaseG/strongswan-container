#!/bin/bash
# check-updates.sh - check upstream for new strongSwan, strongswan-exporter and
# Go releases and update the repository in place.
#
# When something newer is found it updates versions.sh, the ARG defaults in
# server/strongswan.dockerfile and CHANGELOG.md, and bumps IMAGE_VERSION
# (patch). Review the result with `git diff`.
#
# Output:
#   stdout          Markdown summary (used as the pull request body)
#   stderr          progress log
#   GITHUB_OUTPUT   changed=true|false, title=<PR/commit title>,
#                   image_version=<new IMAGE_VERSION> (when run in Actions)
#
# Requirements: bash 4+, curl, git, perl, python3, md5sum/sha256sum (or macOS md5/shasum)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source ./versions.sh

DOCKERFILE="server/strongswan.dockerfile"
CHANGELOG="CHANGELOG.md"
EXPORTER_REPO="https://github.com/ThaseG/strongswan-exporter"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { echo "$*" >&2; }

# newer <candidate> <current> - true if candidate sorts after current
newer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# major <version> - leading number, ignoring a "v" prefix
major() { local v="${1#v}"; echo "${v%%.*}"; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
md5() { if command -v md5sum >/dev/null; then md5sum "$1"; else command md5 -q "$1"; fi | cut -d' ' -f1; }

# set_shell_var <NAME> <value> - NAME='value' in versions.sh
set_shell_var() {
    NAME="$1" VALUE="$2" perl -pi -e \
        's/^\Q$ENV{NAME}\E=.*$/$ENV{NAME}=\x27$ENV{VALUE}\x27/' versions.sh
    grep -qx "$1='$2'" versions.sh || { log "ERROR: could not update $1 in versions.sh"; exit 1; }
}

# set_docker_arg <NAME> <value> - ARG NAME=value in the Dockerfile
set_docker_arg() {
    NAME="$1" VALUE="$2" perl -pi -e \
        's/^ARG \Q$ENV{NAME}\E=.*$/ARG $ENV{NAME}=$ENV{VALUE}/' "$DOCKERFILE"
    grep -qx "ARG $1=$2" "$DOCKERFILE" || { log "ERROR: could not update ARG $1 in $DOCKERFILE"; exit 1; }
}

changes=()       # human-readable lines for the changelog / PR body
title_parts=()   # short fragments for the PR title
warnings=()
rows=()          # summary table rows

# --- strongSwan ---------------------------------------------------------------
log "Checking strongSwan (current ${STRONGSWAN_VERSION})..."
latest_ss=$(curl -fsSL https://download.strongswan.org/ |
    grep -oE 'strongswan-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' |
    sed -E 's/^strongswan-(.*)\.tar\.gz$/\1/' | sort -uV | tail -1)
[ -n "$latest_ss" ] || { log "ERROR: could not determine latest strongSwan release"; exit 1; }

if newer "$latest_ss" "$STRONGSWAN_VERSION"; then
    log "  new release ${latest_ss}, downloading to compute checksum"
    tarball="$WORK/strongswan-${latest_ss}.tar.gz"
    curl -fsSL -o "$tarball" "https://download.strongswan.org/strongswan-${latest_ss}.tar.gz"
    expected_md5=$(curl -fsSL "https://download.strongswan.org/strongswan-${latest_ss}.tar.gz.md5" | cut -d' ' -f1)
    actual_md5=$(md5 "$tarball")
    if [ "$expected_md5" != "$actual_md5" ]; then
        log "ERROR: MD5 mismatch for strongSwan ${latest_ss} (expected ${expected_md5}, got ${actual_md5})"
        exit 1
    fi
    new_sha=$(sha256 "$tarball")
    set_shell_var STRONGSWAN_VERSION "$latest_ss"
    set_shell_var STRONGSWAN_SHA256 "$new_sha"
    set_docker_arg STRONGSWAN_VERSION "$latest_ss"
    set_docker_arg STRONGSWAN_SHA256 "$new_sha"
    changes+=("strongSwan ${STRONGSWAN_VERSION} → ${latest_ss} ([NEWS](https://github.com/strongswan/strongswan/blob/${latest_ss}/NEWS))")
    title_parts+=("strongSwan ${latest_ss}")
    rows+=("| strongSwan | ${STRONGSWAN_VERSION} | ${latest_ss} | updated (SHA-256 \`${new_sha}\`) |")
    [ "$(major "$latest_ss")" != "$(major "$STRONGSWAN_VERSION")" ] &&
        warnings+=("strongSwan major version change (${STRONGSWAN_VERSION} → ${latest_ss}): check configure options and plugin changes in NEWS.")
else
    rows+=("| strongSwan | ${STRONGSWAN_VERSION} | ${latest_ss} | up to date |")
fi

# --- strongswan-exporter --------------------------------------------------------
log "Checking strongswan-exporter (current ${EXPORTER_VERSION})..."
latest_exp=$(git ls-remote --tags --refs "$EXPORTER_REPO" |
    sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[ -n "$latest_exp" ] || { log "ERROR: could not determine latest exporter tag"; exit 1; }

if newer "$latest_exp" "$EXPORTER_VERSION"; then
    log "  new release ${latest_exp}"
    set_shell_var EXPORTER_VERSION "$latest_exp"
    set_docker_arg EXPORTER_VERSION "$latest_exp"
    changes+=("strongswan-exporter ${EXPORTER_VERSION} → ${latest_exp} ([changes](${EXPORTER_REPO}/compare/${EXPORTER_VERSION}...${latest_exp}))")
    title_parts+=("strongswan-exporter ${latest_exp}")
    rows+=("| strongswan-exporter | ${EXPORTER_VERSION} | ${latest_exp} | updated |")
    [ "$(major "$latest_exp")" != "$(major "$EXPORTER_VERSION")" ] &&
        warnings+=("strongswan-exporter major version change (${EXPORTER_VERSION} → ${latest_exp}): check for metric or config changes.")
else
    rows+=("| strongswan-exporter | ${EXPORTER_VERSION} | ${latest_exp} | up to date |")
fi

# --- Go -------------------------------------------------------------------------
# Tracked as major.minor; the golang:<major.minor> image already follows patches.
log "Checking Go (current ${GO_VERSION})..."
latest_go=$(curl -fsSL 'https://go.dev/dl/?mode=json' | python3 -c '
import json, sys
versions = [r["version"][2:] for r in json.load(sys.stdin) if r.get("stable")]
minors = {".".join(v.split(".")[:2]) for v in versions}
print(sorted(minors, key=lambda v: tuple(map(int, v.split("."))))[-1])
')
[ -n "$latest_go" ] || { log "ERROR: could not determine latest Go release"; exit 1; }

if newer "$latest_go" "$GO_VERSION"; then
    go_tag="${latest_go}-trixie"
    if curl -fsS -o /dev/null "https://hub.docker.com/v2/repositories/library/golang/tags/${go_tag}"; then
        log "  new release ${latest_go}"
        set_shell_var GO_VERSION "$latest_go"
        set_docker_arg GO_VERSION "$latest_go"
        changes+=("Go ${GO_VERSION} → ${latest_go} ([release notes](https://go.dev/doc/go${latest_go}))")
        title_parts+=("Go ${latest_go}")
        rows+=("| Go | ${GO_VERSION} | ${latest_go} | updated |")
    else
        log "  Go ${latest_go} released, but image golang:${go_tag} does not exist yet - skipping"
        rows+=("| Go | ${GO_VERSION} | ${latest_go} | skipped: \`golang:${go_tag}\` image not published yet |")
    fi
else
    rows+=("| Go | ${GO_VERSION} | ${latest_go} | up to date |")
fi

# --- Results --------------------------------------------------------------------
gh_output() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT" || true; }

summary_table() {
    echo "| Component | Current | Latest | Status |"
    echo "| --------- | ------- | ------ | ------ |"
    printf '%s\n' "${rows[@]}"
}

if [ "${#changes[@]}" -eq 0 ]; then
    log "Everything is up to date."
    gh_output "changed=false"
    echo "## Weekly version check"
    echo
    echo "Everything is up to date."
    echo
    summary_table
    exit 0
fi

# Bump IMAGE_VERSION (patch)
if [[ ! "$IMAGE_VERSION" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    log "ERROR: IMAGE_VERSION '${IMAGE_VERSION}' is not vX.Y.Z"
    exit 1
fi
old_image="$IMAGE_VERSION"
new_image="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
set_shell_var IMAGE_VERSION "$new_image"

# Changelog row (newest first, right below the table header)
source ./versions.sh
ubuntu_version=$(sed -n 's/^ARG UBUNTU_VERSION=//p' "$DOCKERFILE")
change_text=$(printf '%s </br> ' "${changes[@]}")
row="| ${new_image}  | $(date -u +%F)   | **StrongSwan Version**: ${STRONGSWAN_VERSION} </br> **StrongSwan-exporter Version**: ${EXPORTER_VERSION} </br> **Golang Version**: ${GO_VERSION} </br> **Ubuntu Version**: ${ubuntu_version} </br> Automated dependency update: </br> ${change_text%' </br> '} | See linked upstream release notes. | None known |"
ROW="$row" perl -0pi -e 's/^(\| -------.*\n)/$1$ENV{ROW}\n/m' "$CHANGELOG"
grep -qF "| ${new_image}  |" "$CHANGELOG" || { log "ERROR: could not add changelog row"; exit 1; }

title="Update $(IFS=,; echo "${title_parts[*]}" | sed 's/,/, /g') (${new_image})"
log "$title"
gh_output "changed=true"
gh_output "image_version=${new_image}"
gh_output "title=${title}"

echo "## ${title}"
echo
echo "Automated weekly version check found new upstream releases."
echo
summary_table
echo
echo "### Changes"
printf -- '- %s\n' "${changes[@]}"
if [ "${#warnings[@]}" -gt 0 ]; then
    echo
    echo "### ⚠️ Needs attention"
    printf -- '- %s\n' "${warnings[@]}"
fi
echo
echo "Files updated: \`versions.sh\`, \`${DOCKERFILE}\`, \`${CHANGELOG}\` (IMAGE_VERSION ${old_image} → ${new_image})."
echo
echo "Merge only after the Validation Workflow (build, Trivy, e2e) passes on this pull request."
