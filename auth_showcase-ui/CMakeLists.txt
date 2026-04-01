# Install QML and metadata — relative to CMAKE_INSTALL_PREFIX
# Default: cmake --install build --prefix ~/.local/share/Logos/LogosApp
set(AUTH_SHOWCASE_UI_DIR "plugins/auth_showcase-ui")

install(FILES
    plugins/auth_showcase-ui/manifest.json
    plugins/auth_showcase-ui/metadata.json
    DESTINATION "${AUTH_SHOWCASE_UI_DIR}"
)

install(FILES
    qml/Main.qml
    DESTINATION "${AUTH_SHOWCASE_UI_DIR}"
)
