#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# SpiderPanel VPS Installer / Starter
# Self-elevating, stdin-safe installer.
# Works with:
#   curl -fsSL https://raw.githubusercontent.com/amirh00sain/SpiderPanel/main/start.sh | bash
#   bash start.sh
#   sudo bash start.sh
# Avoid process substitution with sudo (<(curl ...)) because sudo may
# not inherit the caller's /dev/fd namespace.
# ============================================================

APP_DIR="/opt/SpiderPanel"
REPO="${SPIDER_REPO:-https://github.com/amirh00sain/SpiderPanel.git}"
BRANCH="${SPIDER_BRANCH:-main}"
SERVICE_NAME="spider-panel"
ENV_FILE="/etc/spider-panel.env"
TMP_SCRIPT=""

log()  { printf '\033[1;36m[SpiderPanel]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [[ -n "${TMP_SCRIPT:-}" && -f "$TMP_SCRIPT" ]]; then
        rm -f "$TMP_SCRIPT" || true
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------
# Self-elevate safely.
# A command such as `sudo bash <(curl ...)` can fail before this
# script starts because sudo cannot always access /dev/fd/N.
# This block makes plain `curl | bash` fully automatic instead.
# ------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || fail "sudo is required for automatic root installation."

    TMP_SCRIPT="$(mktemp /tmp/spiderpanel-start.XXXXXX.sh)"
    chmod 700 "$TMP_SCRIPT"

    # When stdin is a pipe (curl | bash), stdin is the script itself.
    # `cat` safely copies it before sudo changes privileges.
    if [[ ! -t 0 ]]; then
        cat > "$TMP_SCRIPT"
    elif [[ -r "$0" && "$0" != /dev/fd/* && "$0" != /proc/self/fd/* ]]; then
        cat "$0" > "$TMP_SCRIPT"
    else
        fail "Could not safely copy the installer. Use: curl -fsSL URL | bash"
    fi

    exec sudo -E env SPIDER_REPO="$REPO" SPIDER_BRANCH="$BRANCH" bash "$TMP_SCRIPT" "$@"
fi

# ------------------------------------------------------------
# OS / package manager
# ------------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
else
    fail "/etc/os-release not found; unsupported operating system."
fi

install_apt() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils tar gzip \
        python3 python3-venv python3-pip \
        build-essential gcc g++ make pkg-config \
        libssl-dev zlib1g-dev \
        openssl procps iproute2 iputils-ping net-tools \
        lsof jq rsync gnupg lsb-release
}

install_dnf() {
    dnf install -y \
        ca-certificates curl git unzip xz tar gzip \
        python3 python3-pip \
        gcc gcc-c++ make pkgconf-pkg-config openssl-devel zlib-devel \
        procps-ng iproute iputils net-tools \
        lsof jq rsync
}

install_yum() {
    yum install -y \
        ca-certificates curl git unzip xz tar gzip \
        python3 python3-pip \
        gcc gcc-c++ make pkgconfig openssl-devel zlib-devel \
        procps iproute iputils net-tools \
        lsof jq rsync
}

install_pacman() {
    pacman -Sy --noconfirm --needed \
        ca-certificates curl git unzip xz tar gzip \
        python python-pip \
        base-devel openssl zlib \
        procps-ng iproute2 iputils net-tools \
        lsof jq rsync
}

log "Installing system dependencies..."
case "${ID:-}" in
    arch|cachyos|endeavouros|manjaro)
        install_pacman ;;
    ubuntu|debian|linuxmint|pop|elementary)
        install_apt ;;
    fedora|rhel|rocky|almalinux|centos)
        if command -v dnf >/dev/null 2>&1; then install_dnf; else install_yum; fi ;;
    *)
        if command -v apt-get >/dev/null 2>&1; then install_apt
        elif command -v dnf >/dev/null 2>&1; then install_dnf
        elif command -v yum >/dev/null 2>&1; then install_yum
        elif command -v pacman >/dev/null 2>&1; then install_pacman
        else fail "Unsupported Linux distribution: ${ID:-unknown}"; fi
        ;;
esac
ok "Base system dependencies installed."

# ------------------------------------------------------------
# Optional Docker support
# SpiderPanel's Telegram/runtime helpers can use Docker on VPS setups.
# Install Docker only when missing; do not alter an existing installation.
# ------------------------------------------------------------
install_docker_apt() {
    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker..."
        install -m 0755 -d /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
            curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        fi
        . /etc/os-release
        local arch codename
        arch="$(dpkg --print-architecture)"
        codename="${VERSION_CODENAME:-$(. /etc/os-release; echo "$UBUNTU_CODENAME")}"
        if [[ -z "$codename" ]]; then
            codename="$(lsb_release -cs 2>/dev/null || true)"
        fi
        [[ -n "$codename" ]] || return 0
        cat > /etc/apt/sources.list.d/docker.list <<DOCKERREPO
deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $codename stable
DOCKERREPO
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files docker.service >/dev/null 2>&1; then
        systemctl enable --now docker.service || true
    fi
}

case "${ID:-}" in
    ubuntu|debian|linuxmint|pop|elementary)
        if ! command -v docker >/dev/null 2>&1; then
            install_docker_apt || warn "Docker installation skipped; SpiderPanel can still run without Docker on this build."
        fi
        ;;
    fedora|rhel|rocky|almalinux|centos)
        if ! command -v docker >/dev/null 2>&1; then
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y docker || true
            elif command -v yum >/dev/null 2>&1; then
                yum install -y docker || true
            fi
        fi
        if command -v systemctl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
            systemctl enable --now docker.service || true
        fi
        ;;
    arch|cachyos|endeavouros|manjaro)
        if ! command -v docker >/dev/null 2>&1; then
            pacman -S --noconfirm --needed docker docker-compose || warn "Docker installation skipped."
        fi
        if command -v systemctl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
            systemctl enable --now docker.service || true
        fi
        ;;
esac

# ------------------------------------------------------------
# Fetch source safely.
# Never run the app from a partial git checkout.
# ------------------------------------------------------------
log "Fetching SpiderPanel from $REPO (branch: $BRANCH)..."
WORK_ROOT="$(mktemp -d /tmp/spiderpanel-source.XXXXXX)"
cleanup_source() { rm -rf "$WORK_ROOT" || true; }
trap 'cleanup_source; cleanup' EXIT

if git clone --depth 1 --branch "$BRANCH" --single-branch "$REPO" "$WORK_ROOT/app"; then
    ok "Repository downloaded."
else
    fail "Could not download SpiderPanel from $REPO."
fi

mkdir -p "$APP_DIR"

# Preserve persistent runtime state before replacing application files.
PERSIST_TMP="$WORK_ROOT/persist"
mkdir -p "$PERSIST_TMP"
for item in data .env; do
    if [[ -e "$APP_DIR/$item" ]]; then
        cp -a "$APP_DIR/$item" "$PERSIST_TMP/" 2>/dev/null || true
    fi
done

rsync -a --delete --exclude '.venv/' --exclude 'data/' --exclude '.git/' "$WORK_ROOT/app/" "$APP_DIR/"

if [[ -e "$PERSIST_TMP/data" ]]; then
    rm -rf "$APP_DIR/data"
    cp -a "$PERSIST_TMP/data" "$APP_DIR/data"
fi
if [[ -e "$PERSIST_TMP/.env" ]]; then
    cp -a "$PERSIST_TMP/.env" "$APP_DIR/.env"
fi

mkdir -p "$APP_DIR/data" "$APP_DIR/data/scanned" "$APP_DIR/xray"
chmod +x "$APP_DIR/start.sh" "$APP_DIR/run.sh" 2>/dev/null || true

# ------------------------------------------------------------
# Python environment
# ------------------------------------------------------------
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"
else fail "Python 3 is not installed."; fi

log "Creating/updating Python virtual environment..."
if [[ ! -x "$APP_DIR/.venv/bin/python" ]]; then
    "$PYTHON_BIN" -m venv "$APP_DIR/.venv"
fi

VENV_PY="$APP_DIR/.venv/bin/python"
VENV_PIP="$APP_DIR/.venv/bin/pip"

"$VENV_PIP" install --upgrade pip setuptools wheel
"$VENV_PIP" install -r "$APP_DIR/requirements.txt"
ok "Python environment ready."

# ------------------------------------------------------------
# Xray: pre-install official binary so first Reality operation does not
# need to wait for an application-level download.
# ------------------------------------------------------------
XRAY_VERSION="${XRAY_VERSION:-26.3.27}"
XRAY_DIR="$APP_DIR/xray"
XRAY_BIN="$XRAY_DIR/xray"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"

if [[ ! -x "$XRAY_BIN" ]]; then
    log "Downloading Xray-core v${XRAY_VERSION}..."
    XRAY_ZIP="$WORK_ROOT/xray.zip"
    if curl -fL --retry 3 --connect-timeout 10 --max-time 180 "$XRAY_URL" -o "$XRAY_ZIP"; then
        mkdir -p "$XRAY_DIR"
        unzip -oq "$XRAY_ZIP" -d "$XRAY_DIR"
        if [[ ! -f "$XRAY_BIN" ]]; then
            XRAY_FOUND="$(find "$XRAY_DIR" -maxdepth 1 -type f -name 'xray' -print -quit)"
            [[ -n "$XRAY_FOUND" ]] && mv -f "$XRAY_FOUND" "$XRAY_BIN"
        fi
        [[ -f "$XRAY_BIN" ]] || fail "Xray archive was downloaded but the xray binary was not found."
        chmod 0755 "$XRAY_BIN"
        rm -f "$XRAY_DIR"/*.dat "$XRAY_DIR"/*.json "$XRAY_DIR"/*.txt "$XRAY_DIR"/*.zip 2>/dev/null || true
        ok "Xray-core installed at $XRAY_BIN."
    else
        warn "Xray pre-download failed; SpiderPanel will attempt its built-in download on first startup."
    fi
else
    ok "Existing Xray binary preserved."
fi

# ------------------------------------------------------------
# Telegram MTProxy binary: build official binary when possible.
# SpiderPanel uses /usr/local/bin/mtproto-proxy by default.
# ------------------------------------------------------------
MTPROXY_BIN="/usr/local/bin/mtproto-proxy"
if [[ ! -x "$MTPROXY_BIN" ]]; then
    log "Building official Telegram MTProxy binary..."
    MTPROXY_SRC="$WORK_ROOT/MTProxy"
    if git clone --depth 1 https://github.com/TelegramMessenger/MTProxy.git "$MTPROXY_SRC" \
       && make -C "$MTPROXY_SRC" -j"$(nproc 2>/dev/null || echo 2)" \
       && [[ -x "$MTPROXY_SRC/objs/bin/mtproto-proxy" ]]; then
        install -m 0755 "$MTPROXY_SRC/objs/bin/mtproto-proxy" "$MTPROXY_BIN"
        ok "Official MTProxy installed at $MTPROXY_BIN."
    else
        warn "Could not build MTProxy; Telegram proxy will report its missing binary until installed."
    fi
else
    ok "Existing MTProxy binary preserved."
fi

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    SECRET_KEY="$($VENV_PY - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
)"
    ADMIN_PASSWORD="$($VENV_PY - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)"

    cat > "$ENV_FILE" <<EOF_ENV
# SpiderPanel environment
ADMIN_PASSWORD=$ADMIN_PASSWORD
SECRET_KEY=$SECRET_KEY
DATA_DIR=$APP_DIR/data
SPIDER_DATA_DIR=$APP_DIR/data
PORT=8080
RAILWAY_PUBLIC_DOMAIN=
WORKER_SYNC_INTERVAL=3600
MTPROTO_PROXY_BIN=/usr/local/bin/mtproto-proxy
EOF_ENV
    chmod 600 "$ENV_FILE"

    cat > "$APP_DIR/INSTALL-CREDENTIALS.txt" <<EOF_CREDS
SpiderPanel initial admin password:
$ADMIN_PASSWORD

Environment file:
$ENV_FILE

Application directory:
$APP_DIR
EOF_CREDS
    chmod 600 "$APP_DIR/INSTALL-CREDENTIALS.txt"
    ok "Initial admin credentials generated."
else
    chmod 600 "$ENV_FILE"
    ok "Existing environment preserved."
fi

# ------------------------------------------------------------
# Validate application before starting systemd.
# ------------------------------------------------------------
log "Validating SpiderPanel Python source..."
cd "$APP_DIR"
"$VENV_PY" -m py_compile \
    main.py telegram_proxy.py relay_vless.py shared.py pages.py xhttp_siz10.py
ok "Python syntax check passed."

if [[ -f "$APP_DIR/_worker.js" ]]; then
    if command -v node >/dev/null 2>&1; then
        node --check "$APP_DIR/_worker.js"
    fi
fi
if [[ -f "$APP_DIR/worker/_worker.js" && -f "$APP_DIR/worker/_worker.js" ]]; then
    if command -v node >/dev/null 2>&1; then
        node --check "$APP_DIR/worker/_worker.js"
    fi
fi

# ------------------------------------------------------------
# systemd service
# ------------------------------------------------------------
command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required for VPS automatic startup."

log "Creating systemd service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF_SERVICE
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
Environment=PIP_NO_CACHE_DIR=1
Environment=MTPROTO_PROXY_BIN=/usr/local/bin/mtproto-proxy
ExecStart=$APP_DIR/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5
TimeoutStartSec=180
TimeoutStopSec=30
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service" >/dev/null
systemctl restart "$SERVICE_NAME.service"

sleep 4
if systemctl is-active --quiet "$SERVICE_NAME.service"; then
    ok "SpiderPanel service is running."
else
    warn "SpiderPanel failed to start. Showing recent logs:"
    journalctl -u "$SERVICE_NAME.service" -n 100 --no-pager || true
    exit 1
fi

# ------------------------------------------------------------
# Detect reachable addresses
# ------------------------------------------------------------
SERVER_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
LOCAL_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"

printf '\n'
printf '============================================================\n'
printf '              SPIDERPANEL INSTALL COMPLETE\n'
printf '============================================================\n'
printf '\n'
printf 'Application : %s\n' "$APP_DIR"
printf 'Environment : %s\n' "$ENV_FILE"
printf 'Service     : %s.service\n' "$SERVICE_NAME"
printf '\n'
[[ -n "$SERVER_IP" ]] && printf 'Public URL  : http://%s:8080/spider\n' "$SERVER_IP"
[[ -n "$LOCAL_IP" ]] && printf 'Local URL   : http://%s:8080/spider\n' "$LOCAL_IP"
printf '\n'
printf 'Status      : systemctl status %s\n' "$SERVICE_NAME"
printf 'Logs        : journalctl -u %s -f\n' "$SERVICE_NAME"
printf 'Restart     : systemctl restart %s\n' "$SERVICE_NAME"
printf '\n'
if [[ -f "$APP_DIR/INSTALL-CREDENTIALS.txt" ]]; then
    printf 'Admin creds : %s\n' "$APP_DIR/INSTALL-CREDENTIALS.txt"
    printf '\n'
    cat "$APP_DIR/INSTALL-CREDENTIALS.txt"
fi
printf '\n============================================================\n'
