cmake_minimum_required(VERSION 2.4.6)
include($ENV{ROS_ROOT}/core/rosbuild/rosbuild.cmake)

find_package(PkgConfig REQUIRED)

# Set the build type.  Options are:
#  Coverage       : w/ debug symbols, w/o optimization, w/ code-coverage
#  Debug          : w/ debug symbols, w/o optimization
#  Release        : w/o debug symbols, w/ optimization
#  RelWithDebInfo : w/ debug symbols, w/ optimization
#  MinSizeRel     : w/o debug symbols, w/ optimization, stripped binaries
#set(ROS_BUILD_TYPE RelWithDebInfo)

rosbuild_init()

#set the default path for built executables to the "bin" directory
set(EXECUTABLE_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/bin)
#set the default path for built libraries to the "lib" directory
set(LIBRARY_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/lib)

# We give Lua libraries a special suffix, otherwise some ROS tools written
# in Python crash
set(CMAKE_SHARED_LIBRARY_PREFIX "")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".luaso")

pkg_search_module(LUA REQUIRED lua lua5.2 lua-5.2 lua5.1 lua-5.1)

message(STATUS "Found Lua ${LUA_VERSION}")

include_directories(${LUA_INCLUDE_DIRS})

#uncomment if you have defined messages
#rosbuild_genmsg()
#uncomment if you have defined services
#rosbuild_gensrv()

#common commands for building c++ executables and libraries
#rosbuild_add_library(${PROJECT_NAME} src/example.cpp)
#target_link_libraries(${PROJECT_NAME} another_library)
#rosbuild_add_boost_directories()
#rosbuild_link_boost(${PROJECT_NAME} thread)
#rosbuild_add_executable(example examples/example.cpp)
#target_link_libraries(example ${PROJECT_NAME})

rosbuild_add_library(signal src/lua_modules/lsignal.c)
rosbuild_add_library(struct src/lua_modules/struct.c)

target_link_libraries(signal ${LUA_LIBRARIES})
target_link_libraries(struct ${LUA_LIBRARIES})

# Use system posix library
if (${LUA_VERSION} VERSION_LESS 5.2)
  rosbuild_add_library(posix src/lua_modules/lposix.c)
  target_link_libraries(posix rt crypt)
endif ()


