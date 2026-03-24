# Find Logos SDK (environment variable from flake.nix in Phase 5)
if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    set(LOGOS_CPP_SDK "/nix/store/047dmhc4gi7yib02i1fbwidxpksqvcc2-logos-cpp-sdk")
endif()

if(DEFINED ENV{LOGOS_LIBLOGOS_HEADERS})
    set(LOGOS_LIBLOGOS_HEADERS "$ENV{LOGOS_LIBLOGOS_HEADERS}")
else()
    set(LOGOS_LIBLOGOS_HEADERS "/nix/store/092zxk8qbm9zxqigq1z0a5l901a068cz-logos-liblogos-headers-0.1.0/include")
endif()

# Debug option
option(KEYCARD_DEBUG "Enable verbose keycard debug logging" OFF)

# Plugin sources
set(PLUGIN_SOURCES
    src/plugin.h
    src/plugin.cpp
    src/KeycardBridge.h
    src/KeycardBridge.cpp
    src/FilePairingStorage.h
    src/FilePairingStorage.cpp
)

# Copy metadata to build dir (so moc can find it)
configure_file(
    src/plugin_metadata.json
    ${CMAKE_CURRENT_BINARY_DIR}/src/plugin_metadata.json
    COPYONLY
)

# Build MODULE library (not SHARED)
add_library(keycard_plugin MODULE ${PLUGIN_SOURCES})
set_target_properties(keycard_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "keycard_plugin"
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

# Include Logos SDK headers + keycard-qt headers
target_include_directories(keycard_plugin PRIVATE
    src
    "${LOGOS_LIBLOGOS_HEADERS}"
    "${LOGOS_CPP_SDK}/include"
    "${LOGOS_CPP_SDK}/include/cpp"
    "${LOGOS_CPP_SDK}/include/core"
    "${CMAKE_SOURCE_DIR}/external/keycard-qt/include"
)

# Link Qt + Logos SDK (static) + keycard-qt + OpenSSL + libsodium + PC/SC
target_link_libraries(keycard_plugin PRIVATE
    Qt6::Core
    "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
    keycard-qt
    OpenSSL::Crypto
    PkgConfig::sodium
    PkgConfig::pcsclite
)

# Link Qt6::Nfc if available (mobile platforms)
if(TARGET Qt6::Nfc)
    target_link_libraries(keycard_plugin PRIVATE Qt6::Nfc)
endif()

# Enable debug logging if requested
if(KEYCARD_DEBUG)
    target_compile_definitions(keycard_plugin PRIVATE KEYCARD_DEBUG)
    message(STATUS "Keycard debug logging enabled")
endif()

# Install paths (use LogosBasecamp for development)
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecamp")
set(KEYCARD_MODULE_DIR "${LOGOS_APP_DATA}/modules/keycard")

# Cleanup stale backups (Lesson #33)
install(CODE "
    set(_modules_dir \"${LOGOS_APP_DATA}/modules\")
    file(GLOB _old_keycard \"\${_modules_dir}/keycard.*\")
    foreach(_dir \${_old_keycard})
        message(STATUS \"Removing old keycard module: \${_dir}\")
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")

# Install .so and manifest
install(TARGETS keycard_plugin
    LIBRARY DESTINATION "${KEYCARD_MODULE_DIR}"
)
install(FILES modules/keycard/manifest.json
    DESTINATION "${KEYCARD_MODULE_DIR}"
)

# Note: libkeycard.so removed - now using keycard-qt (native C++/Qt)
