import os
from launch import LaunchDescription
from launch_ros.actions import Node

xfer_format   = 1    # 0-PointCloud2(PointXYZRTL), 1-customized pointcloud format
multi_topic   = 0    # 0-All LiDARs share the same topic
data_src      = 0    # 0-lidar
publish_freq  = 10.0
output_type   = 0
frame_id      = 'livox_frame'
lvx_file_path = ''
cmdline_bd_code = 'livox0000000001'

user_config_path = '/ros2_ws/src/livox_ros_driver2/config/MID360_config.json'

livox_ros2_params = [
    {"xfer_format": xfer_format},
    {"multi_topic": multi_topic},
    {"data_src": data_src},
    {"publish_freq": publish_freq},
    {"output_data_type": output_type},
    {"frame_id": frame_id},
    {"lvx_file_path": lvx_file_path},
    {"user_config_path": user_config_path},
    {"cmdline_input_bd_code": cmdline_bd_code},
]


def generate_launch_description():
    livox_driver = Node(
        package='livox_ros_driver2',
        executable='livox_ros_driver2_node',
        name='livox_lidar_publisher',
        output='screen',
        parameters=livox_ros2_params,
    )

    return LaunchDescription([livox_driver])
