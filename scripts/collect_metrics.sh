#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
source ${CONFIG_DIR}/.env

mkdir -p $APP_LOG_DIR

#CPU_USAGE
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
idle1=$((idle + iowait))
total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
sleep 1
read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
idle2=$((idle + iowait))
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))

CPU_USAGE=$(awk \
	-v idle1="$idle1" \
	-v idle2="$idle2" \
	-v total1="$total1" \
	-v total2="$total2" \
	'BEGIN {printf "%.0f\n", (1 - (idle2 - idle1)/(total2 - total1))*100}')

#RAM_USAGE
RAM_USAGE=$(cat /proc/meminfo | awk '/^MemTotal:/ {total=$2} /^MemAvailable:/ {avail=$2} END { printf "%.0f\n", (total - avail) / total * 100}')

#DISK_USAGE
DISK_USAGE=$(df -P / | awk 'NR==2 { gsub("%","",$5) ; print $5 }')

#TIME
time_log=$(date +'%Y-%m-%d %H:%M:%S')

if (( $CPU_USAGE >= $THRESHOLD_CPU )); then
    echo "[${time_log}] WARNING: CPU usage is ${CPU_USAGE}%" >> $APP_LOG_DIR/sentinel_alert.log
fi

if (( $RAM_USAGE >= $THRESHOLD_MEM )); then
    echo "[${time_log}] WARNING: RAM usage is ${RAM_USAGE}%" >> $APP_LOG_DIR/sentinel_alert.log
fi

if (( $DISK_USAGE >= $THRESHOLD_DISK )); then
    echo "[${time_log}] WARNING: Disk usage is ${DISK_USAGE}%" >> $APP_LOG_DIR/sentinel_alert.log
fi
