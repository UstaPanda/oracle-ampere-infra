#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root" >&2
    exit 1
fi

cat << 'SYSCTL' > /etc/sysctl.d/99-game-server.conf
# Docker bridge forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# BBR and FQ pacing
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Dirty page writeback
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
SYSCTL

sysctl --system >/dev/null 2>&1

echo "System tuning applied"
