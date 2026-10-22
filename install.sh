
#!/bin/bash
set -euo pipefail

# ==========================================
# 1. Xac dinh duong dan du an
# ==========================================

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$SCRIPT_PATH")"
SYSTEMD_DIR="$PROJECT_DIR/systemd"
SYSTEMD_TARGET="/etc/systemd/system"
ENV_FILE="$PROJECT_DIR/config/.env"

# ==========================================
# 2. Kiem tra quyen root
# ==========================================

if (( EUID != 0 )); then
    echo "ERROR: Vui long chay install.sh bang sudo" >&2
    exit 1
fi

echo "Starting Sentinel installation..."

# ==========================================
# 3. Xac dinh application user
# ==========================================

APP_USER="${SUDO_USER:-}"

if [[ -z "$APP_USER" || "$APP_USER" == "root" ]]; then
    echo "ERROR: Run installer using sudo from a normal user" >&2
    exit 1
fi

if ! id "$APP_USER" &>/dev/null; then
    echo "ERROR: User $APP_USER does not exist" >&2
    exit 1
fi

echo "Application user: $APP_USER"

# ==========================================
# 4. Kiem tra file .env
# ==========================================

if [[ ! -f "$ENV_FILE" || ! -r "$ENV_FILE" ]]; then
    echo "ERROR: Missing or unreadable config/.env" >&2
    echo "Please create config/.env from config/.env.example" >&2
    exit 1
fi

# Kiem tra application user co the doc .env
if ! runuser -u "$APP_USER" -- test -r "$ENV_FILE"; then
    echo "ERROR: $APP_USER cannot read config/.env" >&2
    exit 1
fi

echo "Environment file found."
echo "Project directory: $PROJECT_DIR"
echo "Systemd directory: $SYSTEMD_DIR"

# ==========================================
# 5. Khai bao cac file systemd
# ==========================================

UNIT_FILES=(
    "sentinel-collector.service"
    "sentinel-collector.timer"
    "sentinel-backup.service"
    "sentinel-backup.timer"
)

TEMPLATE_FILES=(
    "sentinel-collector.service.template"
    "sentinel-backup.service.template"
)

# ==========================================
# 6. Kiem tra template va timer
# ==========================================

echo "Checking source unit files..."

for file in "${TEMPLATE_FILES[@]}" \
            "sentinel-collector.timer" \
            "sentinel-backup.timer"; do

    if [[ ! -f "$SYSTEMD_DIR/$file" || ! -r "$SYSTEMD_DIR/$file" ]]; then
        echo "ERROR: Missing or unreadable: $SYSTEMD_DIR/$file" >&2
        exit 1
    fi
done

# ==========================================
# 7. Tao thu muc tam
# ==========================================

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# ==========================================
# 8. Sinh service tu template
# ==========================================

echo "Generating systemd services..."

# Escape cac ky tu dac biet trong sed replacement
escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

ESCAPED_USER="$(escape_sed_replacement "$APP_USER")"
ESCAPED_DIR="$(escape_sed_replacement "$PROJECT_DIR")"

for service in sentinel-collector sentinel-backup; do
    sed \
        -e "s|__APP_USER__|$ESCAPED_USER|g" \
        -e "s|__PROJECT_DIR__|$ESCAPED_DIR|g" \
        "$SYSTEMD_DIR/$service.service.template" \
        > "$TEMP_DIR/$service.service"
done

# Copy timer vao thu muc tam
for timer in sentinel-collector.timer sentinel-backup.timer; do
    cp "$SYSTEMD_DIR/$timer" "$TEMP_DIR/$timer"
done

# ==========================================
# 9. Kiem tra placeholder va systemd unit
# ==========================================

echo "Validating generated systemd units..."

for unit in "${UNIT_FILES[@]}"; do
    unit_path="$TEMP_DIR/$unit"

    if grep -Eq '__APP_USER__|__PROJECT_DIR__' "$unit_path"; then
        echo "ERROR: Unresolved placeholder in $unit" >&2
        exit 1
    fi

    echo "Checking $unit..."

    if ! systemd-analyze verify "$unit_path"; then
        echo "ERROR: Invalid systemd unit: $unit" >&2
        exit 1
    fi
done

echo "Systemd unit validation completed."

# ==========================================
# 10. Cai dat cac file systemd
# ==========================================

echo "Installing systemd unit files..."

for unit in "${UNIT_FILES[@]}"; do
    echo "Installing $unit..."

    if ! install -m 644 "$TEMP_DIR/$unit" "$SYSTEMD_TARGET/$unit"; then
        echo "ERROR: Failed to install $unit" >&2
        exit 1
    fi
done

# ==========================================
# 11. Reload systemd
# ==========================================

echo "Reloading systemd..."

if ! systemctl daemon-reload; then
    echo "ERROR: Failed to reload systemd" >&2
    exit 1
fi

echo "Systemd unit installation completed."

# ==========================================
# 12. Bat collector timer
# ==========================================

echo "Enabling Sentinel collector timer..."

if ! systemctl enable --now sentinel-collector.timer; then
    echo "ERROR: Failed to enable collector timer" >&2
    exit 1
fi

if ! systemctl is-active --quiet sentinel-collector.timer; then
    echo "ERROR: Collector timer is not active" >&2
    exit 1
fi

echo "Collector timer is active."

# ==========================================
# 13. Thong bao backup timer
# ==========================================

echo "Backup timer is not automatically enabled by this installer."
echo "Check its existing state before starting AWS EC2 backups."

echo "Sentinel installation completed successfully!"

