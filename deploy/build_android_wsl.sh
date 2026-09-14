#!/bin/bash
# Builds a signed Android APK with DNSTT support from a WSL2/Linux environment.
#
# libdnstt.so is no longer built here: client/cmake/android.cmake compiles the
# Go module in client/3rd/dnstt with the NDK toolchain as part of the CMake
# build, so a plain ./deploy/build.sh produces it too.
set -e

export ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk}
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.3.11579264}
export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}
export QT_ROOT_PATH=${QT_ROOT_PATH:-/opt/Qt/6.10.0}
export QT_INSTALL_DIR=${QT_INSTALL_DIR:-/opt/Qt}
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
export PATH="/root/go/bin:/usr/local/go/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:${PATH}"

ABI=${ABI:-arm64-v8a}
BUILD_TOOLS=${BUILD_TOOLS:-$ANDROID_HOME/build-tools/35.0.0}
KEYSTORE=${KEYSTORE:-/opt/debug.keystore}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANDROID_BUILD_DIR="${ROOT_DIR}/deploy/build/client/android-build"
cd "${ROOT_DIR}"

# Fork branding: overrides the CLIENT_* cache variables from client/cmake/branding/.
export CMAKE_EXTRA_ARGS="${CMAKE_EXTRA_ARGS:--C ${ROOT_DIR}/branding/cheburnezia.cmake}"

command -v go >/dev/null || { echo "go is required to build libdnstt.so" >&2; exit 1; }

# The gradle project signs the release variants itself and fails :packageOssRelease
# outright when no keystore is configured, so the keystore has to exist and be
# exported before build.sh reaches androiddeployqt.
if [ ! -f "${KEYSTORE}" ]; then
    keytool -genkey -v -keystore "${KEYSTORE}" -storepass android -alias androiddebugkey \
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
fi
export QT_ANDROID_KEYSTORE_PATH="${KEYSTORE}"
export QT_ANDROID_KEYSTORE_ALIAS=androiddebugkey
export QT_ANDROID_KEYSTORE_STORE_PASS=android

echo "=== 1. Building C++ core, libdnstt.so and Qt resources ==="
# -f wipes deploy/build. Without it CMakeCache keeps the previous run's
# ANDROID_ABI and Qt toolchain while --abi only updates QT_ANDROID_ABIS, so
# conan resolves dependencies for the wrong architecture.
bash ./deploy/build.sh -t android --abi "${ABI}" -f

echo "=== 2. Injecting QML plugins into libs.xml ==="
python3 "${ROOT_DIR}/deploy/patch_libs_xml.py" "${ANDROID_BUILD_DIR}"

echo "=== 3. Assembling the APK ==="
chmod +x "${ANDROID_BUILD_DIR}/gradlew"
(cd "${ANDROID_BUILD_DIR}" && ./gradlew assembleRelease)

echo "=== 4. Aligning and signing ==="
# The billing flavours (oss/play) split the output directory, so the old
# release/ path only exists on pre-flavour builds. oss is the non-Play build.
APK_OUT="${ANDROID_BUILD_DIR}/build/outputs/apk"
for candidate in \
    "${APK_OUT}/${FLAVOUR:-oss}/release/android-build-${FLAVOUR:-oss}-release.apk" \
    "${APK_OUT}/release/android-build-release-unsigned.apk" \
    "${APK_OUT}/android-build-release-unsigned.apk"
do
    [ -f "$candidate" ] && { UNSIGNED_APK="$candidate"; break; }
done
if [ -z "${UNSIGNED_APK:-}" ]; then
    echo "No APK found under ${APK_OUT}" >&2
    find "${APK_OUT}" -name '*.apk' >&2
    exit 1
fi
echo "Packaging ${UNSIGNED_APK}"

ALIGNED_APK="$(mktemp -u /tmp/AmneziaVPN-aligned-XXXXXX.apk)"
FINAL_APK="${ROOT_DIR}/deploy/build/AmneziaVPN-dnstt.apk"

"${BUILD_TOOLS}/zipalign" -f -p 4 "${UNSIGNED_APK}" "${ALIGNED_APK}"
"${BUILD_TOOLS}/apksigner" sign --ks "${KEYSTORE}" --ks-pass pass:android --key-pass pass:android \
    --out "${FINAL_APK}" "${ALIGNED_APK}"
rm -f "${ALIGNED_APK}"

echo "APK signed -> ${FINAL_APK}"
