# Install QML and metadata
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecamp")
set(AUTH_SHOWCASE_UI_DIR "${LOGOS_APP_DATA}/plugins/auth_showcase-ui")

install(FILES
    plugins/auth_showcase-ui/manifest.json
    plugins/auth_showcase-ui/metadata.json
    DESTINATION "${AUTH_SHOWCASE_UI_DIR}"
)

install(FILES
    qml/Main.qml
    DESTINATION "${AUTH_SHOWCASE_UI_DIR}"
)
