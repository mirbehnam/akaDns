#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run this script as root (sudo)." >&2
  exit 1
fi

restore_resolv_conf() {
  if [[ -f /etc/resolv.conf.bak ]]; then
    cp /etc/resolv.conf.bak /etc/resolv.conf
    echo "Restored /etc/resolv.conf from backup."
  else
    echo "No /etc/resolv.conf backup found; skipping file restore."
  fi
}

interfaces=(
  $(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$' || true)
)

if command -v resolvectl >/dev/null 2>&1; then
  if [[ ${#interfaces[@]} -eq 0 ]]; then
    echo "No active network interfaces found." >&2
    exit 1
  fi
  for iface in "${interfaces[@]}"; do
    if resolvectl --help 2>/dev/null | grep -q "revert"; then
      resolvectl revert "$iface" || true
    else
      resolvectl dns "$iface" "" || true
      resolvectl domain "$iface" "" || true
    fi
  done
else
  restore_resolv_conf
fi

if command -v systemd-resolve >/dev/null 2>&1; then
  systemd-resolve --flush-caches || true
fi

if command -v resolvectl >/dev/null 2>&1; then
  resolvectl flush-caches || true
fi

echo "DNS settings have been restored to default configuration!"
