cmake_minimum_required(VERSION 3.13)
project(demo_talker)

find_package(ament_cmake REQUIRED)

# Read exact dependency versions from package.xml, then enforce them in CMake.
ament_package_xml()
find_package(rclcpp ${demo_talker_BUILD_DEPENDS_rclcpp_VERSION_EQ} EXACT REQUIRED)
find_package(std_msgs ${demo_talker_BUILD_DEPENDS_std_msgs_VERSION_EQ} EXACT REQUIRED)

add_executable(demo_talker src/talker.cpp)

ament_target_dependencies(
        demo_talker
        rclcpp
        std_msgs
)

# Reproducible builds req: Avoid source/workspace paths entering debug information.
target_compile_options(demo_talker PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -ffile-prefix-map=/workspace=/usr/src/ros2-repro-demo
        -fdebug-prefix-map=/workspace=/usr/src/ros2-repro-demo
)

# Reproducible builds req: Avoid a linker-generated build ID changing the binary.
target_link_options(demo_talker PRIVATE
        -Wl,--build-id=none
)

install(TARGETS demo_talker
        DESTINATION lib/${PROJECT_NAME}
)

ament_package()
