#!/usr/bin/env bash
# ==============================================================================
# Script de Preparação do Primeiro Boot para MacBooks Apple Silicon (Asahi Linux)
# ==============================================================================
# Este script prepara uma imagem ou sistema Asahi para:
#  1. Conectar automaticamente a uma rede Wi-Fi específica no primeiro boot
#  2. Executar o provisionamento completo e silencioso do Veyon de forma autônoma
#  3. Desativar a si próprio após a conclusão com sucesso
#
# Uso:
#   sudo ./asahi_firstboot_setup.sh --ssid "NomeDaRede" --password "SenhaDaRede" [--target /mnt]
# ==============================================================================

set -euo pipefail

TARGET_ROOT="/"
WIFI_SSID=""
WIFI_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssid|-s)
            WIFI_SSID="$2"
            shift 2
            ;;
        --password|-p)
            WIFI_PASSWORD="$2"
            shift 2
            ;;
        --target|-t)
            TARGET_ROOT="$2"
            shift 2
            ;;
        *)
            echo "Opção desconhecida: $1"
            echo "Uso: $0 --ssid <NOME_DA_REDE> --password <SENHA> [--target <DIRETORIO_RAIZ>]"
            exit 1
            ;;
    esac
done

if [ -z "${WIFI_SSID}" ] || [ -z "${WIFI_PASSWORD}" ]; then
    echo "Erro: SSID e senha do Wi-Fi são obrigatórios."
    echo "Uso: $0 --ssid \"NomeDaRede\" --password \"SenhaDaRede\" [--target /mnt]"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Erro: Este script deve ser executado como root (sudo)."
    exit 1
fi

echo "======================================================================"
echo "    Configurando Primeiro Boot Autônomo para Asahi Linux"
echo "======================================================================"
echo "Diretório Alvo : ${TARGET_ROOT}"
echo "Rede Wi-Fi     : ${WIFI_SSID}"
echo "======================================================================"

# 1. Configurar NetworkManager para conectar automaticamente ao Wi-Fi
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
echo "-> Conexão Wi-Fi configurada em: ${NM_FILE}"

# 2. Criar script de provisionamento no primeiro boot
BIN_DIR="${TARGET_ROOT}/usr/local/bin"
mkdir -p "${BIN_DIR}"

FIRSTBOOT_SCRIPT="${BIN_DIR}/asahi-firstboot-veyon.sh"
cat << 'SH_EOF' > "${FIRSTBOOT_SCRIPT}"
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/veyon-firstboot.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando Primeiro Boot Veyon Kiosk"
echo "======================================================================"

# Aguarda conectividade com a internet através da rede configurada
echo "-> Aguardando conexão ativa com a internet..."
ONLINE=0
for i in $(seq 1 40); do
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        echo "   [OK] Conexão com a internet estabelecida!"
        ONLINE=1
        break
    fi
    sleep 3
done

if [ "$ONLINE" -ne 1 ]; then
    echo "   [AVISO] Não foi possível conectar ao GitHub após 120s. Verifique o Wi-Fi."
    exit 1
fi

echo "-> Baixando e executando script de padronização do Veyon..."
curl -sSL https://raw.githubusercontent.com/criperrr/veyon/main/build_and_install.sh | bash

# Finalização: remove a flag de pendência e desativa o serviço de primeiro boot
echo "-> Finalizando primeiro boot..."
rm -f /var/lib/asahi-firstboot-pending
systemctl disable asahi-firstboot-veyon.service 2>/dev/null || true

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Provisionamento concluído com sucesso!"
SH_EOF

chmod 755 "${FIRSTBOOT_SCRIPT}"
echo "-> Script de primeiro boot criado em: ${FIRSTBOOT_SCRIPT}"

# 3. Criar serviço systemd do primeiro boot
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
echo "-> Unidade systemd criada em: ${SERVICE_FILE}"

# 4. Habilitar o serviço e criar o marcador de pendência
VAR_LIB="${TARGET_ROOT}/var/lib"
mkdir -p "${VAR_LIB}"
touch "${VAR_LIB}/asahi-firstboot-pending"

WANTS_DIR="${SYSTEMD_DIR}/multi-user.target.wants"
mkdir -p "${WANTS_DIR}"
ln -sf "/etc/systemd/system/asahi-firstboot-veyon.service" "${WANTS_DIR}/asahi-firstboot-veyon.service"

echo "-> Marcador criado: ${VAR_LIB}/asahi-firstboot-pending"
echo "-> Serviço ativado no multi-user.target"
echo ""
echo "======================================================================"
echo "    PRONTO PARA O PRIMEIRO BOOT!"
echo "======================================================================"
echo "Ao ligar o MacBook pela primeira vez:"
echo " 1. O NetworkManager conectará automaticamente ao Wi-Fi '${WIFI_SSID}'."
echo " 2. O systemd executará o provisionamento completo do Veyon via curl | bash."
echo " 3. A tela, o teclado e o touchpad estarão prontos para controle remoto."
echo "======================================================================"
