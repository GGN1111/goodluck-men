cmake_minimum_required(VERSION 3.22)
project(signalready_llama CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Flutter's debug variant configures the native build with CMAKE_BUILD_TYPE=debug,
# which the Android NDK toolchain leaves unoptimized (-O0). llama.cpp is unusably
# slow unoptimized (prompt prefill drops to ~3 tok/s on a mid-range phone), so
# force -O2 onto every translation unit, including the llama.cpp subdirectory.
# Later flags win in clang, so this overrides any earlier -g/-O0.
add_compile_options(-O2)

# Vendored llama.cpp lives at <repo_root>/vendor/llama.cpp. This CMakeLists is
# at <repo_root>/apps/mobile/android/app/src/main/cpp, so 7 levels up.
get_filename_component(VENDOR_LLAMA
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../../vendor/llama.cpp"
    ABSOLUTE)

# CPU-only static llama.cpp (no tests/tools/network; no host-native CPU flags
# so cross-compiling for arm64 stays correct).
set(BUILD_SHARED_LIBS       OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS       OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS       OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER      OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON      OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP         OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL              OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS        OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES     OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE             OFF CACHE BOOL "" FORCE)
set(GGML_BLAS               OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP             OFF CACHE BOOL "" FORCE)
set(GGML_CUDA               OFF CACHE BOOL "" FORCE)
set(GGML_METAL              OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN             OFF CACHE BOOL "" FORCE)
set(GGML_OPENCL             OFF CACHE BOOL "" FORCE)
set(GGML_SYCL               OFF CACHE BOOL "" FORCE)
set(GGML_RPC                OFF CACHE BOOL "" FORCE)
# Disable the ARM llamafile sgemm: it uses AArch64-only f16 NEON intrinsics
# that break any non-arm64 build; the portable path is plenty for our use.
set(GGML_LLAMAFILE          OFF CACHE BOOL "" FORCE)

# GGML_NATIVE must stay OFF (it probes the Windows host, not the device).
# Target the ISA explicitly instead: armv8.2-a is the floor for every arm64-v8a
# device we ship to, and +fp16/+dotprod roughly halve prompt-prefill time.
# Specialized kernels stay runtime-gated by getauxval (ggml-feats.h), so the
# build remains safe on older CPUs.
if (CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
    set(GGML_CPU_ARM_ARCH "armv8.2-a+fp16+dotprod" CACHE STRING "" FORCE)
endif()

add_subdirectory(${VENDOR_LLAMA} ${CMAKE_CURRENT_BINARY_DIR}/llama_build)

# Single libllama.so for Dart (DynamicLibrary.open('libllama.so')). The shim is
# the only source; --whole-archive pulls in every llama.cpp C API symbol so the
# .so is self-contained (no separate libggml*.so to package).
add_library(signalready_llama SHARED llama_shim.cpp)
set_target_properties(signalready_llama PROPERTIES OUTPUT_NAME llama)
target_include_directories(signalready_llama PRIVATE ${VENDOR_LLAMA}/include)
target_link_libraries(signalready_llama PRIVATE
    -Wl,--whole-archive llama -Wl,--no-whole-archive
    log)
