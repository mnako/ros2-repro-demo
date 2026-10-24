# check=skip=InvalidDefaultArgInFrom

# Intentionally required: docker-bake.hcl supplies the pinned base image.
ARG ROS_BASE_IMAGE
FROM ${ROS_BASE_IMAGE} AS build

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /workspace

ARG SOURCE_DATE_EPOCH
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} LC_ALL=C TZ=UTC

COPY src ./src

# Dependencies and tools are already in the pinned image; compilation is offline.
RUN --network=none source /opt/ros/humble/setup.bash && \
    colcon build \
      --event-handlers console_direct+ \
      --packages-select demo_talker \
      --cmake-args \
        -DCMAKE_BUILD_TYPE=Release

FROM build AS package
ARG SOURCE_REVISION
ARG TARGETOS
ARG TARGETARCH

# Normalize archive metadata, keeping the installed files and permissions intact.
RUN --network=none version="$(xmllint --xpath 'string(/package/version)' \
      /workspace/install/demo_talker/share/demo_talker/package.xml)" && \
    archive="demo_talker-${version}-${SOURCE_REVISION}-${TARGETOS}-${TARGETARCH}.tar.gz" && \
    mkdir /out && \
    tar \
      --format=posix \
      --group=0 \
      --mtime="@${SOURCE_DATE_EPOCH}" \
      --numeric-owner \
      --owner=0 \
      --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
      --sort=name \
      -C /workspace/install -cf - demo_talker | gzip -n -9 > "/out/${archive}" && \
    cd /out && \
    sha256sum "${archive}" > "${archive}.sha256"

# Test only the exported package in a fresh ROS environment.
FROM ${ROS_BASE_IMAGE} AS smoke-test
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ARCHIVE
COPY --from=artifacts /${ARCHIVE} /tmp/package.tar.gz
COPY tests/test_installed_package.py /tmp/test_installed_package.py
RUN mkdir /tmp/installed && \
    tar -xzf /tmp/package.tar.gz -C /tmp/installed && \
    source /opt/ros/humble/setup.bash && \
    export COLCON_CURRENT_PREFIX=/tmp/installed/demo_talker && \
    source /tmp/installed/demo_talker/share/demo_talker/package.bash && \
    ament_flake8 /tmp/test_installed_package.py && \
    timeout --kill-after=2s 25s launch_test /tmp/test_installed_package.py

# BuildKit exports these files directly to the host, without creating a container.
FROM scratch AS release
COPY --from=package /out/ /
