# Install QML and metadata — relative to CMAKE_INSTALL_PREFIX
# Default: cmake --install build --prefix ~/.local/share/Logos/LogosApp
set(KEYCARD_UI_DIR "plugins/keycard-ui")

install(FILES
    plugins/keycard-ui/manifest.json
    plugins/keycard-ui/metadata.json
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    qml/Main.qml
    qml/DebugPanel.qml
    qml/PinEntryScreen.qml
    qml/ManagementDashboard.qml
    qml/AuthorizationScreen.qml
    qml/ActivityLog.qml
    qml/DesignTokens.qml
    qml/qmldir
    keycard.png
    DESTINATION "${KEYCARD_UI_DIR}"
)

install(FILES
    icons/keycard.png
    icons/lock.svg
    icons/bolt.svg
    DESTINATION "${KEYCARD_UI_DIR}/icons"
)
