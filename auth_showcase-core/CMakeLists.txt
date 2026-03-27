# Find Logos SDK
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

# Plugin sources
set(PLUGIN_SOURCES
    src/plugin.h
    src/plugin.cpp
)

# Copy metadata to build dir
configure_file(
    src/plugin_metadata.json
    ${CMAKE_CURRENT_BINARY_DIR}/src/plugin_metadata.json
    COPYONLY
)

# Build MODULE library
add_library(auth_showcase_plugin MODULE ${PLUGIN_SOURCES})
set_target_properties(auth_showcase_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "auth_showcase_plugin"
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

# Include Logos SDK headers
target_include_directories(auth_showcase_plugin PRIVATE
    src
    "${LOGOS_LIBLOGOS_HEADERS}"
    "${LOGOS_CPP_SDK}/include"
    "${LOGOS_CPP_SDK}/include/cpp"
    "${LOGOS_CPP_SDK}/include/core"
)

# Link Qt + Logos SDK
target_link_libraries(auth_showcase_plugin PRIVATE
    Qt6::Core
    "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
)

# Install paths
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecamp")
set(AUTH_SHOWCASE_MODULE_DIR "${LOGOS_APP_DATA}/modules/auth_showcase")

# Install .so and manifest
install(TARGETS auth_showcase_plugin
    LIBRARY DESTINATION "${AUTH_SHOWCASE_MODULE_DIR}"
)
install(FILES modules/auth_showcase/manifest.json
    DESTINATION "${AUTH_SHOWCASE_MODULE_DIR}"
)
