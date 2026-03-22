# Install QML and metadata
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecampDev")
set(KEYCARD_UI_DIR "${LOGOS_APP_DATA}/plugins/keycard_ui")

install(FILES
    plugins/keycard_ui/manifest.json
    plugins/keycard_ui/metadata.json
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    qml/Main.qml
    DESTINATION "${KEYCARD_UI_DIR}"
)
