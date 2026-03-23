cmake_minimum_required(VERSION 3.28)
project(keycard-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find Qt6 (Core required, Nfc optional for mobile)
find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)

# Find OpenSSL (for keycard-qt's secp256k1 ECDH)
find_package(OpenSSL REQUIRED)

# Find libsodium (for secure memory wiping)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium REQUIRED IMPORTED_TARGET libsodium)

# Find PC/SC (for direct reader detection)
pkg_check_modules(pcsclite REQUIRED IMPORTED_TARGET libpcsclite)

# Add keycard-qt library
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/keycard-qt/CMakeLists.txt")
    message(FATAL_ERROR
        "keycard-qt submodule not initialized. Run:\n"
        "  git submodule update --init --recursive\n"
        "Or clone with:\n"
        "  git clone --recursive <repo-url>")
endif()
add_subdirectory(external/keycard-qt)

# Include subdirectories
add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
