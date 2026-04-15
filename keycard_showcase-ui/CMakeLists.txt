# Install QML and metadata — relative to CMAKE_INSTALL_PREFIX
# Default: cmake --install build --prefix ~/.local/share/Logos/LogosApp
set(KEYCARD_SHOWCASE_UI_DIR "plugins/keycard_showcase-ui")

install(FILES
    plugins/keycard_showcase-ui/manifest.json
    plugins/keycard_showcase-ui/metadata.json
    DESTINATION "${KEYCARD_SHOWCASE_UI_DIR}"
)

install(FILES
    qml/Main.qml
    DESTINATION "${KEYCARD_SHOWCASE_UI_DIR}"
)

# Mirror to LogosBasecamp (same as keycard-ui)
install(CODE "
    set(SRC \"\${CMAKE_INSTALL_PREFIX}/plugins/keycard_showcase-ui\")
    set(DST \"\$ENV{HOME}/.local/share/Logos/LogosBasecamp/plugins/keycard_showcase-ui\")
    message(STATUS \"Mirroring keycard_showcase-ui to LogosBasecamp: \${DST}\")
    file(COPY \"\${SRC}/\" DESTINATION \"\${DST}\")
    message(STATUS \"Mirror complete\")
")
