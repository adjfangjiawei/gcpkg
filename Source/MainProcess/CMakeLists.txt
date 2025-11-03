add_subdirectory(GcpkgMetaCommand)

add_library(MainProcess
    CreatePortFile.cpp
    CreateProjectFile.cpp
    InstallProcess.cpp
    BuildSystemAnalysis.cpp
    DependenciesAnalysis.cpp

    InstallationOrchestrator.cpp
    InstallationContext.cpp
    EnvironmentSetup.cpp
    BuildPlanner.cpp
)
target_include_directories(MainProcess PUBLIC ${PROJECT_ROOT_DIR})
target_link_libraries(MainProcess PUBLIC tomlplusplus::tomlplusplus Basic GcpkgMetaCommand)