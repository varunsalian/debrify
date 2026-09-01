cmake_minimum_required(VERSION 3.22)
project(debrify_tenvad C)

# Thin JNI shim over the prebuilt ten-vad neural VAD. Only ABIs with a
# prebuilt get a shim; on the others the Kotlin side simply finds no library
# and the subtitle auto-sync keeps its energy-based features.
set(TEN_VAD_LIB "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/${ANDROID_ABI}/libten_vad.so")
if(NOT EXISTS "${TEN_VAD_LIB}")
    message(STATUS "ten-vad: no prebuilt for ${ANDROID_ABI}; JNI shim skipped")
    return()
endif()

add_library(ten_vad SHARED IMPORTED)
set_target_properties(ten_vad PROPERTIES IMPORTED_LOCATION "${TEN_VAD_LIB}")

add_library(debrify_tenvad SHARED ten_vad_jni.c)
target_include_directories(debrify_tenvad PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_options(debrify_tenvad PRIVATE -fvisibility=hidden -Wall)
target_link_libraries(debrify_tenvad ten_vad)
