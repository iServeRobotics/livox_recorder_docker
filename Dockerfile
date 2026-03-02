# =============================================================================
# Livox MID360 ROS2 Bag Recorder
# =============================================================================
# Records /livox/lidar and /livox/imu topics to mcap bags.
#
# Build:
#   docker compose build
# =============================================================================

ARG ROS_DISTRO=jazzy

FROM ros:${ROS_DISTRO}-ros-base AS builder

ARG ROS_DISTRO
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=${ROS_DISTRO}
ENV WORKSPACE=/ros2_ws

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    python3-colcon-common-extensions \
    libpcl-dev \
    ros-${ROS_DISTRO}-pcl-ros \
    && rm -rf /var/lib/apt/lists/*

# Copy livox driver source
COPY livox_ros_driver2 ${WORKSPACE}/src/livox_ros_driver2

# Build Livox-SDK2
RUN cd ${WORKSPACE}/src/livox_ros_driver2/Livox-SDK2 && \
    mkdir -p build && cd build && \
    cmake .. && make -j$(nproc) && make install && ldconfig && \
    rm -rf ${WORKSPACE}/src/livox_ros_driver2/Livox-SDK2/build

# Build livox_ros_driver2
RUN /bin/bash -c "source /opt/ros/${ROS_DISTRO}/setup.bash && \
    cd ${WORKSPACE} && \
    colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release"

# Stage arch-specific runtime libs to a neutral path for the runtime stage
RUN ARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) && \
    mkdir -p /staging/libs && \
    find /usr/lib/${ARCH} -maxdepth 1 \( -name "libpcl_*.so*" -o -name "libflann*.so*" -o -name "libboost_*.so*" \) \
        -exec cp -P {} /staging/libs/ \;

# =============================================================================
# Runtime
# =============================================================================
FROM ros:${ROS_DISTRO}-ros-base AS runtime

ARG ROS_DISTRO
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=${ROS_DISTRO}
ENV WORKSPACE=/ros2_ws
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# Install runtime dependencies (no pcl-ros — runtime .so copied from builder)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-fastrtps-cpp \
    ros-${ROS_DISTRO}-rosbag2-storage-mcap \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Copy Livox SDK from builder
COPY --from=builder /usr/local/lib /usr/local/lib

# Copy PCL and dependency runtime libs from builder (arch-agnostic)
COPY --from=builder /staging/libs/ /tmp/staging-libs/
RUN ARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) && \
    cp -P /tmp/staging-libs/* /usr/lib/${ARCH}/ && \
    rm -rf /tmp/staging-libs && \
    ldconfig

COPY --from=builder ${WORKSPACE}/install ${WORKSPACE}/install

# Copy lidar config
COPY --from=builder ${WORKSPACE}/src/livox_ros_driver2/config ${WORKSPACE}/src/livox_ros_driver2/config

# Copy custom launch file (no topic remapping, uses PointCloud2)
COPY launch_recorder.py ${WORKSPACE}/launch_recorder.py

# Create bags directory
RUN mkdir -p ${WORKSPACE}/bags

# Shell environment
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc && \
    echo "source ${WORKSPACE}/install/setup.bash" >> ~/.bashrc && \
    echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> ~/.bashrc

# Entrypoint
COPY entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

WORKDIR ${WORKSPACE}
ENTRYPOINT ["/ros_entrypoint.sh"]
