#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apt-get update -qq
apt-get install -y -qq iptables ipset curl tar cron

# Install geoip-shell
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -sSL "https://github.com/friendly-bits/geoip-shell/archive/refs/heads/master.tar.gz" -o "${TMP_DIR}/geoip-shell.tar.gz"
tar -xzf "${TMP_DIR}/geoip-shell.tar.gz" -C "${TMP_DIR}"
INSTALL_DIR="$(find "${TMP_DIR}" -maxdepth 1 -type d -name "geoip-shell*" | head -n 1)"

chmod +x "${INSTALL_DIR}"/*.sh
"${INSTALL_DIR}/geoip-shell-install.sh" -w ipt -z

mkdir -p /etc/geoip-shell
cp "${SCRIPT_DIR}/geoip-shell.conf" /etc/geoip-shell/geoip-shell.conf

# Initial database fetch
/usr/bin/geoip-shell-run.sh update -a

# Cron persistence
CRON_TMP="$(mktemp)"
crontab -l 2>/dev/null | grep -v 'geoip-shell' > "${CRON_TMP}" || true
cat << 'CRON' >> "${CRON_TMP}"
19 4 * * * /usr/bin/geoip-shell-run.sh update -a 1>/dev/null 2>/dev/null # geoip-shell-update
@reboot /usr/bin/geoip-shell-run.sh restore -a 1>/dev/null 2>/dev/null # geoip-shell-persistence
CRON
crontab "${CRON_TMP}"
rm -f "${CRON_TMP}"

echo "Firewall and geoip-shell setup completed"
