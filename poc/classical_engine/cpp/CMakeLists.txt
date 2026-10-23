cmake_minimum_required(VERSION 3.20)
project(classical_engine_native CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")

include_directories(include)

add_library(classical_engine_native STATIC
    src/classical_engine.cpp
)

enable_testing()

add_executable(test_classical_engine
    test/test_classical_engine.cpp
)
target_link_libraries(test_classical_engine PRIVATE classical_engine_native)
add_test(NAME test_classical_engine COMMAND test_classical_engine)

add_executable(benchmark_native
    test/benchmark_native.cpp
)
target_link_libraries(benchmark_native PRIVATE classical_engine_native)
