# Install QML and metadata
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecampDev")
set(KEYCARD_UI_DIR "${LOGOS_APP_DATA}/plugins/keycard-ui")

install(FILES
    plugins/keycard-ui/manifest.json
    plugins/keycard-ui/metadata.json
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    qml/Main.qml
    DESTINATION "${KEYCARD_UI_DIR}"
)
