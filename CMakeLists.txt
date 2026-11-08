cmake_minimum_required(VERSION 3.28)

# gcpkg: a thin C++ runtime + a Lua-driven package/project engine.
# The old TOML prototype under Source/MainProcess, Source/Basic is kept in the
# tree for reference but is intentionally NOT part of the build (see docs/ARCHITECTURE.md).
project(gcpkg LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED IMPORTED_TARGET lua5.4)
pkg_check_modules(YAMLCPP REQUIRED IMPORTED_TARGET yaml-cpp)

add_subdirectory(Source/Core)
add_subdirectory(Source/Intercept)

# The Lua engine and the port registry are data, not compiled code: adding a
# build-system adapter or a library port never requires recompiling gcpkg.
install(DIRECTORY lua/ DESTINATION share/gcpkg/lua)
install(DIRECTORY ports/ DESTINATION share/gcpkg/ports)
install(DIRECTORY examples/ DESTINATION share/gcpkg/examples)

message(STATUS "gcpkg source root : ${CMAKE_SOURCE_DIR}")
message(STATUS "gcpkg Lua 5.4     : ${LUA_VERSION}")
message(STATUS "gcpkg yaml-cpp    : ${YAMLCPP_VERSION}")
