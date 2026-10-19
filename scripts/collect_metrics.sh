#!/bin/bash
set -euo pipefail

# ================== CONFIG ==================
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
ENV_FILE="$CONFIG_DIR/.env"

if [[ ! -f "$ENV_FILE" || ! -r "$ENV_FILE" ]]; then
    echo "ERROR: Khong the doc $ENV_FILE" >&2
    exit 1
fi

source "$ENV_FILE"

# ================== VALIDATION ==================
validate_threshold() {
    local th_name="$1"
    local th_val="$2"

    if ! [[ "$th_val" =~ ^(0|[1-9][0-9]{0,2})$ ]]; then
        echo "ERROR: $th_name phai la so nguyen tu 0 den 100" >&2
        return 1
    fi

    if (( 10#$th_val > 100 )); then
        echo "ERROR: $th_name phai trong khoang [0,100]" >&2
        return 1
    fi

    return 0
}

validate_threshold "THRESHOLD_CPU" "${THRESHOLD_CPU:-}"
validate_threshold "THRESHOLD_MEM" "${THRESHOLD_MEM:-}"
validate_threshold "THRESHOLD_DISK" "${THRESHOLD_DISK:-}"

if [[ -z "${APP_LOG_DIR:-}" ]]; then
    echo "ERROR: APP_LOG_DIR chua duoc cau hinh" >&2
    exit 1
fi

if ! mkdir -p "$APP_LOG_DIR"; then
    echo "ERROR: Khong the tao thu muc log" >&2
    exit 1
fi

METRICS_LOG="$APP_LOG_DIR/metrics.log"
ALERT_LOG="$APP_LOG_DIR/sentinel_alert.log"

# ================== CPU ==================
read -r cpu user nice system idle iowait irq softirq steal rest < /proc/stat

idle1=$((idle + iowait))
total1=$((user + nice + system + idle + iowait + irq + softirq + steal))

sleep 1

read -r cpu user nice system idle iowait irq softirq steal rest < /proc/stat

idle2=$((idle + iowait))
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))

delta_total=$((total2 - total1))
delta_idle=$((idle2 - idle1))

if (( delta_total <= 0 || delta_idle < 0 || delta_idle > delta_total )); then
    echo "ERROR: Du lieu CPU khong hop le" >&2
    exit 1
fi

CPU_USAGE=$(awk \
    -v dt="$delta_total" \
    -v di="$delta_idle" \
    'BEGIN {printf "%.0f\n", (1 - di/dt)*100}')

# ================== RAM ==================
if ! RAM_USAGE=$(awk '
    /^MemTotal:/ {total=$2}
    /^MemAvailable:/ {avail=$2}
    END {
        if (total <= 0 || avail < 0 || avail > total)
            exit 1
        printf "%.0f\n", (total-avail)/total*100
    }
' /proc/meminfo); then
    echo "ERROR: Khong the thu thap RAM" >&2
    exit 1
fi

# ================== DISK ==================
if ! DISK_USAGE=$(df -P / | awk '
    NR==2 {
        gsub("%", "", $5)

        if ($5 ~ /^[0-9]+$/ && $5 >= 0 && $5 <= 100) {
            print $5
            found=1
        }
    }
    END {
        if (!found) exit 1
    }
'); then
    echo "ERROR: Khong the thu thap Disk" >&2
    exit 1
fi

# ================== LOGGING ==================
time_log=$(date +'%Y-%m-%d %H:%M:%S')
STATUS="OK"

write_alert() {
    if ! printf '%s\n' "$1" >> "$ALERT_LOG"; then
        echo "ERROR: Khong the ghi alert log" >&2
        exit 1
    fi
}

if (( CPU_USAGE >= THRESHOLD_CPU )); then
    STATUS="WARNING"
    write_alert "[$time_log] [WARNING] CPU=${CPU_USAGE}% THRESHOLD=${THRESHOLD_CPU}%"
fi

if (( RAM_USAGE >= THRESHOLD_MEM )); then
    STATUS="WARNING"
    write_alert "[$time_log] [WARNING] RAM=${RAM_USAGE}% THRESHOLD=${THRESHOLD_MEM}%"
fi

if (( DISK_USAGE >= THRESHOLD_DISK )); then
    STATUS="WARNING"
    write_alert "[$time_log] [WARNING] DISK=${DISK_USAGE}% THRESHOLD=${THRESHOLD_DISK}%"
fi

LOG_LINE="[$time_log] [$STATUS] CPU=${CPU_USAGE}% RAM=${RAM_USAGE}% DISK=${DISK_USAGE}%"

if ! printf '%s\n' "$LOG_LINE" >> "$METRICS_LOG"; then
    echo "ERROR: Khong the ghi metrics log" >&2
    exit 1
fi

echo "$LOG_LINE"

