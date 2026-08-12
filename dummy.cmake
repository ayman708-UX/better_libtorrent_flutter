
cmake_minimum_required(VERSION 3.10)
project(test)
set(CMAKE_POLICY_DEFAULT_CMP0167 OLD)
find_package(Boost REQUIRED)
message(STATUS "Boost_INCLUDE_DIR: ${Boost_INCLUDE_DIR}")

