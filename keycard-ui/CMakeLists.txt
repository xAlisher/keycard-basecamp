# Install QML and metadata (use LogosApp for new plugin discovery)
set(LOGOS_APP_DATA "$ENV{HOME}/.local/share/Logos/LogosApp")
set(KEYCARD_UI_DIR "${LOGOS_APP_DATA}/plugins/keycard_ui")

install(FILES
    plugins/keycard_ui/manifest.json
    plugins/keycard_ui/metadata.json
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
