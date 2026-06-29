cmake_minimum_required(VERSION 3.22)
project(holyc C ASM)

enable_language(ASM)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Os -fno-stack-protector")

add_library(holyc SHARED
    bridge.c
    compiler.c
    runtime.S
)

target_include_directories(holyc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

set_target_properties(holyc PROPERTIES LINK_FLAGS "-nostdlib++")
