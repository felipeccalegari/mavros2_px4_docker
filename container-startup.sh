#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/humble/setup.bash

SEED_PX4_DIR="/opt/PX4-Autopilot-seed"
LIVE_PX4_DIR="/opt/PX4-Autopilot"
AGENTS_DIR="/root/Agents"
MAVLINK_DIR="${AGENTS_DIR}/Mavlink"
MAVLINK_REPO="https://github.com/felipeccalegari/emas_mavlink"

mkdir -p "${LIVE_PX4_DIR}" "${AGENTS_DIR}"

if [ ! -d "${LIVE_PX4_DIR}/.git" ]; then
  if [ -z "$(ls -A "${LIVE_PX4_DIR}" 2>/dev/null)" ]; then
    echo "[init] Seeding PX4-Autopilot into ${LIVE_PX4_DIR}..."
    cp -a "${SEED_PX4_DIR}"/. "${LIVE_PX4_DIR}/"
  else
    echo "[init] ${LIVE_PX4_DIR} is not empty and is not a git repo; leaving it untouched."
  fi
fi

if [ ! -d "${MAVLINK_DIR}/.git" ]; then
  if [ -z "$(ls -A "${MAVLINK_DIR}" 2>/dev/null)" ]; then
    echo "[init] Cloning emas_mavlink into ${MAVLINK_DIR}..."
    git clone "${MAVLINK_REPO}" "${MAVLINK_DIR}"
  else
    echo "[init] ${MAVLINK_DIR} is not empty and is not a git repo; leaving it untouched."
  fi
fi

echo '============================================'
echo 'Container started successfully!'
echo '============================================'
echo
echo 'Starting background services:'
echo '  [1/4] rosbridge - Port 9090'
ros2 launch rosbridge_server rosbridge_websocket_launch.xml &
sleep 3

echo '  [2/4] MAVROS - Waiting for PX4 connection'
ros2 launch mavros px4.launch fcu_url:=udp://:14540@127.0.0.1:14540 &
sleep 3

echo '  [3/4] socat bridge - /dev/ttyV1 <-> udp://127.0.0.1:14560'
(
  while true; do
    rm -f /dev/ttyV1
    socat -d -d \
      pty,raw,echo=0,link=/dev/ttyV1,wait-slave \
      udp:127.0.0.1:14560,sourceport=14561
    echo '[socat] bridge exited, restarting in 1s...'
    sleep 1
  done
) &
sleep 1

echo '  [4/4] Ready for PX4 SITL'
echo
echo '============================================'
echo 'Ready! To start PX4 simulation, run:'
echo '  docker exec -it px4_ros2 bash'
echo '  cd /opt/PX4-Autopilot'
echo '  make px4_sitl gz_x500'
echo
echo 'Safety checks are DISABLED for development.'
echo '============================================'

tail -f /dev/null
