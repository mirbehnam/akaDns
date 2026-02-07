#!/usr/bin/env bash
set -euo pipefail

if command -v resolvectl >/dev/null 2>&1; then
  echo "Current DNS Settings (resolvectl):"
  resolvectl status
else
  echo "Current DNS Settings (/etc/resolv.conf):"
  cat /etc/resolv.conf
fi

echo
if command -v getent >/dev/null 2>&1; then
  echo "Testing DNS Resolution for www.google.com:"
  getent hosts www.google.com || true
fi

if command -v ip >/dev/null 2>&1; then
  echo
  echo "Network Interfaces:"
  ip -brief addr
fi
