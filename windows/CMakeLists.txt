# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "better_libtorrent_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# If buildFromSource is defined, build from source
if(DEFINED ENV{TORRENT_ENGINE_BUILD_FROM_SOURCE})
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
  set(better_libtorrent_flutter_bundled_libraries
    $<TARGET_FILE:better_libtorrent_flutter>
    PARENT_SCOPE
  )
else()
  set(PREBUILT_URL "https://github.com/ayman708-UX/better_libtorrent_flutter/releases/download/v0.0.7/torrent_engine-windows.zip")
  set(ZIP_PATH "${CMAKE_CURRENT_BINARY_DIR}/torrent_engine-windows.zip")
  set(EXTRACT_DIR "${CMAKE_CURRENT_BINARY_DIR}/prebuilt")

  if(NOT EXISTS "${EXTRACT_DIR}/engine-windows-VC-WIN64A/torrent_engine.dll")
    message(STATUS "Downloading prebuilt Windows binaries from ${PREBUILT_URL}")
    file(DOWNLOAD "${PREBUILT_URL}" "${ZIP_PATH}" STATUS DOWNLOAD_STATUS)
    list(GET DOWNLOAD_STATUS 0 DOWNLOAD_CODE)
    if(NOT DOWNLOAD_CODE EQUAL 0)
      message(FATAL_ERROR "Failed to download prebuilt binaries: ${DOWNLOAD_STATUS}")
    endif()
    
    file(ARCHIVE_EXTRACT INPUT "${ZIP_PATH}" DESTINATION "${EXTRACT_DIR}")
  endif()

  # Provide the DLL to Flutter
  set(better_libtorrent_flutter_bundled_libraries
    "${EXTRACT_DIR}/engine-windows-VC-WIN64A/torrent_engine.dll"
    PARENT_SCOPE
  )
endif()
