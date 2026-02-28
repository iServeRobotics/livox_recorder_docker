# Livox MID360 Bag Recorder

Records `/livox/lidar` and `/livox/imu` topics to mcap bags, split every 60 seconds.

## Setup

### 1. Find your lidar network interface and IP

Connect the lidar via ethernet, then find the interface:

```bash
ip addr show
```

Look for the interface on the `192.168.1.x` subnet (e.g., `eth0`, `enp3s0`). Note the interface name and your computer's IP on that subnet.

To verify the lidar is reachable:

```bash
ping 192.168.1.116
```

The default lidar IP is `192.168.1.1XX` where `XX` is the last two digits of the serial number. Check the sticker on the lidar if the default doesn't respond.

### 2. Update `.env`

```bash
LIDAR_INTERFACE=eth0           # your interface name
LIDAR_COMPUTER_IP=192.168.1.5  # your computer's IP on that subnet
LIDAR_IP=192.168.1.116         # your lidar's IP
```

## Record

```bash
docker compose up
```

Bags are saved to `./bags/<YYYYMMDD_HHMMSS>_<hostname>/`. Press `Ctrl+C` to stop.

## Upload to S3

```bash
docker compose --profile upload run --rm s3-upload
```

`--rm` removes the container after upload completes to avoid leftover stopped containers.
