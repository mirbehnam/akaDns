#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Please run this script as root (sudo)." >&2
  exit 1
fi

while true; do
  clear
  echo "=========================================================="
  echo "                 aka_techno (Linux)"
  echo "=========================================================="
  echo " Follow my YouTube channel: https://www.youtube.com/@aka_techno"
  echo " By : Behnam Tajadini"
  echo "=========================================================="
  echo
  echo "DNS Configuration Tool"
  echo "===================="
  echo "1. Set Custom DNS Servers"
  echo "2. Verify DNS Settings"
  echo "3. Restore Default Settings"
  echo "4. Test DNS Servers with URL"
  echo "5. Open DNS Configuration GUI"
  echo "6. Exit"
  echo

  read -r -p "Enter your choice (1-6): " choice

  case "$choice" in
    1)
      bash "$(dirname "$0")/set-dns-servers.sh"
      read -r -p "Press Enter to continue..." _
      ;;
    2)
      bash "$(dirname "$0")/verify-dns.sh"
      read -r -p "Press Enter to continue..." _
      ;;
    3)
      bash "$(dirname "$0")/restore-dns-settings.sh"
      read -r -p "Press Enter to continue..." _
      ;;
    4)
      bash "$(dirname "$0")/test-dns-servers.sh"
      read -r -p "Press Enter to continue..." _
      ;;
    5)
      bash "$(dirname "$0")/start-dns-gui.sh"
      ;;
    6)
      exit 0
      ;;
    *)
      echo "Invalid choice."
      sleep 1
      ;;
  esac
 done
