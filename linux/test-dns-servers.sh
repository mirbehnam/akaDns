#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
config_path="$script_dir/dnsConf.txt"

if [[ ! -f "$config_path" ]]; then
  echo "Configuration file not found: $config_path" >&2
  exit 1
fi

declare -a dns_pairs
mapfile -t dns_pairs < <(
  awk -F= '
  {
    name=$1; ip=$2;
    gsub(/[[:space:]]+/, "", name);
    gsub(/[[:space:]]+/, "", ip);
    base=name;
    sub(/[0-9]+$/, "", base);
    if (!(base in seen)) { seen[base]=1; order[++n]=base; }
    count[base]++;
    ips[base,count[base]]=ip;
  }
  END {
    for (i=1;i<=n;i++) {
      b=order[i];
      if (count[b] >= 2) {
        printf "%s|%s|%s\n", b, ips[b,1], ips[b,2];
      }
    }
  }' "$config_path"
)

if [[ ${#dns_pairs[@]} -eq 0 ]]; then
  echo "No DNS pairs found in configuration file." >&2
  exit 1
fi

domains=(
  "developer.google.com"
  "chatgpt.com"
  "gemini.google.com"
  "aistudio.google.com"
)

echo "Select a domain to test:"
for i in "${!domains[@]}"; do
  echo "$((i + 1)). ${domains[$i]}"
 done

all_option=$(( ${#domains[@]} + 1 ))
custom_option=$(( ${#domains[@]} + 2 ))

echo "${all_option}. Test all listed domains"
echo "${custom_option}. Or enter yourself"

read -r -p "Enter your choice: " domain_choice
if ! [[ "$domain_choice" =~ ^[0-9]+$ ]]; then
  echo "Invalid selection." >&2
  exit 1
fi

selected_domains=()
if (( domain_choice >= 1 && domain_choice <= ${#domains[@]} )); then
  selected_domains=("${domains[$((domain_choice - 1))]}")
elif (( domain_choice == all_option )); then
  selected_domains=("${domains[@]}")
elif (( domain_choice == custom_option )); then
  read -r -p "Enter a URL or domain: " input_url
  if [[ -z "${input_url// }" ]]; then
    echo "No input provided." >&2
    exit 1
  fi
  if [[ "$input_url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]; then
    host=$(printf '%s' "$input_url" | awk -F/ '{print $3}')
    selected_domains=("$host")
  else
    selected_domains=("$input_url")
  fi
else
  echo "Selection out of range." >&2
  exit 1
fi

echo
 echo "Test scope:"
 echo "1. Test current DNS settings"
 echo "2. Test all DNS pairs from dnsConf.txt"
read -r -p "Enter your choice: " scope_choice
if ! [[ "$scope_choice" =~ ^[0-9]+$ ]]; then
  echo "Invalid selection." >&2
  exit 1
fi

if (( scope_choice == 1 )); then
  for domain in "${selected_domains[@]}"; do
    echo
    echo "Resolving DNS for: $domain (system DNS)"
    if command -v getent >/dev/null 2>&1; then
      if getent hosts "$domain"; then
        echo "Success"
      else
        echo "DNS resolution failed for $domain"
      fi
    else
      echo "getent not available to test system DNS." >&2
    fi
  done
elif (( scope_choice == 2 )); then
  if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
    echo "dig or nslookup is required to test custom DNS servers." >&2
    exit 1
  fi

  for pair in "${dns_pairs[@]}"; do
    IFS='|' read -r name server1 server2 <<< "$pair"
    for domain in "${selected_domains[@]}"; do
      echo
      echo "Resolving DNS for: $domain ($name: $server1, $server2)"
      if command -v dig >/dev/null 2>&1; then
        if dig +time=2 +tries=1 "@$server1" "$domain" | grep -q "ANSWER SECTION"; then
          echo "Success via $server1"
        elif dig +time=2 +tries=1 "@$server2" "$domain" | grep -q "ANSWER SECTION"; then
          echo "Success via $server2"
        else
          echo "DNS resolution failed for $domain"
        fi
      else
        if nslookup "$domain" "$server1" >/dev/null 2>&1; then
          echo "Success via $server1"
        elif nslookup "$domain" "$server2" >/dev/null 2>&1; then
          echo "Success via $server2"
        else
          echo "DNS resolution failed for $domain"
        fi
      fi
    done
  done
else
  echo "Selection out of range." >&2
  exit 1
fi
