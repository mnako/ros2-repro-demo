variable "ROS_BASE_IMAGE" {
  default = "docker.io/library/ros:humble-ros-base@sha256:566b87e6dfc48392189a9c32e594e84060fa9948de93b04e536f39475a1f6963"
}

# Make supplies Git metadata.
variable "SOURCE_REVISION" { default = "" }
variable "SOURCE_DATE_EPOCH" { default = "" }
variable "BUILD_CONTEXT" { default = "." }
variable "OUTPUT_DIR" { default = "release/artifacts" }
variable "ARCHIVE" { default = "" }

group "default" {
  targets = ["release"]
}

target "release" {
  context = BUILD_CONTEXT
  dockerfile = "Dockerfile"
  target = "release"
  platforms = ["linux/amd64"]
  network = "none"
  args = {
    ROS_BASE_IMAGE = ROS_BASE_IMAGE
    SOURCE_REVISION = SOURCE_REVISION
    SOURCE_DATE_EPOCH = SOURCE_DATE_EPOCH
  }
  output = ["type=local,dest=${OUTPUT_DIR}"]
}

target "smoke-test" {
  context = "."
  dockerfile = "Dockerfile"
  target = "smoke-test"
  platforms = ["linux/amd64"]
  contexts = {
    artifacts = OUTPUT_DIR
  }
  args = {
    ROS_BASE_IMAGE = ROS_BASE_IMAGE
    ARCHIVE = ARCHIVE
  }
  no-cache-filter = ["smoke-test"]
  output = ["type=cacheonly"]
}
