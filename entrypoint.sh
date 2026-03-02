#!/bin/bash
set -e

# Source ROS environment
source /opt/ros/${ROS_DISTRO}/setup.bash
source ${WORKSPACE}/install/setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# Configure lidar network interface if specified
if [ -n "${LIDAR_INTERFACE}" ] && [ -n "${LIDAR_COMPUTER_IP}" ]; then
    ip addr add ${LIDAR_COMPUTER_IP}/24 dev ${LIDAR_INTERFACE} 2>/dev/null || true
    ip link set ${LIDAR_INTERFACE} up 2>/dev/null || true
fi

# Generate MID360_config.json from environment variables
if [ -n "${LIDAR_COMPUTER_IP}" ] && [ -n "${LIDAR_IP}" ]; then
    cat > ${WORKSPACE}/src/livox_ros_driver2/config/MID360_config.json <<EOF
{
  "lidar_summary_info": { "lidar_type": 8 },
  "MID360": {
    "lidar_net_info": {
      "cmd_data_port": 56100, "push_msg_port": 56200,
      "point_data_port": 56300, "imu_data_port": 56400, "log_data_port": 56500
    },
    "host_net_info": {
      "cmd_data_ip": "${LIDAR_COMPUTER_IP}", "cmd_data_port": 56101,
      "push_msg_ip": "${LIDAR_COMPUTER_IP}", "push_msg_port": 56201,
      "point_data_ip": "${LIDAR_COMPUTER_IP}", "point_data_port": 56301,
      "imu_data_ip": "${LIDAR_COMPUTER_IP}", "imu_data_port": 56401,
      "log_data_ip": "${LIDAR_COMPUTER_IP}", "log_data_port": 56501
    }
  },
  "lidar_configs": [{
    "ip": "${LIDAR_IP}",
    "pcl_data_type": 1, "pattern_mode": 0,
    "extrinsic_parameter": { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "x": 0, "y": 0, "z": 0 }
  }]
}
EOF
    cp ${WORKSPACE}/src/livox_ros_driver2/config/MID360_config.json \
       ${WORKSPACE}/install/livox_ros_driver2/share/livox_ros_driver2/config/MID360_config.json 2>/dev/null || true
    echo "Generated MID360_config.json (LIDAR_IP=${LIDAR_IP}, COMPUTER_IP=${LIDAR_COMPUTER_IP})"
fi

# Generate bag name: <timestamp>_<hostname>
BAG_NAME="$(date +%Y%m%d_%H%M%S)_$(hostname)"
BAG_PATH="${WORKSPACE}/bags/${BAG_NAME}"

echo "=========================================="
echo " Livox MID360 Bag Recorder"
echo "=========================================="
echo " Bag output: ${BAG_PATH}"
echo " Format:     mcap"
echo " Split:      every 60 seconds"
echo " Topics:     /livox/lidar /livox/imu"
echo "=========================================="

# Launch livox driver (custom launch without topic remapping)
ros2 launch /ros2_ws/launch_recorder.py &
DRIVER_PID=$!

# Wait for driver to initialize
sleep 3

# Start bag recording with mcap, split every 60s
ros2 bag record \
    /livox/lidar \
    /livox/imu \
    --storage mcap \
    --max-bag-duration 60 \
    --output "${BAG_PATH}" &
RECORD_PID=$!

echo "Driver PID: ${DRIVER_PID}, Recorder PID: ${RECORD_PID}"

# Graceful shutdown handler
shutdown() {
    echo ""
    echo "Stopping recorder..."
    kill ${RECORD_PID} 2>/dev/null || true
    wait ${RECORD_PID} 2>/dev/null || true
    echo "Stopping driver..."
    kill ${DRIVER_PID} 2>/dev/null || true
    wait ${DRIVER_PID} 2>/dev/null || true
    echo "Done. Bags saved to: ${BAG_PATH}"
    exit 0
}

trap shutdown SIGINT SIGTERM

# Wait for either process to exit
wait -n ${DRIVER_PID} ${RECORD_PID} 2>/dev/null || true
shutdown
