# Fork translations: upstream's .ts files with the app-name strings rewritten,
# plus an English file for the same strings. See translations/overrides.json.
#
# Included right after project(${CLIENT_TARGET_NAME}) in client/CMakeLists.txt
# through CMAKE_PROJECT_<name>_INCLUDE (set in cheburnezia.cmake), so it runs on
# every configure without touching an upstream file. Setting CLIENT_TS_FILES
# here, before client/CMakeLists.txt reads it, makes qt6_add_translations use the
# generated files instead of client/translations/.

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(_ch_ts_script    ${CMAKE_CURRENT_LIST_DIR}/translations/generate_ts.py)
set(_ch_ts_overrides ${CMAKE_CURRENT_LIST_DIR}/translations/overrides.json)
set(_ch_ts_out_dir   ${CMAKE_CURRENT_BINARY_DIR}/cheburnezia-translations)
file(GLOB _ch_ts_upstream CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/translations/${CLIENT_TS_PREFIX}_*.ts)

execute_process(
    COMMAND ${Python3_EXECUTABLE} ${_ch_ts_script}
        --overrides ${_ch_ts_overrides}
        --out-dir ${_ch_ts_out_dir}
        --prefix ${CLIENT_TS_PREFIX}
        --app-name ${CLIENT_APPLICATION_NAME}
        --repo ${CHEBURNEZIA_UPDATE_REPO}
        ${_ch_ts_upstream}
    RESULT_VARIABLE _ch_ts_result
    OUTPUT_VARIABLE _ch_ts_files
    ERROR_VARIABLE _ch_ts_errors
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT _ch_ts_result EQUAL 0)
    message(FATAL_ERROR "Generating fork translations failed:\n${_ch_ts_errors}")
endif()
if(_ch_ts_errors)
    message(WARNING "Fork translations:\n${_ch_ts_errors}")
endif()

string(REPLACE "\n" ";" CLIENT_TS_FILES "${_ch_ts_files}")

# Re-run after an upstream merge changes a .ts file, or after editing overrides.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${_ch_ts_script} ${_ch_ts_overrides} ${_ch_ts_upstream})
