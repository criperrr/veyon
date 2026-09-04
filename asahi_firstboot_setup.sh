#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="/"
WIFI_SSID=""
WIFI_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssid|-s) WIFI_SSID="$2"; shift 2 ;;
        --password|-p) WIFI_PASSWORD="$2"; shift 2 ;;
        --target|-t) TARGET_ROOT="$2"; shift 2 ;;
        *) echo "Uso: $0 --ssid <REDE> --password <SENHA> [--target <DIR>]"; exit 1 ;;
    esac
done

if [ -z "${WIFI_SSID}" ] || [ -z "${WIFI_PASSWORD}" ]; then
    echo "Uso: $0 --ssid <REDE> --password <SENHA> [--target <DIR>]"
    exit 1
fi

[ "$(id -u)" -eq 0 ] || { echo "Execute como root (sudo)"; exit 1; }

NM_DIR="${TARGET_ROOT}/etc/NetworkManager/system-connections"
mkdir -p "${NM_DIR}"
chmod 700 "${NM_DIR}"

NM_FILE="${NM_DIR}/${WIFI_SSID}.nmconnection"
UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)"

cat << NM_EOF > "${NM_FILE}"
[connection]
id=${WIFI_SSID}
uuid=${UUID}
type=wifi
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
NM_EOF
chmod 600 "${NM_FILE}"

BIN_DIR="${TARGET_ROOT}/usr/local/bin"
mkdir -p "${BIN_DIR}"
FIRSTBOOT_SCRIPT="${BIN_DIR}/asahi-firstboot-veyon.sh"

cat << 'SH_EOF' > "${FIRSTBOOT_SCRIPT}"
#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a "/var/log/veyon-firstboot.log") 2>&1

for i in $(seq 1 40); do
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        break
    fi
    sleep 3
done

curl -sSL https://raw.githubusercontent.com/criperrr/veyon/main/build_and_install.sh | bash
rm -f /var/lib/asahi-firstboot-pending
systemctl disable asahi-firstboot-veyon.service 2>/dev/null || true
SH_EOF
chmod 755 "${FIRSTBOOT_SCRIPT}"

SYSTEMD_DIR="${TARGET_ROOT}/etc/systemd/system"
mkdir -p "${SYSTEMD_DIR}"
SERVICE_FILE="${SYSTEMD_DIR}/asahi-firstboot-veyon.service"

cat << 'SRV_EOF' > "${SERVICE_FILE}"
[Unit]
Description=Asahi First Boot Veyon Provisioning
After=network-online.target NetworkManager.service
Wants=network-online.target
ConditionPathExists=/var/lib/asahi-firstboot-pending

[Service]
Type=oneshot
ExecStart=/usr/local/bin/asahi-firstboot-veyon.sh
RemainAfterExit=yes
TimeoutSec=1800
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SRV_EOF
chmod 644 "${SERVICE_FILE}"

mkdir -p "${TARGET_ROOT}/var/lib"
touch "${TARGET_ROOT}/var/lib/asahi-firstboot-pending"

WANTS_DIR="${SYSTEMD_DIR}/multi-user.target.wants"
mkdir -p "${WANTS_DIR}"
ln -sf "/etc/systemd/system/asahi-firstboot-veyon.service" "${WANTS_DIR}/asahi-firstboot-veyon.service"

echo "[OK] Primeiro boot configurado para Wi-Fi '${WIFI_SSID}' em ${TARGET_ROOT}"
