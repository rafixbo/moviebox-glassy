# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(moviebox_glassy LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "moviebox_glassy")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Bundle the Visual C++ runtime DLLs (MSVCP140.dll, VCRUNTIME140.dll,
# VCRUNTIME140_1.dll) next to the executable. The exe and the video
# plugin link against them (verified with objdump on the shipped zip),
# but the CI zip previously did not contain them — on a Windows PC
# without the Visual C++ Redistributable installed the app would fail
# to start ("VCRUNTIME140.dll was not found"). This makes the zip
# self-contained on any Windows 10/11 machine.
#
# Run #9 lesson (verbose CI log, run 45178757682): NEVER use
# include(InstallRequiredSystemLibraries) here. That module adds its own
# install(PROGRAMS ... DESTINATION bin) rule, and the relative "bin"
# destination is resolved against CMAKE_INSTALL_PREFIX — which the
# Flutter template sets to the generator expression
# "$<TARGET_FILE_DIR:moviebox_glassy>". The install script runs in
# script mode, where generator expressions are NOT evaluated, so CMake
# tried to create a literal directory named
# ".../x64/$<TARGET_FILE_DIR:moviebox_glassy>/bin" and failed
# (cmake_install.cmake:362, MSB3073). The stock install() rules work
# because their DESTINATIONs carry the generator expression directly
# and the Visual Studio generator expands it at generation time.
# So: locate the DLLs ourselves and install them with a plain
# install(FILES ...) using the same DESTINATION form as the stock rules.
# A missing DLL is skipped with a message instead of breaking the build.
set(_vc_runtime_dlls "")
set(_vc_compiler "${CMAKE_CXX_COMPILER}")
if(NOT _vc_compiler)
  set(_vc_compiler "${CMAKE_C_COMPILER}")
endif()
if(_vc_compiler)
  # cl.exe lives at <VS>/VC/Tools/MSVC/<ver>/bin/HostX64/x64/cl.exe;
  # the redist DLLs live at <VS>/VC/Redist/MSVC/<ver>/x64/Microsoft.VC*.CRT/.
  get_filename_component(_vc_dir "${_vc_compiler}" DIRECTORY)
  get_filename_component(_vc_dir "${_vc_dir}/../../../../../.." ABSOLUTE)
  file(GLOB _vc_redist_crt_dirs
    "${_vc_dir}/Redist/MSVC/*/x64/Microsoft.VC*.CRT")
  if(_vc_redist_crt_dirs)
    list(SORT _vc_redist_crt_dirs)
    list(GET _vc_redist_crt_dirs -1 _vc_crt_dir)
    foreach(_dll_name IN ITEMS msvcp140.dll vcruntime140.dll vcruntime140_1.dll)
      set(_dll_path "${_vc_crt_dir}/${_dll_name}")
      if(EXISTS "${_dll_path}")
        list(APPEND _vc_runtime_dlls "${_dll_path}")
      else()
        message(STATUS "VC++ runtime DLL not found: ${_dll_path}")
      endif()
    endforeach()
  endif()
endif()
if(_vc_runtime_dlls)
  install(FILES ${_vc_runtime_dlls}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
else()
  message(STATUS "VC++ runtime DLLs not found under the MSVC redist dir; skipping (app still builds, target PC needs the VC++ Redistributable)")
endif()
