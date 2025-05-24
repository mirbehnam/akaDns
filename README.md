# Cross-Platform DNS Setter

This script allows users to set custom DNS servers and flush the DNS cache on Windows, Linux, and macOS. It also includes a feature to save the original DNS settings and restore them later.

## Features

*   Sets custom DNS servers from a configuration file.
*   Flushes the system's DNS cache after applying settings.
*   Saves original DNS settings before making changes.
*   Restores original DNS settings from a backup file.
*   Cross-platform support for Windows, Linux, and macOS.
*   Attempts multiple methods for DNS configuration on Linux for broader compatibility.
*   Includes privilege checking to ensure it can make necessary changes.

## Requirements

*   Python 3.x
*   Administrator/root privileges are required to run the script and modify network settings.

## Configuration (`dnsConf.txt`)

The script reads the DNS servers to be set from a file named `dnsConf.txt` located in the same directory as the script.

*   **Format:** Each line should be in the format `Name=IPAddress`.
    *   `Name` can be any descriptive name (e.g., `GoogleDNS1`, `CloudflarePrimary`).
    *   `IPAddress` must be a valid IPv4 address.
*   The script will use the **first three valid IP addresses** it finds in this file.
*   Lines starting with `#` and empty lines are ignored as comments.

**Example `dnsConf.txt`:**

```
# Primary DNS Servers
MyPrimaryDNS=8.8.8.8
MySecondaryDNS=8.8.4.4

# Optional Third DNS
CloudflareDNS=1.1.1.1

# These will be ignored if the above three are valid
OpenDNS1=208.67.222.222
OpenDNS2=208.67.220.220
```

## Usage

**Important:** This script modifies network settings. Ensure you understand its function before running.

1.  **Prepare `dnsConf.txt`:** Create or edit the `dnsConf.txt` file in the same directory as the script with your desired DNS servers.
2.  **Run the script:**

    *   **To Set New DNS Servers:**
        *   **Windows:** Open Command Prompt or PowerShell as Administrator and run:
            ```bash
            python set_dns_crossplatform.py
            ```
        *   **Linux/macOS:** Open a terminal and run with `sudo`:
            ```bash
            sudo python3 set_dns_crossplatform.py
            ```
        This will:
        1.  Save your current DNS settings to `original_dns_config.json`.
        2.  Set the new DNS servers from `dnsConf.txt`.
        3.  Flush the DNS cache.

    *   **To Restore Original DNS Servers:**
        *   **Windows:** Open Command Prompt or PowerShell as Administrator and run:
            ```bash
            python set_dns_crossplatform.py --restore
            ```
        *   **Linux/macOS:** Open a terminal and run with `sudo`:
            ```bash
            sudo python3 set_dns_crossplatform.py --restore
            ```
        This will:
        1.  Read settings from `original_dns_config.json`.
        2.  Attempt to revert DNS settings to their original state.
        3.  Flush the DNS cache.
        4.  Delete `original_dns_config.json` if restoration is successful.

## Supported Operating Systems

*   **Windows:** Tested on Windows 10/11. Uses `netsh.exe` for setting DNS and `ipconfig.exe` for flushing.
*   **Linux:** Attempts DNS configuration using:
    1.  `nmcli` (NetworkManager command-line tool)
    2.  `resolvectl` (systemd-resolved command-line tool)
    3.  Direct modification of `/etc/resolv.conf` (as a last resort, with safety checks and warnings).
    Cache flushing is attempted via `resolvectl`, `nscd`, or `dnsmasq`.
*   **macOS:** Uses `networksetup` for DNS configuration and `dscacheutil`/`killall -HUP mDNSResponder` for cache flushing.

## How it Works (Briefly)

1.  **OS Detection:** Determines if the script is running on Windows, Linux, or macOS.
2.  **Privilege Checking:** Verifies if the script has administrator/root privileges; exits if not.
3.  **Setting DNS (`python set_dns_crossplatform.py`):**
    *   Retrieves and saves current DNS settings for active interfaces/services to `original_dns_config.json`.
    *   Parses `dnsConf.txt` for the new DNS server IPs.
    *   Calls OS-specific functions to apply the new DNS settings using system commands (e.g., `netsh`, `nmcli`, `resolvectl`, `networksetup`).
    *   Flushes the DNS cache.
4.  **Restoring DNS (`python set_dns_crossplatform.py --restore`):**
    *   Loads DNS settings from `original_dns_config.json`.
    *   Calls OS-specific functions to revert DNS configurations (e.g., setting interfaces to DHCP or re-applying saved static IPs).
    *   Flushes the DNS cache.
    *   Removes `original_dns_config.json` upon successful restoration.

## Important Notes/Limitations

*   **Requires elevated privileges:** The script must be run as an Administrator (Windows) or with `sudo` (Linux/macOS) to function.
*   **Linux DNS Complexity:** DNS management on Linux can vary significantly between distributions and configurations. The script tries common, modern methods first (`nmcli`, `systemd-resolve`). Direct modification of `/etc/resolv.conf` is a fallback and might be temporary, as network management services often overwrite this file. Always verify your system's specific network configuration method.
*   **Interface Detection:** The script attempts to find and configure all active network interfaces (Windows/Linux) or services (macOS). Behavior might vary based on specific OS configurations and how network interfaces are managed.
*   **Manual Reversion:** Always ensure you have a way to manually revert DNS settings if needed, especially during initial use or if encountering issues. This could involve noting down your original settings or understanding your OS's network configuration GUI/tools.
*   **Error Handling:** While the script includes error handling, specific system configurations might lead to unexpected outcomes. Review the script's output for any error messages.
