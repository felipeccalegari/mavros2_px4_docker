#!/bin/bash

echo "$(date)"

LOG_DIR="log"
mkdir -p "$LOG_DIR"

ros_sampler=""
mavros_sampler=""
java_sampler=""
cleanup_done=0

wait_for_mavros_ready() {
    local timeout=60
    local elapsed=0

    while (( elapsed < timeout )); do
        if ros2 service list 2>/dev/null | grep -qx '/mavros/param/set_parameters' &&
           ros2 topic list 2>/dev/null | grep -qx '/mavros/param/event'; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo "Timed out waiting for MAVROS parameter service/topic."
    return 1
}

join_by_comma() { local IFS=,; echo "$*"; }

find_java_pid() {
    jps -l | awk '/examples\.mavros\.MavrosParamCounter/ {print $1; exit}'
}

start_sampler() {
    local pid_list="$1"
    local logfile="$2"

    (
        count=1
        while true; do
            read cpu mem < <(
                ps -p "$pid_list" -o %cpu=,rss= 2>/dev/null |
                awk '
                    BEGIN{sCPU=0;sMEM=0}
                    NF>=2{sCPU+=$1;sMEM+=$2}
                    END{printf "%.2f %.2f\n",sCPU,sMEM/1024}'
            )

            cpu="${cpu:-0.00}"
            mem="${mem:-0.00}"

            printf "Sample %d - CPU: %6.2f - MEM: %6.2f\n" \
                "$count" "$cpu" "$mem" >> "$logfile"

            ((count++))
            sleep 0.5
        done
    ) >/dev/null 2>&1 &

    echo $!
}

cleanup() {
    [[ "$cleanup_done" -eq 1 ]] && return
    cleanup_done=1

    echo "Stopping benchmark..."

    [[ -n "${ros_sampler:-}" ]] && kill "$ros_sampler" 2>/dev/null
    [[ -n "${mavros_sampler:-}" ]] && kill "$mavros_sampler" 2>/dev/null
    [[ -n "${java_sampler:-}" ]] && kill "$java_sampler" 2>/dev/null
    [[ -n "${APP_PID:-}" ]] && kill "$APP_PID" 2>/dev/null
}

on_signal() {
    local sig="$1"
    echo "Received $sig, cleaning up..."
    exit 130
}

trap cleanup EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal TSTP' TSTP

echo "Waiting for MAVROS parameter endpoints..."
wait_for_mavros_ready || exit 1

i=0
while [[ -f "$LOG_DIR/ros_${i}.log" || -f "$LOG_DIR/mavros_${i}.log" || -f "$LOG_DIR/java_${i}.log" ]]; do
    ((i++))
done

LOG_ROS="$LOG_DIR/ros_${i}.log"
LOG_MAVROS="$LOG_DIR/mavros_${i}.log"
LOG_JAVA="$LOG_DIR/java_${i}.log"

echo "ROS log:    $LOG_ROS"
echo "MAVROS log: $LOG_MAVROS"
echo "Java log:   $LOG_JAVA"

./gradlew -q --console=plain run &
APP_PID=$!

PID_JAVA=""
for _ in {1..20}; do
    PID_JAVA=$(find_java_pid)
    [[ -n "$PID_JAVA" ]] && break
    sleep 1
done

mapfile -t MAVROS_PID_ARRAY < <(
    ps -eo pid=,args= | awk -v app="$PID_JAVA" '
        ($0 ~ /mavros/) &&
        ($0 !~ /awk/) &&
        ($0 !~ /grep/) &&
        ($1 != app) { print $1 }'
)

mapfile -t ROS_PID_ARRAY < <(
    ps -eo pid=,args= | awk -v app="$PID_JAVA" '
        ($0 ~ /roscore|rosmaster|rosout|roslaunch|ros2|\/ros\//) &&
        ($0 !~ /mavros/) &&
        ($0 !~ /awk/) &&
        ($0 !~ /grep/) &&
        ($1 != app) { print $1 }'
)

PIDS_MAVROS=$(join_by_comma "${MAVROS_PID_ARRAY[@]}")
PIDS_ROS=$(join_by_comma "${ROS_PID_ARRAY[@]}")

echo "MAVROS PIDs: ${PIDS_MAVROS:-none}"
echo "ROS PIDs:    ${PIDS_ROS:-none}"
echo "Java PID:    ${PID_JAVA:-none}"

if [[ -n "$PIDS_ROS" ]]; then
    ros_sampler=$(start_sampler "$PIDS_ROS" "$LOG_ROS")
fi

if [[ -n "$PIDS_MAVROS" ]]; then
    mavros_sampler=$(start_sampler "$PIDS_MAVROS" "$LOG_MAVROS")
fi

if [[ -n "$PID_JAVA" ]]; then
    java_sampler=$(start_sampler "$PID_JAVA" "$LOG_JAVA")
fi

sleep 30

echo "$(date)"
echo "Benchmark finished."

exit 0
