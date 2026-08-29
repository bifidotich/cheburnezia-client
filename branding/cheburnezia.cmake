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
set(CLIENT_SERVICE_NAME     "Cheburnezia-service" CACHE STRING "")
set(CLIENT_ORGANIZATION_NAME "Cheburnezia.ORG"    CACHE STRING "")
set(CLIENT_APP_INSTANCE_NAME "CheburneziaInstance" CACHE STRING "")

# CLIENT_KEYCHAIN_NAME defaults to "${CLIENT_APPLICATION_NAME}-Keychain",
# so it follows the name above on its own.

# Deliberately NOT overridden:
#
# CLIENT_TS_PREFIX      - translation files on disk are named amneziavpn_*.ts;
#                         changing the prefix makes CMake look for files that
#                         do not exist. Override only together with
#                         CLIENT_TS_FILES pointing at renamed copies.
# CLIENT_ANDROID_PACKAGE - used only for the Play Store version lookup, not for
#                         the real applicationId (that lives in
#                         client/android/build.gradle.kts).
