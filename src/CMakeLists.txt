cmake_minimum_required(VERSION 3.5)
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

# Find the library directory (could be lib or lib64)
if(EXISTS "${DEPS_DIR}/lib64")
    set(LIB_DIR "${DEPS_DIR}/lib64")
else()
    set(LIB_DIR "${DEPS_DIR}/lib")
endif()

# We build a SHARED library on Android/Linux/Windows, 
# but on iOS/macOS we build a STATIC library to be wrapped in an xcframework.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    add_library(torrent_engine STATIC torrent_bridge.cpp)
else()
    add_library(torrent_engine SHARED torrent_bridge.cpp)
endif()

# Add definitions needed by libtorrent
target_compile_definitions(torrent_engine PRIVATE 
    BOOST_ASIO_NO_DEPRECATED
    BOOST_ASIO_DISABLE_CONCEPTS
    TORRENT_USE_OPENSSL
    TORRENT_DISABLE_ENCRYPTION=OFF
)

# Resolve libraries based on platform naming conventions
if(WIN32)
    set(CRYPTO_LIB "${LIB_DIR}/libcrypto.lib")
    set(SSL_LIB "${LIB_DIR}/libssl.lib")
    set(DATACHANNEL_LIB "${LIB_DIR}/datachannel-static.lib")
    set(JUICE_LIB "${LIB_DIR}/juice-static.lib")
    set(USRSCTP_LIB "${LIB_DIR}/usrsctp.lib")
    set(TORRENT_LIB "${LIB_DIR}/torrent-rasterbar.lib")
    
    # Windows system libraries
    target_link_libraries(torrent_engine PRIVATE ws2_32 crypt32 iphlpapi bcrypt)
else()
    set(CRYPTO_LIB "${LIB_DIR}/libcrypto.a")
    set(SSL_LIB "${LIB_DIR}/libssl.a")
    set(DATACHANNEL_LIB "${LIB_DIR}/libdatachannel-static.a")
    set(JUICE_LIB "${LIB_DIR}/libjuice-static.a")
    set(USRSCTP_LIB "${LIB_DIR}/libusrsctp.a")
    set(TORRENT_LIB "${LIB_DIR}/libtorrent-rasterbar.a")

    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Android")
        target_link_libraries(torrent_engine PRIVATE pthread dl m)
        if(CMAKE_SYSTEM_NAME STREQUAL "Android")
            target_link_libraries(torrent_engine PRIVATE log)
        endif()
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

# Install rule
install(TARGETS torrent_engine DESTINATION bin)
