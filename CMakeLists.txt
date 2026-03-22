cmake_minimum_required(VERSION 3.28)
project(keycard-basecamp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find Qt6 and libsodium
find_package(Qt6 REQUIRED COMPONENTS Core Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(sodium REQUIRED IMPORTED_TARGET libsodium)

# Include subdirectories
add_subdirectory(keycard-core)
add_subdirectory(keycard-ui)
