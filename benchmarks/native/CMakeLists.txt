cmake_minimum_required(VERSION 3.20)
project(process_start_benchmark LANGUAGES C)

if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "This benchmark requires Windows and the Microsoft C compiler.")
endif()

add_executable(process-start process-start.c)
target_compile_options(process-start PRIVATE /W4 /WX /O2)
set_target_properties(process-start PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
)
