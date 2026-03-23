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

# Add keycard-qt library
add_subdirectory(external/keycard-qt)

# Include subdirectories
add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
