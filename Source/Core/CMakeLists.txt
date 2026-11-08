add_executable(gcpkg
    main.cpp
    Engine.cpp
    Process.cpp
)

target_link_libraries(gcpkg PRIVATE PkgConfig::LUA PkgConfig::YAMLCPP)

target_compile_definitions(gcpkg PRIVATE
    GCPKG_SOURCE_ROOT="${CMAKE_SOURCE_DIR}"
    GCPKG_BINARY_ROOT="${CMAKE_BINARY_DIR}"
)

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(gcpkg PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()
