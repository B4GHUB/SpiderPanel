#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SpiderPanel Universal Installer + Manager
# ============================================================
#
# INSTALL:
#   curl -fsSL https://raw.githubusercontent.com/amirh00sain/SpiderPanel/main/start.sh | bash
#
# AFTER INSTALL:
#   spiderpanel
#
# COMMANDS:
#   spiderpanel
#   spiderpanel install
#   spiderpanel update
#   spiderpanel start
#   spiderpanel stop
#   spiderpanel restart
#   spiderpanel status
#   spiderpanel logs
#   spiderpanel info
#   spiderpanel uninstall
#
# VPS:
#   systemd
#
# GitHub Codespaces:
#   standalone nohup mode
#
# Application:
#   0.0.0.0:8080
# ============================================================

set +e

APP_NAME="SpiderPanel"
SERVICE_NAME="spider-panel"

APP_DIR="${SPIDER_APP_DIR:-/opt/SpiderPanel}"
ENV_FILE="/etc/spider-panel.env"

REPO="${SPIDER_REPO:-https://github.com/amirh00sain/SpiderPanel.git}"
BRANCH="${SPIDER_BRANCH:-main}"

INSTALLER_URL="${SPIDER_INSTALLER_URL:-https://raw.githubusercontent.com/amirh00sain/SpiderPanel/main/start.sh}"

PORT="${SPIDER_PORT:-8080}"

VENV_DIR="$APP_DIR/.venv"
PID_FILE="$APP_DIR/spiderpanel.pid"
LOG_FILE="$APP_DIR/spiderpanel.log"

XRAY_VERSION="${XRAY_VERSION:-26.3.27}"
XRAY_DIR="$APP_DIR/xray"
XRAY_BIN="$XRAY_DIR/xray"

MTPROXY_BIN="/usr/local/bin/mtproto-proxy"

CLI_PATH="/usr/local/bin/spiderpanel"

TMP_ROOT=""
TMP_INSTALLER=""

# ============================================================
# COLORS / LOGGING
# ============================================================

log() {
    printf '\033[1;36m[SpiderPanel]\033[0m %s\n' "$*"
}

ok() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

fail() {
    error "$*"
    exit 1
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT:-}" ]] && rm -rf "$TMP_ROOT" 2>/dev/null || true
    [[ -n "${TMP_INSTALLER:-}" && -f "${TMP_INSTALLER:-}" ]] && rm -f "$TMP_INSTALLER" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================
# ROOT / SUDO
# ============================================================

become_root() {

    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi

    command -v sudo >/dev/null 2>&1 || \
        fail "sudo is required. Please install sudo first."

    TMP_INSTALLER="$(mktemp /tmp/spiderpanel-start.XXXXXX.sh)"

    log "Downloading installer for automatic sudo execution..."

    curl -fsSL \
        --retry 3 \
        --connect-timeout 10 \
        --max-time 180 \
        "$INSTALLER_URL" \
        -o "$TMP_INSTALLER" \
        || fail "Could not download installer."

    chmod 700 "$TMP_INSTALLER"

    export SPIDER_REPO="$REPO"
    export SPIDER_BRANCH="$BRANCH"
    export SPIDER_APP_DIR="$APP_DIR"
    export SPIDER_PORT="$PORT"
    export XRAY_VERSION="$XRAY_VERSION"
    export SPIDER_INSTALLER_URL="$INSTALLER_URL"

    exec sudo -E bash "$TMP_INSTALLER" "$@"
}

# ============================================================
# OS
# ============================================================

detect_os() {

    [[ -f /etc/os-release ]] || fail "/etc/os-release not found."

    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
}

# ============================================================
# CODESPACES
# ============================================================

detect_environment() {

    IS_CODESPACE=0
    HAS_SYSTEMD=0

    if [[ "${CODESPACES:-}" == "true" || -n "${CODESPACE_NAME:-}" ]]; then
        IS_CODESPACE=1
    fi

    if command -v systemctl >/dev/null 2>&1; then

        PID1="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]' || true)"

        if [[ "$PID1" == "systemd" ]]; then
            HAS_SYSTEMD=1
        fi

    fi
}

# ============================================================
# PACKAGE INSTALLATION
# ============================================================

install_apt() {

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    apt-get install -y \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
        tar \
        gzip \
        rsync \
        python3 \
        python3-venv \
        python3-pip \
        build-essential \
        gcc \
        g++ \
        make \
        pkg-config \
        libssl-dev \
        zlib1g-dev \
        openssl \
        procps \
        iproute2 \
        iputils-ping \
        net-tools \
        lsof \
        jq \
        gnupg \
        lsb-release
}

install_dnf() {

    dnf install -y \
        ca-certificates \
        curl \
        git \
        unzip \
        xz \
        tar \
        gzip \
        rsync \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make \
        pkgconf-pkg-config \
        openssl-devel \
        zlib-devel \
        procps-ng \
        iproute \
        iputils \
        net-tools \
        lsof \
        jq
}

install_yum() {

    yum install -y \
        ca-certificates \
        curl \
        git \
        unzip \
        xz \
        tar \
        gzip \
        rsync \
        python3 \
        python3-pip \
        gcc \
        gcc-c++ \
        make \
        pkgconfig \
        openssl-devel \
        zlib-devel \
        procps \
        iproute \
        iputils \
        net-tools \
        lsof \
        jq
}

install_pacman() {

    pacman -Sy --noconfirm --needed \
        ca-certificates \
        curl \
        git \
        unzip \
        xz \
        tar \
        gzip \
        rsync \
        python \
        python-pip \
        base-devel \
        openssl \
        zlib \
        procps-ng \
        iproute2 \
        iputils \
        net-tools \
        lsof \
        jq
}

install_packages() {

    log "Installing system dependencies..."

    case "$OS_ID" in

        ubuntu|debian|linuxmint|pop|elementary)
            install_apt
            ;;

        fedora|rhel|rocky|almalinux|centos)
            if command -v dnf >/dev/null 2>&1; then
                install_dnf
            else
                install_yum
            fi
            ;;

        arch|cachyos|endeavouros|manjaro)
            install_pacman
            ;;

        *)
            if command -v apt-get >/dev/null 2>&1; then
                install_apt
            elif command -v dnf >/dev/null 2>&1; then
                install_dnf
            elif command -v yum >/dev/null 2>&1; then
                install_yum
            elif command -v pacman >/dev/null 2>&1; then
                install_pacman
            else
                fail "Unsupported Linux distribution: $OS_ID"
            fi
            ;;
    esac

    ok "System dependencies installed."
}

# ============================================================
# DOCKER
# ============================================================

install_docker() {

    [[ "$IS_CODESPACE" -eq 1 ]] && {
        log "Codespace detected: Docker installation skipped."
        return 0
    }

    if command -v docker >/dev/null 2>&1; then
        ok "Docker already installed."
        return 0
    fi

    if [[ "$HAS_SYSTEMD" -ne 1 ]]; then
        warn "systemd unavailable, Docker setup skipped."
        return 0
    fi

    case "$OS_ID" in

        ubuntu|debian|linuxmint|pop|elementary)

            install -m 0755 -d /etc/apt/keyrings

            if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then

                curl -fsSL \
                    "https://download.docker.com/linux/$OS_ID/gpg" |
                    gpg --dearmor \
                    > /etc/apt/keyrings/docker.gpg

                chmod a+r /etc/apt/keyrings/docker.gpg

            fi

            . /etc/os-release

            DOCKER_ARCH="$(dpkg --print-architecture)"
            DOCKER_CODENAME="${VERSION_CODENAME:-}"

            [[ -n "$DOCKER_CODENAME" ]] || \
                DOCKER_CODENAME="$(lsb_release -cs 2>/dev/null || true)"

            if [[ -n "$DOCKER_CODENAME" ]]; then

                cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$DOCKER_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $DOCKER_CODENAME stable
EOF

                apt-get update -y

                apt-get install -y \
                    docker-ce \
                    docker-ce-cli \
                    containerd.io \
                    docker-buildx-plugin \
                    docker-compose-plugin

                systemctl enable --now docker.service || true

                ok "Docker installed."

            fi
            ;;

        arch|cachyos|endeavouros|manjaro)

            pacman -S --noconfirm --needed docker docker-compose || true

            if command -v docker >/dev/null 2>&1; then
                systemctl enable --now docker.service || true
                ok "Docker installed."
            fi
            ;;

        fedora|rhel|rocky|almalinux|centos)

            if command -v dnf >/dev/null 2>&1; then
                dnf install -y docker || true
            else
                yum install -y docker || true
            fi

            if command -v docker >/dev/null 2>&1; then
                systemctl enable --now docker.service || true
                ok "Docker installed."
            fi
            ;;

    esac
}

# ============================================================
# DOWNLOAD SOURCE
# ============================================================

download_source() {

    TMP_ROOT="$(mktemp -d /tmp/spiderpanel.XXXXXX)"

    log "Downloading SpiderPanel..."

    git clone \
        --depth 1 \
        --branch "$BRANCH" \
        --single-branch \
        "$REPO" \
        "$TMP_ROOT/app" \
        || fail "Could not clone $REPO"

    [[ -f "$TMP_ROOT/app/main.py" ]] || \
        fail "main.py not found in repository."

    [[ -f "$TMP_ROOT/app/requirements.txt" ]] || \
        fail "requirements.txt not found in repository."

    ok "Repository downloaded."
}

# ============================================================
# DEPLOY APPLICATION
# ============================================================

deploy_application() {

    mkdir -p "$APP_DIR"

    PERSIST="$TMP_ROOT/persist"

    mkdir -p "$PERSIST"

    if [[ -d "$APP_DIR/data" ]]; then
        cp -a "$APP_DIR/data" "$PERSIST/data"
    fi

    if [[ -f "$APP_DIR/.env" ]]; then
        cp -f "$APP_DIR/.env" "$PERSIST/.env"
    fi

    log "Installing application..."

    rsync -a \
        --delete \
        --exclude '.git/' \
        --exclude '.venv/' \
        --exclude 'data/' \
        --exclude '*.pid' \
        --exclude '*.log' \
        "$TMP_ROOT/app/" \
        "$APP_DIR/"

    if [[ -d "$PERSIST/data" ]]; then
        rm -rf "$APP_DIR/data"
        cp -a "$PERSIST/data" "$APP_DIR/data"
    fi

    if [[ -f "$PERSIST/.env" ]]; then
        cp -f "$PERSIST/.env" "$APP_DIR/.env"
    fi

    mkdir -p \
        "$APP_DIR/data" \
        "$APP_DIR/data/scanned" \
        "$APP_DIR/xray"

    chmod 755 "$APP_DIR"

    ok "Application installed."
}

# ============================================================
# PYTHON
# ============================================================

setup_python() {

    PYTHON_BIN=""

    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    fi

    [[ -n "$PYTHON_BIN" ]] || fail "Python 3 not found."

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then

        log "Creating Python virtual environment..."

        "$PYTHON_BIN" -m venv "$VENV_DIR"

    fi

    log "Installing Python dependencies..."

    "$VENV_DIR/bin/python" -m pip install \
        --upgrade \
        pip \
        setuptools \
        wheel

    "$VENV_DIR/bin/python" -m pip install \
        --no-cache-dir \
        -r "$APP_DIR/requirements.txt"

    "$VENV_DIR/bin/python" -c "import uvicorn" \
        || fail "uvicorn installation failed."

    ok "Python environment ready."
}

# ============================================================
# XRAY
# ============================================================

install_xray() {

    mkdir -p "$XRAY_DIR"

    if [[ -x "$XRAY_BIN" ]]; then
        ok "Existing Xray preserved."
        return 0
    fi

    log "Installing Xray-core v$XRAY_VERSION..."

    XRAY_ZIP="$TMP_ROOT/xray.zip"

    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"

    if ! curl -fL \
        --retry 3 \
        --connect-timeout 10 \
        --max-time 180 \
        "$XRAY_URL" \
        -o "$XRAY_ZIP"; then

        warn "Xray download failed."
        return 0
    fi

    unzip -oq "$XRAY_ZIP" -d "$XRAY_DIR"

    if [[ ! -f "$XRAY_BIN" ]]; then

        FOUND_XRAY="$(find "$XRAY_DIR" -maxdepth 1 -type f -name xray -print -quit || true)"

        if [[ -n "$FOUND_XRAY" ]]; then
            mv -f "$FOUND_XRAY" "$XRAY_BIN"
        fi
    fi

    if [[ -f "$XRAY_BIN" ]]; then
        chmod 755 "$XRAY_BIN"

        rm -f \
            "$XRAY_DIR"/*.dat \
            "$XRAY_DIR"/*.json \
            "$XRAY_DIR"/*.txt \
            "$XRAY_DIR"/*.zip \
            2>/dev/null || true

        ok "Xray installed."
    else
        warn "Xray binary was not found."
    fi
}

# ============================================================
# MTPROXY
# ============================================================

install_mtproxy() {

    if [[ -x "$MTPROXY_BIN" ]]; then
        ok "Existing MTProxy preserved."
        return 0
    fi

    log "Building Telegram MTProxy..."

    MTPROXY_SRC="$TMP_ROOT/MTProxy"

    if ! git clone \
        --depth 1 \
        https://github.com/TelegramMessenger/MTProxy.git \
        "$MTPROXY_SRC"; then

        warn "Could not download MTProxy."
        return 0
    fi

    if ! make \
        -C "$MTPROXY_SRC" \
        -j"$(nproc 2>/dev/null || echo 2)"; then

        warn "MTProxy compilation failed."
        return 0
    fi

    if [[ -x "$MTPROXY_SRC/objs/bin/mtproto-proxy" ]]; then

        install \
            -m 0755 \
            "$MTPROXY_SRC/objs/bin/mtproto-proxy" \
            "$MTPROXY_BIN"

        ok "MTProxy installed."

    else
        warn "MTProxy binary was not produced."
    fi
}

# ============================================================
# ENVIRONMENT
# ============================================================

random_secret() {
    "$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
}

random_password() {
    "$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
}

setup_environment() {

    if [[ ! -f "$ENV_FILE" ]]; then

        SECRET_KEY="$(random_secret)"
        ADMIN_PASSWORD="$(random_password)"

        cat > "$ENV_FILE" <<EOF
SECRET_KEY=$SECRET_KEY
ADMIN_PASSWORD=$ADMIN_PASSWORD

DATA_DIR=$APP_DIR/data
SPIDER_DATA_DIR=$APP_DIR/data

PORT=$PORT

MTPROTO_PROXY_BIN=$MTPROXY_BIN

WORKER_SYNC_INTERVAL=3600

RAILWAY_PUBLIC_DOMAIN=
EOF

        chmod 600 "$ENV_FILE"

        ok "New environment created."

    else

        chmod 600 "$ENV_FILE"

        if ! grep -q '^PORT=' "$ENV_FILE"; then
            printf '\nPORT=%s\n' "$PORT" >> "$ENV_FILE"
        else
            sed -i "s/^PORT=.*/PORT=$PORT/" "$ENV_FILE"
        fi

        ok "Existing environment preserved."
    fi

    ADMIN_PASSWORD="$(grep '^ADMIN_PASSWORD=' "$ENV_FILE" 2>/dev/null \
        | head -n1 \
        | cut -d= -f2- || true)"

    if [[ -z "$ADMIN_PASSWORD" ]]; then

        ADMIN_PASSWORD="$(random_password)"

        printf '\nADMIN_PASSWORD=%s\n' "$ADMIN_PASSWORD" >> "$ENV_FILE"

        chmod 600 "$ENV_FILE"
    fi

    cat > "$APP_DIR/INSTALL-CREDENTIALS.txt" <<EOF
SpiderPanel initial admin password:
$ADMIN_PASSWORD

Environment file:
$ENV_FILE

Application directory:
$APP_DIR

Application port:
$PORT
EOF

    chmod 600 "$APP_DIR/INSTALL-CREDENTIALS.txt"
}

# ============================================================
# PORT HELPERS
# ============================================================

port_in_use() {

    if command -v ss >/dev/null 2>&1; then

        ss -lntp 2>/dev/null |
            grep -Eq ":${PORT}[[:space:]]"

    elif command -v lsof >/dev/null 2>&1; then

        lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1

    else

        return 1
    fi
}

port_owner() {

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
    else
        ss -lntp 2>/dev/null |
            grep -E ":${PORT}[[:space:]]" || true
    fi
}

# ============================================================
# SYSTEMD SERVICE
# ============================================================

create_systemd_service() {

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=SpiderPanel Control Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root

WorkingDirectory=$APP_DIR

EnvironmentFile=$ENV_FILE

Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1

ExecStart=$VENV_DIR/bin/uvicorn main:app --host 0.0.0.0 --port $PORT

Restart=always
RestartSec=5

TimeoutStartSec=180
TimeoutStopSec=30

KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME.service"

    ok "systemd service configured."
}

# ============================================================
# STANDALONE START
# ============================================================

stop_standalone() {

    if [[ -f "$PID_FILE" ]]; then

        PID="$(cat "$PID_FILE" 2>/dev/null || true)"

        if [[ "$PID" =~ ^[0-9]+$ ]]; then

            if kill -0 "$PID" 2>/dev/null; then

                kill "$PID" 2>/dev/null || true

                for _ in {1..20}; do

                    if ! kill -0 "$PID" 2>/dev/null; then
                        break
                    fi

                    sleep 0.25
                done

                if kill -0 "$PID" 2>/dev/null; then
                    kill -9 "$PID" 2>/dev/null || true
                fi
            fi
        fi

        rm -f "$PID_FILE"
    fi
}

start_standalone() {

    stop_standalone

    if port_in_use; then
        warn "Port $PORT is already occupied:"
        port_owner
        return 1
    fi

    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    cd "$APP_DIR"

    nohup \
        "$VENV_DIR/bin/uvicorn" \
        main:app \
        --host 0.0.0.0 \
        --port "$PORT" \
        >> "$LOG_FILE" \
        2>&1 &

    APP_PID="$!"

    echo "$APP_PID" > "$PID_FILE"

    chmod 640 "$PID_FILE"

    sleep 3

    if kill -0 "$APP_PID" 2>/dev/null; then
        ok "SpiderPanel started. PID=$APP_PID"
        return 0
    fi

    error "SpiderPanel failed to start."
    tail -n 100 "$LOG_FILE" || true

    rm -f "$PID_FILE"

    return 1
}

# ============================================================
# START
# ============================================================

start_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        if port_in_use; then

            # Do not fail when the currently running service itself owns port.
            if ! systemctl is-active --quiet "$SERVICE_NAME.service"; then
                warn "Port $PORT is already occupied:"
                port_owner
                return 1
            fi

        fi

        systemctl restart "$SERVICE_NAME.service"

        sleep 3

        if systemctl is-active --quiet "$SERVICE_NAME.service"; then
            ok "SpiderPanel is running via systemd."
            return 0
        fi

        error "SpiderPanel failed to start."
        journalctl -u "$SERVICE_NAME.service" -n 100 --no-pager || true

        return 1

    else

        start_standalone
    fi
}

# ============================================================
# STOP
# ============================================================

stop_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl stop "$SERVICE_NAME.service" >/dev/null 2>&1 || true

        ok "SpiderPanel stopped."

    else

        stop_standalone

        ok "SpiderPanel stopped."
    fi
}

# ============================================================
# STATUS
# ============================================================

status_panel() {

    echo
    echo "=============================================="
    echo "             SpiderPanel Status"
    echo "=============================================="
    echo

    echo "Application : $APP_DIR"
    echo "Port        : $PORT"

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        echo "Mode        : systemd"
        echo "Service     : $SERVICE_NAME.service"

        echo
        systemctl status \
            "$SERVICE_NAME.service" \
            --no-pager \
            || true

    else

        echo "Mode        : standalone"

        if [[ -f "$PID_FILE" ]]; then

            PID="$(cat "$PID_FILE" 2>/dev/null || true)"

            if [[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null; then
                echo "Status      : RUNNING"
                echo "PID         : $PID"
            else
                echo "Status      : STOPPED"
            fi

        else

            echo "Status      : STOPPED"

        fi

        echo "Log         : $LOG_FILE"
    fi

    echo
}

# ============================================================
# GET PUBLIC IP
# ============================================================

get_public_ip() {

    curl \
        -4 \
        -fsS \
        --max-time 5 \
        https://api.ipify.org \
        2>/dev/null \
        || true
}

get_local_ip() {

    ip -4 route get 1.1.1.1 2>/dev/null |
        awk '
        {
            for(i=1;i<=NF;i++) {
                if($i=="src") {
                    print $(i+1)
                    exit
                }
            }
        }
        ' || true
}

# ============================================================
# CODESPACE URL
# ============================================================

get_codespace_url() {

    if [[ "$IS_CODESPACE" -eq 1 && -n "${CODESPACE_NAME:-}" ]]; then

        DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"

        echo "https://${CODESPACE_NAME}-${PORT}.${DOMAIN}/spider"
    fi
}

# ============================================================
# INFO
# ============================================================

info_panel() {

    ADMIN_PASSWORD=""

    if [[ -f "$ENV_FILE" ]]; then

        # shellcheck disable=SC1090
        ADMIN_PASSWORD="$(
            grep '^ADMIN_PASSWORD=' "$ENV_FILE" 2>/dev/null |
                head -n1 |
                cut -d= -f2- || true
        )"

    fi

    PUBLIC_IP="$(get_public_ip)"
    LOCAL_IP="$(get_local_ip)"
    CODESPACE_URL="$(get_codespace_url)"

    echo
    echo "============================================================"
    echo "                    SPIDERPANEL"
    echo "============================================================"
    echo

    echo "Application : $APP_DIR"
    echo "Environment : $ENV_FILE"
    echo "Port        : $PORT"

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then
        echo "Mode        : systemd"
        echo "Service     : $SERVICE_NAME.service"
    else
        echo "Mode        : standalone"
    fi

    echo

    if [[ -n "$PUBLIC_IP" ]]; then
        echo "Public URL  : http://${PUBLIC_IP}:${PORT}/spider"
    fi

    if [[ -n "$LOCAL_IP" ]]; then
        echo "Local URL   : http://${LOCAL_IP}:${PORT}/spider"
    fi

    if [[ -n "$CODESPACE_URL" ]]; then
        echo "Codespace   : $CODESPACE_URL"
    fi

    echo

    echo "Admin password:"
    if [[ -n "$ADMIN_PASSWORD" ]]; then
        echo "$ADMIN_PASSWORD"
    else
        echo "NOT FOUND"
    fi

    echo

    echo "Credentials : $APP_DIR/INSTALL-CREDENTIALS.txt"

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then
        echo
        echo "Status      : systemctl status $SERVICE_NAME"
        echo "Logs        : journalctl -u $SERVICE_NAME -f"
        echo "Restart     : systemctl restart $SERVICE_NAME"
    else
        echo
        echo "Log         : $LOG_FILE"
        echo "PID         : $PID_FILE"
    fi

    echo
    echo "============================================================"
    echo
}

# ============================================================
# LOGS
# ============================================================

logs_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        journalctl \
            -u "$SERVICE_NAME.service" \
            -f

    else

        touch "$LOG_FILE"
        tail -f "$LOG_FILE"

    fi
}

# ============================================================
# UPDATE
# ============================================================

update_panel() {

    log "Updating SpiderPanel..."

    stop_panel || true

    NEW_ROOT="$(mktemp -d /tmp/spiderpanel-update.XXXXXX)"

    if ! git clone \
        --depth 1 \
        --branch "$BRANCH" \
        --single-branch \
        "$REPO" \
        "$NEW_ROOT/app"; then

        rm -rf "$NEW_ROOT"

        fail "Update download failed."
    fi

    [[ -f "$NEW_ROOT/app/main.py" ]] ||
        fail "Updated source does not contain main.py."

    [[ -f "$NEW_ROOT/app/requirements.txt" ]] ||
        fail "Updated source does not contain requirements.txt."

    PERSIST="$NEW_ROOT/persist"

    mkdir -p "$PERSIST"

    if [[ -d "$APP_DIR/data" ]]; then
        cp -a "$APP_DIR/data" "$PERSIST/data"
    fi

    if [[ -f "$APP_DIR/.env" ]]; then
        cp -f "$APP_DIR/.env" "$PERSIST/.env"
    fi

    rsync -a \
        --delete \
        --exclude '.git/' \
        --exclude '.venv/' \
        --exclude 'data/' \
        --exclude '*.pid' \
        --exclude '*.log' \
        "$NEW_ROOT/app/" \
        "$APP_DIR/"

    if [[ -d "$PERSIST/data" ]]; then
        rm -rf "$APP_DIR/data"
        cp -a "$PERSIST/data" "$APP_DIR/data"
    fi

    if [[ -f "$PERSIST/.env" ]]; then
        cp -f "$PERSIST/.env" "$APP_DIR/.env"
    fi

    mkdir -p \
        "$APP_DIR/data" \
        "$APP_DIR/data/scanned" \
        "$APP_DIR/xray"

    "$VENV_DIR/bin/python" -m pip install \
        --no-cache-dir \
        -r "$APP_DIR/requirements.txt"

    "$VENV_DIR/bin/python" -m compileall -q "$APP_DIR" || {
        error "Python validation failed after update."
        rm -rf "$NEW_ROOT"
        return 1
    }

    rm -rf "$NEW_ROOT"

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then
        create_systemd_service
    fi

    start_panel || return 1

    ok "SpiderPanel updated successfully."

    info_panel
}

# ============================================================
# UNINSTALL
# ============================================================

uninstall_panel() {

    echo
    echo "WARNING: This will remove SpiderPanel."
    echo
    echo "Application directory:"
    echo "  $APP_DIR"
    echo
    echo "Environment:"
    echo "  $ENV_FILE"
    echo

    read -r -p "Type REMOVE to continue: " CONFIRM

    if [[ "$CONFIRM" != "REMOVE" ]]; then
        echo "Cancelled."
        return 0
    fi

    log "Stopping SpiderPanel..."

    stop_panel || true

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl disable \
            "$SERVICE_NAME.service" \
            >/dev/null 2>&1 || true

        rm -f \
            "/etc/systemd/system/${SERVICE_NAME}.service"

        systemctl daemon-reload || true
    fi

    rm -f "$PID_FILE" 2>/dev/null || true
    rm -f "$CLI_PATH" 2>/dev/null || true
    rm -f "$ENV_FILE" 2>/dev/null || true

    rm -rf "$APP_DIR"

    ok "SpiderPanel completely removed."
}

# ============================================================
# CREATE CLI
# ============================================================

create_cli() {

    cat > "$CLI_PATH" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/SpiderPanel"
ENV_FILE="/etc/spider-panel.env"
SERVICE_NAME="spider-panel"
PORT="${SPIDER_PORT:-8080}"

PID_FILE="$APP_DIR/spiderpanel.pid"
LOG_FILE="$APP_DIR/spiderpanel.log"

IS_CODESPACE=0
HAS_SYSTEMD=0

if [[ "${CODESPACES:-}" == "true" || -n "${CODESPACE_NAME:-}" ]]; then
    IS_CODESPACE=1
fi

if command -v systemctl >/dev/null 2>&1; then
    PID1="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]' || true)"

    if [[ "$PID1" == "systemd" ]]; then
        HAS_SYSTEMD=1
    fi
fi

get_public_ip() {
    curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
}

get_local_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{
            for(i=1;i<=NF;i++) {
                if($i=="src") {
                    print $(i+1)
                    exit
                }
            }
        }' || true
}

get_codespace_url() {

    if [[ "$IS_CODESPACE" -eq 1 && -n "${CODESPACE_NAME:-}" ]]; then

        DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"

        echo "https://${CODESPACE_NAME}-${PORT}.${DOMAIN}/spider"
    fi
}

get_password() {

    if [[ -f "$ENV_FILE" ]]; then

        grep '^ADMIN_PASSWORD=' "$ENV_FILE" 2>/dev/null |
            head -n1 |
            cut -d= -f2- || true

    fi
}

running() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl is-active --quiet "$SERVICE_NAME.service"

    else

        [[ -f "$PID_FILE" ]] || return 1

        PID="$(cat "$PID_FILE" 2>/dev/null || true)"

        [[ "$PID" =~ ^[0-9]+$ ]] || return 1

        kill -0 "$PID" 2>/dev/null

    fi
}

start_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl restart "$SERVICE_NAME.service"

    else

        if [[ -f "$PID_FILE" ]]; then

            PID="$(cat "$PID_FILE" 2>/dev/null || true)"

            if [[ "$PID" =~ ^[0-9]+$ ]] &&
               kill -0 "$PID" 2>/dev/null; then

                echo "SpiderPanel is already running."

                return 0
            fi

            rm -f "$PID_FILE"
        fi

        nohup \
            "$APP_DIR/.venv/bin/uvicorn" \
            main:app \
            --host 0.0.0.0 \
            --port "$PORT" \
            >> "$LOG_FILE" \
            2>&1 &

        echo "$!" > "$PID_FILE"

    fi

    sleep 2

    if running; then
        echo "SpiderPanel started."
    else
        echo "SpiderPanel failed to start."
        exit 1
    fi
}

stop_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl stop "$SERVICE_NAME.service" || true

    else

        if [[ -f "$PID_FILE" ]]; then

            PID="$(cat "$PID_FILE" 2>/dev/null || true)"

            if [[ "$PID" =~ ^[0-9]+$ ]]; then
                kill "$PID" 2>/dev/null || true
            fi

            rm -f "$PID_FILE"
        fi

    fi

    echo "SpiderPanel stopped."
}

restart_panel() {
    stop_panel
    sleep 1
    start_panel
}

status_panel() {

    echo
    echo "SpiderPanel status"
    echo "------------------"

    if running; then
        echo "Status : RUNNING"
    else
        echo "Status : STOPPED"
    fi

    echo "Port   : $PORT"
    echo "Mode   : $([[ "$HAS_SYSTEMD" -eq 1 ]] && echo systemd || echo standalone)"

    echo
}

info_panel() {

    PUBLIC_IP="$(get_public_ip)"
    LOCAL_IP="$(get_local_ip)"
    CODE_URL="$(get_codespace_url)"
    PASSWORD="$(get_password)"

    echo
    echo "============================================================"
    echo "                    SPIDERPANEL"
    echo "============================================================"
    echo

    echo "Application : $APP_DIR"
    echo "Environment : $ENV_FILE"
    echo "Port        : $PORT"

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then
        echo "Mode        : systemd"
        echo "Service     : $SERVICE_NAME.service"
    else
        echo "Mode        : standalone"
        echo "PID         : $PID_FILE"
        echo "Log         : $LOG_FILE"
    fi

    echo

    if [[ -n "$PUBLIC_IP" ]]; then
        echo "Public URL  : http://${PUBLIC_IP}:${PORT}/spider"
    fi

    if [[ -n "$LOCAL_IP" ]]; then
        echo "Local URL   : http://${LOCAL_IP}:${PORT}/spider"
    fi

    if [[ -n "$CODE_URL" ]]; then
        echo "Codespace   : $CODE_URL"
    fi

    echo

    echo "Admin password:"
    echo "${PASSWORD:-NOT FOUND}"

    echo

    echo "Credentials : $APP_DIR/INSTALL-CREDENTIALS.txt"

    echo

    echo "Commands:"
    echo "  spiderpanel"
    echo "  spiderpanel info"
    echo "  spiderpanel status"
    echo "  spiderpanel start"
    echo "  spiderpanel stop"
    echo "  spiderpanel restart"
    echo "  spiderpanel update"
    echo "  spiderpanel logs"
    echo "  spiderpanel uninstall"

    echo
    echo "============================================================"
    echo
}

logs_panel() {

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        journalctl -u "$SERVICE_NAME.service" -f

    else

        touch "$LOG_FILE"

        tail -f "$LOG_FILE"
    fi
}

update_panel() {

    curl -fsSL \
        "https://raw.githubusercontent.com/amirh00sain/SpiderPanel/main/start.sh" |
        bash
}

uninstall_panel() {

    echo
    echo "WARNING: This will remove SpiderPanel."
    echo
    read -r -p "Type REMOVE to continue: " CONFIRM

    if [[ "$CONFIRM" != "REMOVE" ]]; then
        echo "Cancelled."
        exit 0
    fi

    stop_panel || true

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        systemctl disable "$SERVICE_NAME.service" >/dev/null 2>&1 || true

        rm -f \
            "/etc/systemd/system/${SERVICE_NAME}.service"

        systemctl daemon-reload || true
    fi

    rm -f "$PID_FILE" 2>/dev/null || true
    rm -f "$ENV_FILE" 2>/dev/null || true

    rm -rf "$APP_DIR"
    rm -f "/usr/local/bin/spiderpanel"

    echo "SpiderPanel completely removed."
}

menu() {

    while true; do

        clear 2>/dev/null || true

        echo
        echo "============================================================"
        echo "                    SPIDERPANEL"
        echo "============================================================"
        echo
        echo "  1) Info"
        echo "  2) Status"
        echo "  3) Start"
        echo "  4) Stop"
        echo "  5) Restart"
        echo "  6) Update"
        echo "  7) Logs"
        echo "  8) Uninstall"
        echo "  0) Exit"
        echo
        printf "Select: "

        read -r CHOICE

        case "$CHOICE" in

            1)
                info_panel
                read -r -p "Press Enter..."
                ;;

            2)
                status_panel
                read -r -p "Press Enter..."
                ;;

            3)
                start_panel
                read -r -p "Press Enter..."
                ;;

            4)
                stop_panel
                read -r -p "Press Enter..."
                ;;

            5)
                restart_panel
                read -r -p "Press Enter..."
                ;;

            6)
                update_panel
                read -r -p "Press Enter..."
                ;;

            7)
                logs_panel
                ;;

            8)
                uninstall_panel
                exit 0
                ;;

            0)
                exit 0
                ;;

            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac

    done
}

COMMAND="${1:-menu}"

case "$COMMAND" in

    menu)
        menu
        ;;

    info)
        info_panel
        ;;

    status)
        status_panel
        ;;

    start)
        start_panel
        ;;

    stop)
        stop_panel
        ;;

    restart)
        restart_panel
        ;;

    update)
        update_panel
        ;;

    logs)
        logs_panel
        ;;

    uninstall|remove|delete)
        uninstall_panel
        ;;

    *)
        echo
        echo "SpiderPanel"
        echo
        echo "Usage:"
        echo "  spiderpanel"
        echo "  spiderpanel info"
        echo "  spiderpanel status"
        echo "  spiderpanel start"
        echo "  spiderpanel stop"
        echo "  spiderpanel restart"
        echo "  spiderpanel update"
        echo "  spiderpanel logs"
        echo "  spiderpanel uninstall"
        echo
        ;;
esac
EOF

    chmod 755 "$CLI_PATH"

    ok "Command installed: spiderpanel"
}

# ============================================================
# VALIDATE
# ============================================================

validate_application() {

    log "Validating Python source..."

    cd "$APP_DIR"

    "$VENV_DIR/bin/python" -m compileall -q "$APP_DIR" ||
        fail "Python syntax validation failed."

    ok "Python validation passed."
}

# ============================================================
# INSTALL
# ============================================================

install_panel() {

    become_root "$@"

    detect_os
    detect_environment

    echo
    log "Installing $APP_NAME..."
    echo

    log "OS: ${PRETTY_NAME:-$OS_ID}"

    if [[ "$IS_CODESPACE" -eq 1 ]]; then
        log "Environment: GitHub Codespaces"
    elif [[ "$HAS_SYSTEMD" -eq 1 ]]; then
        log "Environment: Linux VPS / systemd"
    else
        log "Environment: Linux / no systemd"
    fi

    echo

    install_packages

    install_docker

    download_source

    deploy_application

    setup_python

    install_xray

    install_mtproxy

    setup_environment

    validate_application

    if [[ "$HAS_SYSTEMD" -eq 1 ]]; then

        create_systemd_service

        start_panel

    else

        start_panel

    fi

    create_cli

    # Make command available in current environment.
    hash -r 2>/dev/null || true

    echo
    ok "SpiderPanel installation finished."
    echo

    info_panel
}

# ============================================================
# MAIN
# ============================================================

COMMAND="${1:-install}"

case "$COMMAND" in

    install)
        install_panel "$@"
        ;;

    *)
        #
        # If somebody executes this local installer directly
        # with a manager command, install the CLI first only
        # when needed.
        #

        become_root "$@"

        detect_os
        detect_environment

        if [[ ! -x "$CLI_PATH" ]]; then
            install_panel install
        else
            exec "$CLI_PATH" "$@"
        fi
        ;;

esac
