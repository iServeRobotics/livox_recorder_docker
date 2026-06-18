#!/bin/bash
set -e

source /opt/ros/${ROS_DISTRO}/setup.bash
source ${WORKSPACE}/install/setup.bash

BAGS_DIR="${WORKSPACE}/bags"
PASSED_FILE="${BAGS_DIR}/passed_bags.txt"
REPORT_FILE="${BAGS_DIR}/report_$(date +%Y%m%d_%H%M%S).txt"
LIDAR_MIN=9.5; LIDAR_MAX=10.5; IMU_MIN=195; IMU_MAX=205
PASS=0; FAIL=0; TOTAL=0

> "${PASSED_FILE}"

{
    echo "Bag Framerate Report — $(date)"
    echo "========================================"
    echo ""
} > "${REPORT_FILE}"

for bag_dir in "${BAGS_DIR}"/*/; do
    [ -f "${bag_dir}/metadata.yaml" ] || continue
    TOTAL=$((TOTAL + 1))
    BAG_NAME=$(basename "${bag_dir}")
    INFO=$(ros2 bag info "${bag_dir}" 2>/dev/null) || true

    DURATION=$(echo "${INFO}" | grep "Duration:" | awk '{print $2}' | tr -d 's')
    if [ -z "${DURATION}" ] || [ "${DURATION}" = "0" ]; then
        echo "  [SKIP] ${BAG_NAME} — could not read bag info" >> "${REPORT_FILE}"
        FAIL=$((FAIL + 1))
        continue
    fi

    LIDAR_COUNT=$(echo "${INFO}" | grep -E "Topic: /(lidar/scan|livox/lidar) " | grep -o "Count: [0-9]*" | awk '{print $2}')
    IMU_COUNT=$(echo "${INFO}" | grep -E "Topic: /(imu/data|livox/imu) " | grep -o "Count: [0-9]*" | awk '{print $2}')
    LIDAR_COUNT="${LIDAR_COUNT:-0}"
    IMU_COUNT="${IMU_COUNT:-0}"

    LIDAR_HZ=$(awk "BEGIN {printf \"%.2f\", ${LIDAR_COUNT}/${DURATION}}")
    IMU_HZ=$(awk "BEGIN {printf \"%.2f\", ${IMU_COUNT}/${DURATION}}")

    LIDAR_OK=$(awk "BEGIN {print (${LIDAR_HZ} >= ${LIDAR_MIN} && ${LIDAR_HZ} <= ${LIDAR_MAX}) ? 1 : 0}")
    IMU_OK=$(awk "BEGIN {print (${IMU_HZ} >= ${IMU_MIN} && ${IMU_HZ} <= ${IMU_MAX}) ? 1 : 0}")

    if [ "${LIDAR_OK}" = "1" ] && [ "${IMU_OK}" = "1" ]; then
        STATUS="PASS"; PASS=$((PASS + 1))
        echo "${BAG_NAME}" >> "${PASSED_FILE}"
    else
        STATUS="FAIL"; FAIL=$((FAIL + 1))
    fi

    LIDAR_LABEL=$([ "${LIDAR_OK}" = "1" ] && echo "OK" || echo "OUT OF RANGE")
    IMU_LABEL=$([ "${IMU_OK}" = "1" ] && echo "OK" || echo "OUT OF RANGE")

    {
        echo "  [${STATUS}] ${BAG_NAME}"
        echo "         Duration : ${DURATION}s"
        echo "         Lidar    : ${LIDAR_HZ} Hz  [${LIDAR_LABEL}]  (expected ${LIDAR_MIN}-${LIDAR_MAX} Hz)"
        echo "         IMU      : ${IMU_HZ} Hz  [${IMU_LABEL}]  (expected ${IMU_MIN}-${IMU_MAX} Hz)"
        echo ""
    } >> "${REPORT_FILE}"
done

{
    echo "========================================"
    echo "Summary: ${PASS}/${TOTAL} bags passed"
    echo "========================================"
} >> "${REPORT_FILE}"

echo ""
cat "${REPORT_FILE}"
echo "Report saved to: ${REPORT_FILE}"
