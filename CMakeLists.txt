# ── Builder mode ─────────────────────────────────────────────────────────────
# Activated when logos-module-builder sets LOGOS_MODULE_BUILDER_ROOT in the
# nix build environment.  Everything after the return() is ignored.
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    cmake_minimum_required(VERSION 3.14)
    project(KeycardPlugin LANGUAGES CXX)

    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

    find_package(OpenSSL REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(sodium   REQUIRED IMPORTED_TARGET libsodium)
    pkg_check_modules(pcsclite REQUIRED IMPORTED_TARGET libpcsclite)

    logos_module(
        NAME keycard
        # keycard-qt is staged into lib/ by the builder's externalLibCopies step:
        #   lib/libkeycard-qt.a  +  lib/keycard-qt/*.h
        EXTERNAL_LIBS keycard-qt
        LINK_LIBRARIES OpenSSL::Crypto PkgConfig::sodium PkgConfig::pcsclite
        INCLUDE_DIRS keycard-core/src
        SOURCES
            keycard-core/src/plugin.h
            keycard-core/src/plugin.cpp
            keycard-core/src/KeycardBridge.h
            keycard-core/src/KeycardBridge.cpp
            keycard-core/src/FilePairingStorage.h
            keycard-core/src/FilePairingStorage.cpp
            keycard-core/src/secure_buffer.h
    )
    return()
endif()

# ── Standalone / dev build ───────────────────────────────────────────────────
# Used by IDEs, CI without the Nix builder, or direct cmake invocations.
cmake_minimum_required(VERSION 3.28)
project(keycard-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(FetchContent)

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)
find_package(OpenSSL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium   REQUIRED IMPORTED_TARGET libsodium)
pkg_check_modules(pcsclite REQUIRED IMPORTED_TARGET libpcsclite)

# keycard-qt: prefer local submodule, then env-var override, then FetchContent
if(DEFINED KEYCARD_QT_SOURCE_DIR)
    message(STATUS "Using keycard-qt from: ${KEYCARD_QT_SOURCE_DIR}")
    add_subdirectory(${KEYCARD_QT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/keycard-qt)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/keycard-qt/CMakeLists.txt")
    message(STATUS "Using local keycard-qt submodule")
    add_subdirectory(external/keycard-qt)
else()
    message(STATUS "Fetching keycard-qt from GitHub")
    FetchContent_Declare(
        keycard-qt
        GIT_REPOSITORY https://github.com/status-im/keycard-qt.git
        GIT_TAG        5cd0b0d22659fd8564c749787fc86c1374b00223
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(keycard-qt)
endif()

add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
add_subdirectory(keycard_showcase-core)
add_subdirectory(keycard_showcase-ui)
