add_executable(gcpkg-intercept InterceptMain.cpp)

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(gcpkg-intercept PRIVATE -Wall -Wextra)
endif()
