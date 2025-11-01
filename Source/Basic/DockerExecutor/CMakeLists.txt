add_library(DockerExecutor ExecuteInContainer.cpp RunContainer.cpp)
target_include_directories(DockerExecutor PUBLIC ${PROJECT_ROOT_DIR})