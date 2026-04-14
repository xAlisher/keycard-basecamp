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
    qml/ActivityLog.qml
    qml/DesignTokens.qml
    qml/KeycardAuth.qml
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

# Mirror plugin UI to LogosBasecamp so the AppImage picks up the same build.
# LogosApp is the install prefix; LogosBasecamp is the AppImage runtime dir.
set(_LB "$ENV{HOME}/.local/share/Logos/LogosBasecamp/${KEYCARD_UI_DIR}")
install(CODE "
    set(_src \"\${CMAKE_INSTALL_PREFIX}/${KEYCARD_UI_DIR}\")
    set(_dst \"${_LB}\")
    message(STATUS \"Mirroring keycard-ui to LogosBasecamp: \${_dst}\")
    file(GLOB _files \"\${_src}/*\")
    foreach(_f \${_files})
        if(NOT IS_DIRECTORY \"\${_f}\")
            file(COPY \"\${_f}\" DESTINATION \"\${_dst}\")
        endif()
    endforeach()
    file(GLOB _icons \"\${_src}/icons/*\")
    foreach(_f \${_icons})
        file(COPY \"\${_f}\" DESTINATION \"\${_dst}/icons\")
    endforeach()
    message(STATUS \"Mirror complete\")
")
