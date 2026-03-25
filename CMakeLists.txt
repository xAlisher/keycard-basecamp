cmake_minimum_required(VERSION 3.28)
project(keycard-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Fetch dependencies
include(FetchContent)

# Find Qt6 (Core and RemoteObjects required, Nfc optional for mobile)
find_package(Qt6 REQUIRED COMPONENTS Core RemoteObjects)
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)

# Find OpenSSL (for keycard-qt's secp256k1 ECDH)
find_package(OpenSSL REQUIRED)

# Find libsodium (for secure memory wiping)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium REQUIRED IMPORTED_TARGET libsodium)

# Find PC/SC (for direct reader detection)
# On macOS, use PCSC.framework; on Linux, use libpcsclite
if(NOT APPLE)
    pkg_check_modules(pcsclite REQUIRED IMPORTED_TARGET libpcsclite)
endif()

# Fetch keycard-qt (use local submodule, Nix-provided, or download)
if(DEFINED KEYCARD_QT_SOURCE_DIR)
    # Use externally-provided keycard-qt (e.g., from Nix)
    message(STATUS "Using keycard-qt from: ${KEYCARD_QT_SOURCE_DIR}")
    add_subdirectory(${KEYCARD_QT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/keycard-qt)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/keycard-qt/CMakeLists.txt")
    # Use local submodule if already checked out
    message(STATUS "Using local keycard-qt submodule")
    add_subdirectory(external/keycard-qt)
else()
    # Fetch from GitHub if not present (makes build reproducible from archives)
    message(STATUS "Fetching keycard-qt from GitHub")
    FetchContent_Declare(
        keycard-qt
        GIT_REPOSITORY https://github.com/status-im/keycard-qt.git
        GIT_TAG        3c01bc114f0a38e91147793e96d7a4ebd68301a6  # Pin to specific commit for reproducibility
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(keycard-qt)
endif()

# Include subdirectories
add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
