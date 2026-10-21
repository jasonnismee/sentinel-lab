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

# Check required variables
for var in SRC_DIR DEST_DIR APP_LOG_DIR BACKUP_LOG_DIR  PORT DEST_SERVER SSH_KEY; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var chua duoc cau hinh" >&2
        exit 1
    fi
done

# Check source directory (local)
if [[ ! -d "$SRC_DIR" || ! -r "$SRC_DIR" || ! -x "$SRC_DIR" ]]; then
    echo "ERROR: SRC_DIR khong ton tai hoac khong the truy cap" >&2
    exit 1
fi

# Check local log directory
if [[ ! -d "$APP_LOG_DIR" || ! -w "$APP_LOG_DIR" ]]; then
    echo "ERROR: APP_LOG_DIR khong ton tai hoac khong co quyen ghi" >&2
    exit 1
fi

# ================== BACKUP LOG DIRECTORY ==================

if ! mkdir -p "$BACKUP_LOG_DIR"; then
    echo "ERROR: Khong the tao BACKUP_LOG_DIR" >&2
    exit 1
fi

BACKUP_LOG="$BACKUP_LOG_DIR/backup.log"

# Check SSH private key
if [[ ! -f "$SSH_KEY" || ! -r "$SSH_KEY" ]]; then
    echo "ERROR: SSH_KEY khong ton tai hoac khong the doc" >&2
    exit 1
fi

# Check SSH port
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: PORT phai la so nguyen" >&2
    exit 1
fi

# Normalize leading zeros, e.g. 00022 -> 22
PORT_NORMALIZED="${PORT#"${PORT%%[!0]*}"}"
PORT_NORMALIZED="${PORT_NORMALIZED:-0}"

if (( ${#PORT_NORMALIZED} > 5 )); then
    echo "ERROR: PORT phai trong khoang 1-65535" >&2
    exit 1
fi

if (( PORT_NORMALIZED < 1 || PORT_NORMALIZED > 65535 )); then
    echo "ERROR: PORT phai trong khoang 1-65535" >&2
    exit 1
fi

PORT="$PORT_NORMALIZED"

# Check destination directory format
if [[ "$DEST_DIR" != /* || "$DEST_DIR" == "/" ]]; then
    echo "ERROR: DEST_DIR phai la duong dan tuyet doi va khong duoc la /" >&2
    exit 1
fi

# Check destination server format
if ! [[ "$DEST_SERVER" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*@[a-zA-Z0-9.-]+$ ]]; then
    echo "ERROR: DEST_SERVER khong dung dinh dang user@host" >&2
    exit 1
fi

echo "Validation successful!"

# ================== BACKUP LOGGING ==================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp

    timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    local log_line="[$timestamp] [$level] $message"

    if ! printf '%s\n' "$log_line" >> "$BACKUP_LOG"; then
        echo "ERROR: Khong the ghi backup log" >&2
        return 1
    fi

    printf '%s\n' "$log_line"
}
log_message "INFO" "Backup started"
# SSH CONNECTION
if ! ssh \
    -i "$SSH_KEY" \
    -p "$PORT" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$DEST_SERVER" \
    "echo SSH_OK"; then

    log_message "ERROR" "SSH connection failed" >&2
    exit 1
fi
log_message "SUCCESS" "SSH connection successful"

# REMOTE DIRECTORY
if ! ssh \
    -i "$SSH_KEY" \
    -p "$PORT" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$DEST_SERVER" \
    "mkdir -p '$DEST_DIR'"; then
     log_message "ERROR" "Tao thu muc failed" >&2
     exit 1
fi

log_message "SUCCESS" "'$DEST_DIR' da duoc tao!"

# ================== RSYNC ==================
if ! rsync -avz \
    -e "ssh -i $SSH_KEY -p $PORT -o BatchMode=yes -o ConnectTimeout=10" \
    "$SRC_DIR" \
    "$DEST_SERVER:$DEST_DIR"; then

    log_message "ERROR" "Rsync backup that bai" >&2
    exit 1
fi

log_message "SUCCESS" "Rsync backup thanh cong"

