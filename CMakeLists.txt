cmake_minimum_required(VERSION 3.30)
set(CMAKE_CXX_COMPILER clang++-22)
set(CMAKE_C_COMPILER clang-22)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(VCPKG_MANIFEST_MODE OFF)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address")
project(gcpkg LANGUAGES C CXX)

# 设置C++标准
set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PROJECT_ROOT_DIR ${CMAKE_SOURCE_DIR}/Source)

find_package(LLVM REQUIRED CONFIG)
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")
include(HandleLLVMOptions)
add_definitions(${LLVM_DEFINITIONS})
llvm_map_components_to_libnames(llvm_libs support core irreader)

add_subdirectory(extern/tomlplusplus)

add_subdirectory(Source)
