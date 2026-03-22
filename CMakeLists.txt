cmake_minimum_required(VERSION 3.28)
project(keycard-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find Qt6, libsodium, and libpcsclite
find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium REQUIRED IMPORTED_TARGET libsodium)

# Find libpcsclite (link against system library)
find_library(PCSCLITE_LIBRARY pcsclite REQUIRED)
if(NOT PCSCLITE_LIBRARY)
    message(FATAL_ERROR "libpcsclite not found - install libpcsclite-dev or pcsclite package")
endif()
message(STATUS "Found libpcsclite: ${PCSCLITE_LIBRARY}")

# Include subdirectories
add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
