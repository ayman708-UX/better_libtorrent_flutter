cmake_minimum_required(VERSION 3.15)
if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()
project(torrent_engine)

# We need C++17 for libtorrent 2.x
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# The prebuilt static dependencies are passed via -DDEPS_DIR=...
if(NOT DEPS_DIR)
    message(FATAL_ERROR "DEPS_DIR must be specified (path to prebuilt static libraries)")
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${DEPS_DIR}/include
    ${CMAKE_SOURCE_DIR}/../third_party/boost
)

# Helper function to find a static library
macro(find_static_lib VAR_NAME NAMES)
    find_library(${VAR_NAME} 
        NAMES ${NAMES} 
        PATHS ${DEPS_DIR}/lib ${DEPS_DIR}/lib64 
        NO_DEFAULT_PATH
    )
    if(NOT ${VAR_NAME})
        message(FATAL_ERROR "Could not find library ${NAMES} in ${DEPS_DIR}/lib or lib64")
    endif()
endmacro()

# We build a SHARED library on Android/Linux/Windows, 
# but on iOS/macOS we build a STATIC library to be wrapped in an xcframework.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    add_library(torrent_engine STATIC torrent_bridge.cpp)
else()
    add_library(torrent_engine SHARED torrent_bridge.cpp)
endif()

if(WIN32)
    set_target_properties(torrent_engine PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()

# Add definitions needed by libtorrent
target_compile_definitions(torrent_engine PRIVATE 
    TORRENT_ABI_VERSION=2
    TORRENT_NO_DEPRECATE
    BOOST_ASIO_NO_DEPRECATED
    BOOST_ASIO_DISABLE_CONCEPTS
    TORRENT_USE_OPENSSL
    TORRENT_DISABLE_ENCRYPTION=OFF
    TORRENT_BRIDGE_EXPORTS
)

# Resolve libraries based on platform naming conventions
if(WIN32)
    find_static_lib(CRYPTO_LIB "libcrypto;crypto")
    find_static_lib(SSL_LIB "libssl;ssl")
    find_static_lib(DATACHANNEL_LIB "datachannel-static")
    find_static_lib(JUICE_LIB "juice-static")
    find_static_lib(USRSCTP_LIB "usrsctp")
    find_static_lib(TORRENT_LIB "torrent-rasterbar")
    
    # Windows system libraries
    target_link_libraries(torrent_engine PRIVATE ws2_32 crypt32 iphlpapi bcrypt)
else()
    find_static_lib(CRYPTO_LIB "libcrypto.a;crypto")
    find_static_lib(SSL_LIB "libssl.a;ssl")
    find_static_lib(DATACHANNEL_LIB "libdatachannel-static.a;datachannel-static")
    find_static_lib(JUICE_LIB "libjuice-static.a;juice-static")
    find_static_lib(USRSCTP_LIB "libusrsctp.a;usrsctp")
    find_static_lib(TORRENT_LIB "libtorrent-rasterbar.a;torrent-rasterbar")

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        target_link_libraries(torrent_engine PRIVATE pthread dl m)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
        target_link_libraries(torrent_engine PRIVATE dl m log)
    endif()
endif()

# Force static linking of all dependencies into our shared library
# Link order matters! torrent -> datachannel -> juice/usrsctp -> ssl -> crypto
target_link_libraries(torrent_engine PRIVATE
    ${TORRENT_LIB}
    ${DATACHANNEL_LIB}
    ${JUICE_LIB}
    ${USRSCTP_LIB}
    ${SSL_LIB}
    ${CRYPTO_LIB}
)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    add_custom_command(TARGET torrent_engine POST_BUILD
        COMMAND libtool -static -o $<TARGET_FILE:torrent_engine>.fat
                $<TARGET_FILE:torrent_engine>
                ${TORRENT_LIB}
                ${DATACHANNEL_LIB}
                ${JUICE_LIB}
                ${USRSCTP_LIB}
                ${SSL_LIB}
                ${CRYPTO_LIB}
        COMMAND ${CMAKE_COMMAND} -E rename $<TARGET_FILE:torrent_engine>.fat $<TARGET_FILE:torrent_engine>
        COMMENT "Bundling static libraries into a single fat archive for Apple platforms"
    )
endif()

# Install rule
install(TARGETS torrent_engine DESTINATION .)
