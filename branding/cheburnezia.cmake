# Branding overrides for the Cheburnezia fork.
#
# Passed to CMake as an initial-cache script:
#
#     cmake -C branding/cheburnezia.cmake -S . -B build
#
# Every CLIENT_* variable in client/cmake/branding/*.cmake is declared as
#     if(NOT X)
#         set(X "<amnezia default>" CACHE ...)
#     endif()
# so anything seeded here wins and the upstream default is skipped. Nothing in
# this file touches an upstream file, which is why merges from upstream can
# never clobber the branding.

set(CLIENT_TARGET_NAME      "Cheburnezia"         CACHE STRING "")
set(CLIENT_APPLICATION_NAME "Cheburnezia"         CACHE STRING "")
set(CLIENT_ORGANIZATION_NAME "Cheburnezia.ORG"    CACHE STRING "")
set(CLIENT_APP_INSTANCE_NAME "CheburneziaInstance" CACHE STRING "")

# Play Store version lookup (MarketplaceUpdateController). The upstream default
# points at Amnezia's Play listing, which is always ahead of the fork, so every
# launch showed "Update available". The fork has no listing, the lookup fails
# and the prompt is skipped. Keep in sync with applicationId in
# client/android/build.gradle.kts.
set(CLIENT_ANDROID_PACKAGE  "org.cheburnezia.vpn" CACHE STRING "")

# Fork release number. APP_VERSION stays the upstream one (the Amnezia gateway
# sees it as cliVersion, so a made-up version could break API servers), and the
# fork's own releases are counted here instead. Bump it once per published
# release: deploy/release_android.sh tags the release as
# v<upstream version>-ch<CHEBURNEZIA_BUILD> and refuses to reuse a tag.
set(CHEBURNEZIA_BUILD 2 CACHE STRING "Cheburnezia release number")

# GitHub repository whose latest release the app checks for updates
# (ForkUpdateController). Same as REPO in deploy/release_android.sh.
set(CHEBURNEZIA_UPDATE_REPO "bifidotich/cheburnezia-client" CACHE STRING "")

# UI strings that call the app "Amnezia" and the About page links. translations.cmake
# runs right after project(${CLIENT_TARGET_NAME}), generates the .ts files from
# upstream's with translations/overrides.json applied and points CLIENT_TS_FILES
# at them. The GitHub link on the About page follows CHEBURNEZIA_UPDATE_REPO.
set(CMAKE_PROJECT_${CLIENT_TARGET_NAME}_INCLUDE
    "${CMAKE_CURRENT_LIST_DIR}/translations.cmake" CACHE FILEPATH "")

# Android refuses to install an APK over one with the same or higher
# versionCode. Upstream's code only grows and the fork number only grows, so
# their sum is strictly increasing across fork releases and upstream merges.
set(APP_ANDROID_VERSION_CODE_OFFSET ${CHEBURNEZIA_BUILD} CACHE STRING "")

# CLIENT_KEYCHAIN_NAME defaults to "${CLIENT_APPLICATION_NAME}-Keychain",
# so it follows the name above on its own.

# Deliberately NOT overridden:
#
# CLIENT_TS_PREFIX      - translation files on disk are named amneziavpn_*.ts;
#                         changing the prefix makes CMake look for files that
#                         do not exist, and the app looks up the .qm files by
#                         it. translations.cmake keeps the prefix for the
#                         files it generates.
# CLIENT_SERVICE_NAME   - becomes SERVICE_NAME, which the desktop client uses to
#                         check that "<name>.exe" is running before connecting.
#                         The service binary itself is hard-coded as
#                         AmneziaVPN-service in service/server/CMakeLists.txt and
#                         in the installer scripts (WiX, post_install/uninstall),
#                         so a different name here makes the client never see
#                         the service and refuse to connect.