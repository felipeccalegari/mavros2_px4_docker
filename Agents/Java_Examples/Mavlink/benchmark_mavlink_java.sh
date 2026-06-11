#!/bin/bash

echo "$(date)"

LOG_DIR="log"
mkdir -p "$LOG_DIR"

mavlink_sampler=""
java_sampler=""
cleanup_done=0

join_by_comma() { local IFS=,; echo "$*"; }

find_java_pid() {
    jps -l | awk '/examples\.mavlink\.MavlinkParamCounter/ {print $1; exit}'
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

stop_unneeded_ros() {
    mapfile -t ROS_KILL_ARRAY < <(
        ps -eo pid=,args= | awk '
            ($0 ~ /rosbridge_server/ ||
             $0 ~ /rosbridge_websocket/ ||
             $0 ~ /rosapi_node/ ||
             $0 ~ /mavros px4\.launch/ ||
             $0 ~ /\/mavros_node/) &&
            ($0 !~ /awk/) &&
            ($0 !~ /grep/) {
                print $1
            }'
    )

    if [[ "${#ROS_KILL_ARRAY[@]}" -gt 0 ]]; then
        echo "Stopping ROS/MAVROS-related PIDs: $(join_by_comma "${ROS_KILL_ARRAY[@]}")"
        kill "${ROS_KILL_ARRAY[@]}" 2>/dev/null || true
        sleep 2
        kill -9 "${ROS_KILL_ARRAY[@]}" 2>/dev/null || true
    else
        echo "No ROS/MAVROS-related PIDs found to stop."
    fi
}

cleanup() {
    [[ "$cleanup_done" -eq 1 ]] && return
    cleanup_done=1

    echo "Stopping benchmark..."

    [[ -n "${mavlink_sampler:-}" ]] && kill "$mavlink_sampler" 2>/dev/null
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

i=0
while [[ -f "$LOG_DIR/mavlink_${i}.log" || -f "$LOG_DIR/java_${i}.log" ]]; do
    ((i++))
done

LOG_MAVLINK="$LOG_DIR/mavlink_${i}.log"
LOG_JAVA="$LOG_DIR/java_${i}.log"

echo "MAVLink log: $LOG_MAVLINK"
echo "Java log:    $LOG_JAVA"

stop_unneeded_ros

./gradlew -q --console=plain run &
APP_PID=$!

PID_JAVA=""
for _ in {1..20}; do
    PID_JAVA=$(find_java_pid)
    [[ -n "$PID_JAVA" ]] && break
    sleep 1
done

mapfile -t MAVLINK_PID_ARRAY < <(
    ps -eo pid=,args= | awk -v app="$PID_JAVA" '
        (($0 ~ /(^|[[:space:]])px4([[:space:]]|$)/) || ($0 ~ /(^|[[:space:]])socat([[:space:]]|$)/)) &&
        ($0 !~ /awk/) &&
        ($0 !~ /grep/) &&
        ($1 != app) {
            print $1
        }'
)

PIDS_MAVLINK=$(join_by_comma "${MAVLINK_PID_ARRAY[@]}")

echo "MAVLink-side PIDs: ${PIDS_MAVLINK:-none}"
echo "Java PID:          ${PID_JAVA:-none}"

if [[ -n "$PIDS_MAVLINK" ]]; then
    mavlink_sampler=$(start_sampler "$PIDS_MAVLINK" "$LOG_MAVLINK")
fi

if [[ -n "$PID_JAVA" ]]; then
    java_sampler=$(start_sampler "$PID_JAVA" "$LOG_JAVA")
fi

sleep 30

echo "$(date)"
echo "Benchmark finished."

exit 0
