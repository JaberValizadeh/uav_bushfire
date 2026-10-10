cmake_minimum_required(VERSION 3.0.2)
project(uav_bushfire)

find_package(catkin REQUIRED COMPONENTS
  rospy
  std_msgs
  std_srvs
  geometry_msgs
  nav_msgs
  sensor_msgs
  tf
  gazebo_msgs
  visualization_msgs
  message_generation
)

add_message_files(
  FILES
  Hotspot.msg
  HotspotArray.msg
  FireClaim.msg
)

generate_messages(
  DEPENDENCIES
  std_msgs
)

catkin_package(
  CATKIN_DEPENDS rospy std_msgs std_srvs geometry_msgs nav_msgs sensor_msgs tf
                 gazebo_msgs visualization_msgs message_runtime
)

catkin_install_python(PROGRAMS
  scripts/fire_spotter
  scripts/fire_suppressor
  scripts/pose_fire_monitor
  scripts/collision_monitor
  scripts/make_bushfire_world
  scripts/make_bushfire_textures
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY launch worlds urdf rviz
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
