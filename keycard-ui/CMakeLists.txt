# Install QML and metadata (use LogosBasecamp for development)
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosBasecamp")
set(KEYCARD_UI_DIR "${LOGOS_APP_DATA}/plugins/keycard-ui")

install(FILES
    plugins/keycard-ui/manifest.json
    plugins/keycard-ui/metadata.json
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    qml/Main.qml
    qml/AuthWindow.qml
    keycard.png
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    icons/keycard.png
    DESTINATION "${KEYCARD_UI_DIR}/icons"
)
