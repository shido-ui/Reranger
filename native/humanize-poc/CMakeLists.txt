cmake_minimum_required(VERSION 3.20)
project(humanize_poc CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")

include_directories(include)

add_library(humanize_spike STATIC
    src/humanize_spike.cpp
)

enable_testing()

add_executable(test_humanize_spike
    test/test_humanize_spike.cpp
)
target_link_libraries(test_humanize_spike PRIVATE humanize_spike)
add_test(NAME test_humanize_spike COMMAND test_humanize_spike)
