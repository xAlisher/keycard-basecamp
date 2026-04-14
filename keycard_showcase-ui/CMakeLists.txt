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
