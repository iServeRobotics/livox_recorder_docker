#!/bin/bash
set -e

# Source ROS environment
source /opt/ros/${ROS_DISTRO}/setup.bash
source ${WORKSPACE}/install/setup.bash
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# Disable FastDDS shared memory transport — SHM is isolated between Docker
# containers even with network_mode:host, so force UDP for cross-container comms
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastdds_no_shm.xml
cat > /tmp/fastdds_no_shm.xml <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8" ?>
<profiles xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
    <transport_descriptors>
        <transport_descriptor>
            <transport_id>udp_transport</transport_id>
            <type>UDPv4</type>
        </transport_descriptor>
    </transport_descriptors>
    <participant profile_name="disable_shm" is_default_profile="true">
        <rtps>
            <userTransports>
                <transport_id>udp_transport</transport_id>
            </userTransports>
            <useBuiltinTransports>false</useBuiltinTransports>
        </rtps>
    </participant>
</profiles>
XMLEOF

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
mkdir -p "${WORKSPACE}/bags"

echo "=========================================="
echo " Livox MID360 Bag Recorder"
echo "=========================================="
echo " Bag output: ${BAG_PATH}"
echo " Format:     mcap"
echo " Split:      every 60 seconds"
echo "=========================================="

# Check if livox driver is already running by looking for standard topics
# (/lidar/scan uses standard types and is always visible across containers,
#  while /livox/* custom topics may not be due to message type hash differences)
TOPICS_EXIST=false
RECORD_TOPICS=""
for i in $(seq 1 10); do
    EXISTING_TOPICS=$(ros2 topic list 2>/dev/null || true)
    if echo "${EXISTING_TOPICS}" | grep -q "^/lidar/scan$"; then
        TOPICS_EXIST=true
        RECORD_TOPICS="/lidar/scan /imu/data"
        echo "Livox driver already running — recording /lidar/scan and /imu/data"
        break
    fi
    echo "Waiting for livox topics... (attempt ${i}/10)"
    sleep 2
done

DRIVER_PID=""
if [ "${TOPICS_EXIST}" = "false" ]; then
    # Launch livox driver (custom launch without topic remapping)
    ros2 launch /ros2_ws/launch_recorder.py &
    DRIVER_PID=$!
    RECORD_TOPICS="/livox/lidar /livox/imu"
    echo "Launched livox driver (PID: ${DRIVER_PID}), waiting for init..."
    sleep 3
fi

echo " Topics:     ${RECORD_TOPICS}"

# Start bag recording with mcap, split every 60s
ros2 bag record \
    ${RECORD_TOPICS} \
    --storage mcap \
    --compression-mode chunk \
    --compression-format zstd \
    --max-bag-duration 60 \
    --output "${BAG_PATH}" &
RECORD_PID=$!

echo "Recorder PID: ${RECORD_PID}"

# Analyze the current session's bag directory and write a framerate report
check_bag_framerates() {
    local bags_dir="${WORKSPACE}/bags"
    local report_file="${bags_dir}/report_$(date +%Y%m%d_%H%M%S).txt"
    local passed_file="${bags_dir}/passed_bags.txt"
    local lidar_min=9.5 lidar_max=10.5 imu_min=195 imu_max=205
    local pass=0 fail=0 total=0

    > "${passed_file}"

    {
        echo "Bag Framerate Report — $(date)"
        echo "========================================"
        echo ""
    } > "${report_file}"

    local bag_name info duration lidar_count imu_count lidar_hz imu_hz lidar_ok imu_ok status lidar_label imu_label
    bag_name=$(basename "${BAG_PATH}")

    if [ ! -f "${BAG_PATH}/metadata.yaml" ]; then
        echo "  [SKIP] ${bag_name} — no metadata.yaml" >> "${report_file}"
    else
        total=1
        info=$(ros2 bag info "${BAG_PATH}" 2>/dev/null) || true

        duration=$(echo "${info}" | grep "Duration:" | awk '{print $2}' | tr -d 's')
        if [ -z "${duration}" ] || [ "${duration}" = "0" ]; then
            echo "  [SKIP] ${bag_name} — could not read bag info" >> "${report_file}"
        else
            lidar_count=$(echo "${info}" | grep -E "Topic: /(lidar/scan|livox/lidar) " | grep -o "Count: [0-9]*" | awk '{print $2}')
            imu_count=$(echo "${info}" | grep -E "Topic: /(imu/data|livox/imu) " | grep -o "Count: [0-9]*" | awk '{print $2}')
            lidar_count="${lidar_count:-0}"
            imu_count="${imu_count:-0}"

            lidar_hz=$(awk "BEGIN {printf \"%.2f\", ${lidar_count}/${duration}}")
            imu_hz=$(awk "BEGIN {printf \"%.2f\", ${imu_count}/${duration}}")

            lidar_ok=$(awk "BEGIN {print (${lidar_hz} >= ${lidar_min} && ${lidar_hz} <= ${lidar_max}) ? 1 : 0}")
            imu_ok=$(awk "BEGIN {print (${imu_hz} >= ${imu_min} && ${imu_hz} <= ${imu_max}) ? 1 : 0}")

            if [ "${lidar_ok}" = "1" ] && [ "${imu_ok}" = "1" ]; then
                status="PASS"; pass=1
                echo "${bag_name}" >> "${passed_file}"
            else
                status="FAIL"; fail=1
            fi

            lidar_label=$([ "${lidar_ok}" = "1" ] && echo "OK" || echo "OUT OF RANGE")
            imu_label=$([ "${imu_ok}" = "1" ] && echo "OK" || echo "OUT OF RANGE")

            {
                echo "  [${status}] ${bag_name}"
                echo "         Duration : ${duration}s"
                echo "         Lidar    : ${lidar_hz} Hz  [${lidar_label}]  (expected ${lidar_min}-${lidar_max} Hz)"
                echo "         IMU      : ${imu_hz} Hz  [${imu_label}]  (expected ${imu_min}-${imu_max} Hz)"
                echo ""
            } >> "${report_file}"
        fi
    fi

    {
        echo "========================================"
        echo "Summary: ${pass}/${total} bags passed"
        echo "========================================"
    } >> "${report_file}"

    echo ""
    cat "${report_file}"
    echo "Report saved to: ${report_file}"
}

# Graceful shutdown handler
shutdown() {
    echo ""
    echo "Stopping recorder..."
    kill ${RECORD_PID} 2>/dev/null || true
    wait ${RECORD_PID} 2>/dev/null || true
    if [ -n "${DRIVER_PID}" ]; then
        echo "Stopping driver..."
        kill ${DRIVER_PID} 2>/dev/null || true
        wait ${DRIVER_PID} 2>/dev/null || true
    fi
    chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" "${WORKSPACE}/bags" 2>/dev/null || true
    check_bag_framerates
    echo "Done. Bags saved to: ${BAG_PATH}"
    exit 0
}

trap shutdown SIGINT SIGTERM

# Wait for process(es) to exit
if [ -n "${DRIVER_PID}" ]; then
    wait -n ${DRIVER_PID} ${RECORD_PID} 2>/dev/null || true
else
    wait ${RECORD_PID} 2>/dev/null || true
fi
shutdown
