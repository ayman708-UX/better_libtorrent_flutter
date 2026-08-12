# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(better_libtorrent_flutter_library VERSION 0.0.1 LANGUAGES CXX C)

add_library(better_libtorrent_flutter SHARED
  "torrent_bridge.cpp"
)

set_target_properties(better_libtorrent_flutter PROPERTIES
  PUBLIC_HEADER torrent_bridge.h
  OUTPUT_NAME "better_libtorrent_flutter"
)

target_compile_definitions(better_libtorrent_flutter PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(better_libtorrent_flutter PRIVATE "-Wl,-z,max-page-size=16384")
endif()
