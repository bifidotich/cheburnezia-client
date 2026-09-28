#!/bin/bash
# Publishes an Android release of the fork to GitHub Releases.
#
#     ./deploy/release_android.sh [--skip-build] [--notes FILE] [--allow-dirty]
#
# 1. Reads the upstream version from CMakeLists.txt and the fork release number
#    CHEBURNEZIA_BUILD from branding/cheburnezia.cmake; the tag is
#    v<version>-ch<build>, e.g. v5.0.1.5-ch1.
# 2. Builds and signs the APK with deploy/build_android_wsl.sh (skip with
#    --skip-build to upload an APK that is already in deploy/build/).
# 3. Creates the GitHub release on the pushed HEAD commit with the APK and its
#    SHA256SUMS attached. The APK keeps a fixed name, so the newest one is always
#    at https://github.com/<repo>/releases/latest/download/Cheburnezia-<abi>.apk
#
# Requires the GitHub CLI, authenticated for the repository: gh auth login.
# After a release, bump CHEBURNEZIA_BUILD for the next one.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

REPO=${REPO:-bifidotich/cheburnezia-client}
ABI=${ABI:-arm64-v8a}
BUILD_TOOLS=${BUILD_TOOLS:-${ANDROID_HOME:-/opt/android-sdk}/build-tools/35.0.0}

SKIP_BUILD=0
ALLOW_DIRTY=0
NOTES_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build)  SKIP_BUILD=1 ;;
        --allow-dirty) ALLOW_DIRTY=1 ;;
        --notes)       NOTES_FILE="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }

UPSTREAM_VERSION=$(sed -n 's/.*set(AMNEZIAVPN_VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt | head -1)
UPSTREAM_CODE=$(sed -n 's/^set(APP_ANDROID_VERSION_CODE \([0-9]*\)).*/\1/p' CMakeLists.txt | head -1)
FORK_BUILD=$(sed -n 's/^set(CHEBURNEZIA_BUILD \([0-9]*\).*/\1/p' branding/cheburnezia.cmake | head -1)
[ -n "${UPSTREAM_VERSION}" ] || die "cannot read AMNEZIAVPN_VERSION from CMakeLists.txt"
[ -n "${UPSTREAM_CODE}" ]    || die "cannot read APP_ANDROID_VERSION_CODE from CMakeLists.txt"
[ -n "${FORK_BUILD}" ]       || die "cannot read CHEBURNEZIA_BUILD from branding/cheburnezia.cmake"

TAG="v${UPSTREAM_VERSION}-ch${FORK_BUILD}"
VERSION_CODE=$((UPSTREAM_CODE + FORK_BUILD))
APK_NAME="Cheburnezia-${ABI}"
APK="${ROOT_DIR}/deploy/build/${APK_NAME}.apk"

echo "Release ${TAG} (versionCode ${VERSION_CODE}, ${ABI}) -> ${REPO}"

# --- Preflight: everything that can fail cheaply goes before the long build.
command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated, run: gh auth login"
[ -z "${NOTES_FILE}" ] || [ -f "${NOTES_FILE}" ] || die "notes file not found: ${NOTES_FILE}"

if [ "${ALLOW_DIRTY}" = 0 ] && ! git diff --quiet HEAD --; then
    die "uncommitted changes; the release must match a pushed commit (--allow-dirty to override)"
fi

git fetch --quiet origin
HEAD_SHA=$(git rev-parse HEAD)
[ -n "$(git branch -r --contains "${HEAD_SHA}")" ] || die "HEAD ${HEAD_SHA:0:8} is not pushed to origin"

if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    die "tag ${TAG} already exists; bump CHEBURNEZIA_BUILD in branding/cheburnezia.cmake"
fi

# --- Build.
if [ "${SKIP_BUILD}" = 0 ]; then
    ABI="${ABI}" APK_NAME="${APK_NAME}" bash "${SCRIPT_DIR}/build_android_wsl.sh"
fi
[ -f "${APK}" ] || die "APK not found: ${APK}"

# A stale APK from an earlier build would install as the wrong version, or not
# at all. aapt2 lives in the WSL build environment; elsewhere just warn.
if [ -x "${BUILD_TOOLS}/aapt2" ]; then
    APK_CODE=$("${BUILD_TOOLS}/aapt2" dump badging "${APK}" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
    [ "${APK_CODE}" = "${VERSION_CODE}" ] || die "APK versionCode is ${APK_CODE}, expected ${VERSION_CODE}; rebuild"
else
    echo "warning: aapt2 not found, APK versionCode not checked" >&2
fi

(cd "$(dirname "${APK}")" && sha256sum "${APK_NAME}.apk" > SHA256SUMS)

# --- Publish. gh creates the tag on the remote at HEAD, so nothing is left
# behind if the release creation fails.
NOTES_ARGS=(--generate-notes)
[ -z "${NOTES_FILE}" ] || NOTES_ARGS=(--notes-file "${NOTES_FILE}")

gh release create "${TAG}" \
    --repo "${REPO}" \
    --target "${HEAD_SHA}" \
    --title "Cheburnezia ${UPSTREAM_VERSION}-ch${FORK_BUILD}" \
    "${NOTES_ARGS[@]}" \
    "${APK}" \
    "$(dirname "${APK}")/SHA256SUMS"

git fetch --quiet --tags origin

echo
echo "Published ${TAG}: https://github.com/${REPO}/releases/tag/${TAG}"
echo "Next: bump CHEBURNEZIA_BUILD to $((FORK_BUILD + 1)) in branding/cheburnezia.cmake and commit."
