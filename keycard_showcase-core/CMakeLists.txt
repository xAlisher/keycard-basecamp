# Find Logos SDK
if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
    set(LOGOS_CPP_SDK "$ENV{LOGOS_CPP_SDK_ROOT}")
else()
    set(LOGOS_CPP_SDK "/nix/store/c23ijr4km1wc2jixw4siqmbw3yaqf4z2-logos-cpp-sdk")
endif()

if(DEFINED ENV{LOGOS_LIBLOGOS_HEADERS})
    set(LOGOS_LIBLOGOS_HEADERS "$ENV{LOGOS_LIBLOGOS_HEADERS}")
else()
    set(LOGOS_LIBLOGOS_HEADERS "/nix/store/lkr4jwcdh7k1yw5lisvpvaya4pq8qiv4-logos-liblogos-headers-0.1.0/include")
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
add_library(keycard_showcase_plugin MODULE ${PLUGIN_SOURCES})
set_target_properties(keycard_showcase_plugin PROPERTIES
    PREFIX ""
    OUTPUT_NAME "keycard_showcase_plugin"
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

# Include Logos SDK headers
target_include_directories(keycard_showcase_plugin PRIVATE
    src
    "${LOGOS_LIBLOGOS_HEADERS}"
    "${LOGOS_CPP_SDK}/include"
    "${LOGOS_CPP_SDK}/include/cpp"
    "${LOGOS_CPP_SDK}/include/core"
)

# Link Qt + Logos SDK
target_link_libraries(keycard_showcase_plugin PRIVATE
    Qt6::Core
    "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
)

# Install paths — relative to CMAKE_INSTALL_PREFIX
# Default: cmake --install build --prefix ~/.local/share/Logos/LogosApp
set(KEYCARD_SHOWCASE_MODULE_DIR "modules/keycard_showcase")

# Install .so and manifest
install(TARGETS keycard_showcase_plugin
    LIBRARY DESTINATION "${KEYCARD_SHOWCASE_MODULE_DIR}"
)
install(FILES modules/keycard_showcase/manifest.json
              modules/keycard_showcase/variant
    DESTINATION "${KEYCARD_SHOWCASE_MODULE_DIR}"
)

# Mirror to LogosBasecamp
install(CODE "
    set(SRC \"\${CMAKE_INSTALL_PREFIX}/modules/keycard_showcase\")
    set(DST \"\$ENV{HOME}/.local/share/Logos/LogosBasecamp/modules/keycard_showcase\")
    message(STATUS \"Mirroring keycard_showcase to LogosBasecamp: \${DST}\")
    file(COPY \"\${SRC}/\" DESTINATION \"\${DST}\")
    message(STATUS \"Mirror complete\")
")
