
#!/bin/bash
set -euo pipefail

# ==========================================
# 1. Xac dinh duong dan du an
# ==========================================

SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$SCRIPT_PATH")"

echo "Starting Sentinel environment setup..."
echo "Project directory: $PROJECT_DIR"

# ==========================================
# 2. Kiem tra quyen va tham so
# ==========================================

if (( EUID == 0 )); then
    echo "ERROR: Run setup.sh as a normal user, not root" >&2
    exit 1
fi

INSTALL_DEPS=false

if (( $# > 1 )); then
    echo "ERROR: Too many arguments" >&2
    exit 1
fi

if (( $# == 1 )); then
    case "$1" in
        --install-deps)
            INSTALL_DEPS=true
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
fi

# ==========================================
# 3. Khai bao dependencies
# ==========================================

declare -A PACKAGES=(
    [bash]="bash"
    [ssh]="openssh-client"
    [rsync]="rsync"
    [flock]="util-linux"
    [systemctl]="systemd"
    [systemd-analyze]="systemd"
)

DEPENDENCIES=(
    bash
    ssh
    rsync
    flock
    systemctl
    systemd-analyze
)

MISSING_PACKAGES=()

# ==========================================
# 4. Kiem tra dependencies
# ==========================================

echo "Checking dependencies..."

for cmd in "${DEPENDENCIES[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "[OK] $cmd"
    else
        package="${PACKAGES[$cmd]}"
        echo "[MISSING] $cmd (package: $package)"

        found=false

        for existing in "${MISSING_PACKAGES[@]}"; do
            if [[ "$existing" == "$package" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            MISSING_PACKAGES+=("$package")
        fi
    fi
done

# ==========================================
# 5. Cai dat dependencies neu can
# ==========================================

if (( ${#MISSING_PACKAGES[@]} == 0 )); then
    echo "All dependencies are available."
else
    echo "Missing packages: ${MISSING_PACKAGES[*]}"

    if [[ "$INSTALL_DEPS" == false ]]; then
        echo "Run ./setup.sh --install-deps to install missing packages." >&2
        exit 1
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        echo "ERROR: apt-get is unavailable" >&2
        exit 1
    fi

    echo "Installing missing packages..."

    sudo apt-get update
    sudo apt-get install -y "${MISSING_PACKAGES[@]}"

    # Kiem tra lai sau khi cai dat
    for cmd in "${DEPENDENCIES[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "ERROR: $cmd is still unavailable" >&2
            exit 1
        fi
    done

    echo "Dependency installation completed successfully."
fi

# ==========================================
# 6. Xac dinh file cau hinh
# ==========================================

CONFIG_DIR="$PROJECT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"
ENV_EXAMPLE="$CONFIG_DIR/.env.example"

echo "Checking environment configuration..."

# ==========================================
# 7. Kiem tra hoac khoi tao .env
# ==========================================

if [[ -e "$ENV_FILE" || -L "$ENV_FILE" ]]; then

    if [[ ! -f "$ENV_FILE" || ! -r "$ENV_FILE" ]]; then
        echo "ERROR: Existing .env is not a readable regular file" >&2
        exit 1
    fi

    echo "[OK] config/.env already exists. Keeping it unchanged."

else

    if [[ ! -f "$ENV_EXAMPLE" || ! -r "$ENV_EXAMPLE" ]]; then
        echo "ERROR: Missing or unreadable config/.env.example" >&2
        exit 1
    fi

    # Chi tao khi file chua ton tai
    if ! (umask 077; cp --no-clobber "$ENV_EXAMPLE" "$ENV_FILE"); then
        echo "ERROR: Failed to create config/.env" >&2
        exit 1
    fi

    echo "[CREATED] config/.env from config/.env.example"
    echo "ACTION REQUIRED: Review and configure config/.env"
fi

echo "Environment configuration check completed."
echo "Sentinel environment setup completed."
