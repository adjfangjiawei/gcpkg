add_library(GcpkgMetaCommand
    DecompressCommand.cpp DownloadCommand.cpp)
target_include_directories(GcpkgMetaCommand PUBLIC ${PROJECT_ROOT_DIR})
target_link_libraries(GcpkgMetaCommand PUBLIC tomlplusplus::tomlplusplus Basic archive_static CURL::libcurl)