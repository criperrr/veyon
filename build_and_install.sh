#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/criperrr/veyon.git"
REPO_BRANCH="main"

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -z "${SCRIPT_SOURCE}" ] || [ "${SCRIPT_SOURCE}" = "bash" ] || [ "${SCRIPT_SOURCE}" = "sh" ] || [ ! -f "${SCRIPT_SOURCE}" ]; then
    CURRENT_DIR="$(pwd)"
else
    CURRENT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
fi

if [ ! -f "${CURRENT_DIR}/CMakeLists.txt" ] || [ ! -f "${CURRENT_DIR}/core/src/VeyonCore.cpp" ]; then
    run_root apt-get update -qq
    run_root apt-get install -y -qq git curl ca-certificates
    WORK_DIR="/opt/veyon-source"
    run_root rm -rf "${WORK_DIR}"
    run_root git clone --depth 1 -b "${REPO_BRANCH}" "${REPO_URL}" "${WORK_DIR}"
    (cd "${WORK_DIR}" && run_root git submodule update --init --recursive)
    exec run_root bash "${WORK_DIR}/build_and_install.sh" "$@"
fi

SCRIPT_DIR="${CURRENT_DIR}"
BUILD_DIR="${SCRIPT_DIR}/build"
JOBS="$(nproc)"
if [ "${JOBS}" -gt 4 ]; then
    JOBS=4
fi

if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -eq 0 ] && [ ! -f /swapfile ]; then
    run_root fallocate -l 4G /swapfile 2>/dev/null || run_root dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null || true
    run_root chmod 600 /swapfile 2>/dev/null || true
    run_root mkswap /swapfile 2>/dev/null || true
    run_root swapon /swapfile 2>/dev/null || true
    if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
        echo "/swapfile none swap sw 0 0" | run_root tee -a /etc/fstab > /dev/null
    fi
fi

run_root apt-get update -qq
run_root apt-get install -y -qq --no-install-recommends \
    build-essential cmake make gcc g++ pkgconf dpkg-dev fakeroot git ca-certificates \
    qt6-base-dev qt6-5compat-dev qt6-l10n-tools qt6-tools-dev qt6-declarative-dev \
    qt6-httpserver-dev qt6-websockets-dev libqca-qt6-dev libqca-qt6-plugins libssl-dev \
    libpam0g-dev libsasl2-dev libldap2-dev libproc2-dev libpipewire-0.3-dev libspa-0.2-dev \
    xorg-dev libxtst-dev libfakekey-dev libvncserver-dev libjpeg-dev zlib1g-dev liblzo2-dev \
    libpng-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    flatpak xdg-desktop-portal xdg-desktop-portal-kde pipewire qml6-module-qtwebsockets polkitd x11vnc

CORE_SERVICE_FILE="${SCRIPT_DIR}/plugins/platform/linux/LinuxServiceCore.cpp"
if grep -q 'if (st.st_mode & (S_IWGRP | S_IWOTH))' "${CORE_SERVICE_FILE}" 2>/dev/null; then
    sed -i 's/if (st.st_mode & (S_IWGRP | S_IWOTH))/if (!S_ISSOCK(st.st_mode) \&\& (st.st_mode \& (S_IWGRP | S_IWOTH)))/' "${CORE_SERVICE_FILE}"
fi

PORTAL_SESSION_FILE="${SCRIPT_DIR}/plugins/vncserver/pipewire/PortalSession.cpp"
if ! grep -q 'QStringLiteral("screencast"), QStringLiteral("")' "${PORTAL_SESSION_FILE}" 2>/dev/null; then
    sed -i '/QStringLiteral("remote-desktop"), appId, QStringLiteral("yes")});/a \
\tQProcess::execute(QStringLiteral("flatpak"),\
\t\t\t\t\t  {QStringLiteral("permission-set"), QStringLiteral("kde-authorized"),\
\t\t\t\t\t   QStringLiteral("screencast"), QStringLiteral(""), QStringLiteral("yes")});\
\tQProcess::execute(QStringLiteral("flatpak"),\
\t\t\t\t\t  {QStringLiteral("permission-set"), QStringLiteral("kde-authorized"),\
\t\t\t\t\t   QStringLiteral("remote-desktop"), QStringLiteral(""), QStringLiteral("yes")});' "${PORTAL_SESSION_FILE}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DWITH_QT6=ON \
      -DWITH_WEBAPI=ON \
      -DWITH_LTO=ON \
      -DWITH_UNITY_BUILD=ON \
      "${SCRIPT_DIR}" > /dev/null

make -j"${JOBS}" > /dev/null

mkdir -p "${BUILD_DIR}/lib/veyon"
find "${BUILD_DIR}/plugins" -name "*.so" -exec ln -sf '{}' "${BUILD_DIR}/lib/veyon/" ';'
run_root make install > /dev/null

echo "/usr/local/lib/veyon" | run_root tee /etc/ld.so.conf.d/veyon.conf > /dev/null
run_root ldconfig

run_root chmod 4755 /usr/local/bin/veyon-input-helper
run_root chmod 4755 /usr/local/bin/veyon-auth-helper

run_root mkdir -p /var/log/veyon
run_root chmod 1777 /var/log/veyon

run_root /usr/local/bin/veyon-cli config set Service/HideTrayIcon true > /dev/null
run_root /usr/local/bin/veyon-cli config set Service/RemoteConnectionNotifications false > /dev/null
run_root /usr/local/bin/veyon-cli config set Service/FailedAuthenticationNotifications false > /dev/null
run_root /usr/local/bin/veyon-cli config set Service/Autostart true > /dev/null
run_root /usr/local/bin/veyon-cli config set Service/ActiveSession false > /dev/null
run_root /usr/local/bin/veyon-cli config set Service/MultiSession true > /dev/null
run_root /usr/local/bin/veyon-cli config set Authentication/Method 1 > /dev/null
run_root /usr/local/bin/veyon-cli config set AccessControl/AccessRestrictedToUserGroups false > /dev/null
run_root /usr/local/bin/veyon-cli config set AccessControl/AccessControlRulesProcessingEnabled false > /dev/null
run_root /usr/local/bin/veyon-cli config set Logging/LogToSystem true > /dev/null
run_root /usr/local/bin/veyon-cli config set Logging/LogFileDirectory /var/log/veyon > /dev/null
run_root /usr/local/bin/veyon-cli config set Master/ComputerMonitoringImageQuality 2 > /dev/null
run_root /usr/local/bin/veyon-cli config set Master/RemoteAccessImageQuality 2 > /dev/null
run_root /usr/local/bin/veyon-cli config set VncConnection/FastFramebufferUpdateInterval 100 > /dev/null

KEY_PUBLIC_DIR="/etc/veyon/keys/public/teacher"
KEY_PRIVATE_DIR="/etc/veyon/keys/private/teacher"
BUNDLED_PUB_KEY="${SCRIPT_DIR}/keys/teacher_public.key"

run_root mkdir -p "${KEY_PUBLIC_DIR}"
if [ ! -f "${KEY_PUBLIC_DIR}/key" ]; then
    if [ -f "${BUNDLED_PUB_KEY}" ]; then
        run_root cp "${BUNDLED_PUB_KEY}" "${KEY_PUBLIC_DIR}/key"
    else
        run_root /usr/local/bin/veyon-cli authkeys create teacher > /dev/null
    fi
fi

run_root chmod 755 /etc/veyon /etc/veyon/keys /etc/veyon/keys/public "${KEY_PUBLIC_DIR}"
run_root chmod 644 "${KEY_PUBLIC_DIR}/key"

if [ -d "/etc/veyon/keys/private" ]; then
    run_root chgrp -R sudo /etc/veyon/keys/private 2>/dev/null || true
    run_root chmod 750 /etc/veyon/keys/private
    run_root /usr/local/bin/veyon-cli authkeys setaccessgroup teacher/private sudo 2>/dev/null || true
fi

run_root tee /usr/local/bin/veyon-plasma-preauth.sh > /dev/null << 'PREAUTH_EOF'
#!/bin/sh
APP_ID="io.veyon.veyon-server"
if command -v flatpak >/dev/null 2>&1; then
    flatpak permission-set kde-authorized screencast "${APP_ID}" yes 2>/dev/null || true
    flatpak permission-set kde-authorized remote-desktop "${APP_ID}" yes 2>/dev/null || true
    flatpak permission-set kde-authorized screencast "" yes 2>/dev/null || true
    flatpak permission-set kde-authorized remote-desktop "" yes 2>/dev/null || true
fi
if command -v dbus-send >/dev/null 2>&1 && [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    for target in "${APP_ID}" ""; do
        dbus-send --session --dest=org.freedesktop.impl.portal.PermissionStore /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore.SetPermission string:kde-authorized boolean:false string:screencast string:"${target}" array:string:yes 2>/dev/null || true
        dbus-send --session --dest=org.freedesktop.impl.portal.PermissionStore /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore.SetPermission string:kde-authorized boolean:false string:remote-desktop string:"${target}" array:string:yes 2>/dev/null || true
    done
fi
PREAUTH_EOF
run_root chmod 755 /usr/local/bin/veyon-plasma-preauth.sh

run_root mkdir -p /etc/xdg/autostart
run_root tee /etc/xdg/autostart/veyon-plasma-preauth.desktop > /dev/null << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Veyon KDE Pre-authorization
Exec=/usr/local/bin/veyon-plasma-preauth.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-KDE-autostart-phase=1
AUTOSTART_EOF
run_root chmod 644 /etc/xdg/autostart/veyon-plasma-preauth.desktop

run_root mkdir -p /etc/xdg
if [ -f /etc/xdg/plasmanotifyrc ]; then
    grep -q "\[Applications\]\[krfb\]" /etc/xdg/plasmanotifyrc 2>/dev/null || run_root tee -a /etc/xdg/plasmanotifyrc > /dev/null << 'NOTIFY_EOF'

[Applications][krfb]
ShowBadges=false
ShowInHistory=false
ShowPopups=false

[Applications][org.freedesktop.impl.portal.desktop.kde]
ShowBadges=false
ShowInHistory=false
ShowPopups=false

[Applications][io.veyon.veyon-server]
ShowBadges=false
ShowInHistory=false
ShowPopups=false
NOTIFY_EOF
else
    run_root tee /etc/xdg/plasmanotifyrc > /dev/null << 'NOTIFY_EOF'
[Applications][krfb]
ShowBadges=false
ShowInHistory=false
ShowPopups=false

[Applications][org.freedesktop.impl.portal.desktop.kde]
ShowBadges=false
ShowInHistory=false
ShowPopups=false

[Applications][io.veyon.veyon-server]
ShowBadges=false
ShowInHistory=false
ShowPopups=false
NOTIFY_EOF
fi

run_root mkdir -p /etc/skel/.local/share/flatpak/db
if [ -d "${HOME}/.local/share/flatpak/db" ]; then
    run_root cp -p "${HOME}/.local/share/flatpak/db/"* /etc/skel/.local/share/flatpak/db/ 2>/dev/null || true
fi
run_root chmod -R 755 /etc/skel/.local
run_root chmod 644 /etc/skel/.local/share/flatpak/db/* 2>/dev/null || true

for user_home in /home/*; do
    if [ -d "${user_home}" ] && [ "$(basename "${user_home}")" != "lost+found" ]; then
        user_name="$(basename "${user_home}")"
        user_db="${user_home}/.local/share/flatpak/db"
        run_root mkdir -p "${user_db}"
        if [ -d "/etc/skel/.local/share/flatpak/db" ]; then
            run_root cp -p "/etc/skel/.local/share/flatpak/db/"* "${user_db}/" 2>/dev/null || true
            run_root chown -R "${user_name}:" "${user_home}/.local" 2>/dev/null || true
        fi
        run_root usermod -a -G input "${user_name}" 2>/dev/null || true
    fi
done

run_root tee /usr/local/bin/veyon-pam-session.sh > /dev/null << 'PAM_EOF'
#!/bin/sh
[ "$PAM_TYPE" = "open_session" ] || exit 0
[ -n "$PAM_USER" ] || exit 0
USER_UID=$(id -u "$PAM_USER" 2>/dev/null) || exit 0
[ "$USER_UID" -ge 1000 ] || exit 0
USER_HOME=$(getent passwd "$PAM_USER" | cut -d: -f6)
[ -n "$USER_HOME" ] || exit 0

mkdir -p /run/veyon
chmod 0755 /run/veyon
usermod -a -G input "$PAM_USER" 2>/dev/null || true

USER_DB="${USER_HOME}/.local/share/flatpak/db"
if [ -d "/etc/skel/.local/share/flatpak/db" ]; then
    mkdir -p "${USER_DB}"
    cp -n /etc/skel/.local/share/flatpak/db/* "${USER_DB}/" 2>/dev/null || true
    chown -R "${USER_UID}:$(id -g "$PAM_USER")" "${USER_HOME}/.local" 2>/dev/null || true
fi
PAM_EOF
run_root chmod 755 /usr/local/bin/veyon-pam-session.sh

run_root tee /usr/share/pam-configs/veyon-session > /dev/null << 'PAMCONF_EOF'
Name: Veyon session environment initialization
Default: yes
Priority: 0
Session-Type: Additional
Session:
	optional	pam_exec.so quiet /usr/local/bin/veyon-pam-session.sh
PAMCONF_EOF

run_root pam-auth-update --enable veyon-session --package > /dev/null

run_root tee /etc/udev/rules.d/99-veyon-input.rules > /dev/null << 'UDEV_EOF'
KERNEL=="uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", KERNEL=="event*", MODE="0660", GROUP="input"
UDEV_EOF
run_root udevadm control --reload-rules 2>/dev/null || true
run_root udevadm trigger 2>/dev/null || true

run_root tee /etc/polkit-1/rules.d/50-veyon.rules > /dev/null << 'POLKIT_EOF'
polkit.addRule(function(action, subject) {
    if (action.id === "io.veyon.veyon-configurator") {
        return subject.isInGroup("sudo") ? polkit.Result.YES : polkit.Result.NO;
    }
    if (action.id === "org.freedesktop.systemd1.manage-units" &&
        (action.lookup("unit") === "veyon.service" || action.lookup("unit") === "veyon")) {
        return subject.isInGroup("sudo") ? polkit.Result.YES : polkit.Result.NO;
    }
});
POLKIT_EOF
run_root chmod 644 /etc/polkit-1/rules.d/50-veyon.rules

run_root tee /etc/systemd/system/veyon.service > /dev/null << 'SERVICE_EOF'
[Unit]
Description=Veyon Service
After=network-online.target dbus.service systemd-logind.service
Wants=network-online.target
Requires=dbus.service systemd-logind.service
Documentation=man:veyon-service(1)
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
ExecStart=/usr/local/bin/veyon-service
Type=simple
Restart=always
RestartSec=3s
Nice=-10
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
SERVICE_EOF

run_root systemctl daemon-reload
run_root systemctl enable veyon.service > /dev/null 2>&1
run_root systemctl restart veyon.service

echo "[OK] Veyon instalado e configurado com sucesso."
