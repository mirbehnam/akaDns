import platform
import os
import re
import subprocess
import ctypes # For Windows privilege check
import sys # For sys.exit()
import json # For saving/loading original DNS settings
import argparse # For command-line arguments

# --- Constants ---
ORIGINAL_DNS_CONFIG_FILE = "original_dns_config.json"

def get_os(test_platform_system=None):
    """
    Detects the current operating system.
    An optional 'test_platform_system' argument can be provided for testing purposes.

    Args:
        test_platform_system (str, optional): A string to override platform.system().
                                            Defaults to None.

    Returns:
        str: "windows", "linux", "macos", or "unknown".
    """
    system_to_check = test_platform_system if test_platform_system is not None else platform.system()
    system_lower = system_to_check.lower()

    if "windows" in system_lower:
        return "windows"
    elif "linux" in system_lower:
        return "linux"
    elif "darwin" in system: # darwin is the system name for macOS
        return "macos"
    else:
        return "unknown"

def is_valid_ip(ip):
    """
    Validates an IPv4 address.

    Args:
        ip (str): The IP address string to validate.

    Returns:
        bool: True if valid IPv4, False otherwise.
    """
    # Regex for IPv4 address
    pattern = re.compile(r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")
    if pattern.match(ip):
        parts = ip.split(".")
        for part in parts:
            if not 0 <= int(part) <= 255:
                return False
        return True
    return False

def parse_dns_config(filepath="dnsConf.txt"):
    """
    Parses a DNS configuration file (e.g., "dnsConf.txt").
    Expected format in the file is: Name=IPAddress (e.g., GoogleDNS1=8.8.8.8)
    Lines starting with '#' or empty lines are ignored.

    Args:
        filepath (str, optional): The path to the DNS configuration file.
                                  Defaults to "dnsConf.txt".

    Returns:
        list[str] or None: A list of up to 3 valid IP addresses found in the file.
                           Returns None if the file is not found, empty, or no valid
                           IP addresses are found, or if an error occurs.
    """
    dns_servers = []
    if not os.path.exists(filepath):
        print(f"Error: Configuration file '{filepath}' not found.")
        return None
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()

        if not lines:
            print(f"Error: Configuration file '{filepath}' is empty.")
            return None

        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'): # Skip empty lines and comments
                continue
            
            if '=' in line:
                _, ip_address = line.split('=', 1)
                ip_address = ip_address.strip()
                if is_valid_ip(ip_address):
                    if len(dns_servers) < 3:
                        dns_servers.append(ip_address)
                    else:
                        break # Stop after finding 3 valid IPs
                else:
                    print(f"Warning: Invalid IP address format found: {ip_address}")
            else:
                print(f"Warning: Malformed line in config (missing '='): {line}")
        
        if not dns_servers:
            print("No valid DNS server IP addresses found in the configuration file.")
            return None
            
        return dns_servers
    except Exception as e:
        print(f"Error reading or parsing configuration file '{filepath}': {e}")
        return None

# --- OS-Specific DNS Setting Functions ---

def set_dns_windows(dns_servers):
    """
    Sets DNS servers for Windows.
    It finds active network interfaces and applies the DNS settings to them.

    Args:
        dns_servers (list[str]): A list of DNS server IP addresses.

    Returns:
        bool: True if DNS was successfully set for at least one interface, False otherwise.
    """
    print(f"Attempting to set DNS for Windows with servers: {dns_servers}")
    if not dns_servers:
        print("No DNS servers provided.")
        return False # Indicate failure: no servers
    
    overall_success = False # Track if at least one interface was configured

    try:
        # Get interface details using netsh
        result = subprocess.run(["netsh", "interface", "show", "interface"], capture_output=True, text=True, check=True, shell=True)
        interfaces_output = result.stdout

        active_interfaces = []
        # Typical output lines:
        # Admin State    State          Type             Interface Name
        # -------------------------------------------------------------------------
        # Enabled        Connected      Dedicated        Ethernet
        # Enabled        Disconnected   Dedicated        Wi-Fi
        lines = interfaces_output.strip().split('\n')
        if len(lines) > 2: # Header, separator, then data
            for line in lines[2:]:
                parts = line.split()
                # A simple heuristic: if it has at least 4 parts, and state is "Connected" and admin state is "Enabled"
                # A more robust parsing might be needed if interface names have spaces, but netsh output is tricky.
                # For simplicity, we assume interface names are single words or the parsing handles it.
                # `netsh interface ip show config name="Interface Name"` is more reliable for checking if it's truly active.
                # However, `show interface` is a good first pass.
                if len(parts) >= 4 and parts[0] == "Enabled" and parts[1] == "Connected":
                    # The interface name is usually the last part, or multiple parts if it contains spaces.
                    # netsh output for interface names can be inconsistent.
                    # We'll try to join all parts from the 4th element onwards as the name.
                    interface_name = " ".join(parts[3:])
                    if interface_name:
                         active_interfaces.append(interface_name)
        
        if not active_interfaces:
            print("No active (Enabled and Connected) network interfaces found.")
            return False # Indicate failure: no interfaces

        print(f"Found active interfaces: {active_interfaces}")

        for interface_name in active_interfaces:
            print(f"\nConfiguring interface: '{interface_name}'")
            
            # Set primary DNS server
            cmd_set = ["netsh", "interface", "ipv4", "set", "dnsserver", f"name=\"{interface_name}\"", "static", f"addr=\"{dns_servers[0]}\"", "validate=no"]
            print(f"Executing: {' '.join(cmd_set)}")
            try:
                set_result = subprocess.run(cmd_set, capture_output=True, text=True, check=True, shell=True)
                print(f"Successfully set primary DNS for '{interface_name}': {dns_servers[0]}")
                if set_result.stdout: print(f"Output: {set_result.stdout.strip()}")
                if set_result.stderr: print(f"Stderr: {set_result.stderr.strip()}")

                # Add secondary and tertiary DNS servers if provided
                for i, dns_server_ip in enumerate(dns_servers[1:], start=1): # start=1 for index (2nd DNS is index 2)
                    cmd_add = ["netsh", "interface", "ipv4", "add", "dnsserver", f"name=\"{interface_name}\"", f"addr=\"{dns_server_ip}\"", f"index={i+1}", "validate=no"]
                    print(f"Executing: {' '.join(cmd_add)}")
                    try:
                        add_result = subprocess.run(cmd_add, capture_output=True, text=True, check=True, shell=True)
                        print(f"Successfully added DNS server {dns_server_ip} (index {i+1}) for '{interface_name}'")
                        if add_result.stdout: print(f"Output: {add_result.stdout.strip()}")
                        if add_result.stderr: print(f"Stderr: {add_result.stderr.strip()}")
                    except subprocess.CalledProcessError as e:
                        print(f"Error adding DNS server {dns_server_ip} for '{interface_name}': {e}")
                        print(f"Stderr: {e.stderr.strip() if hasattr(e, 'stderr') and e.stderr else 'N/A'}")
                    except FileNotFoundError:
                        print("Error: 'netsh' command not found. Ensure it's in your system PATH.")
                        return False # Stop further processing if netsh is missing
                    except Exception as e:
                        print(f"An unexpected error occurred while adding DNS for '{interface_name}': {e}")
                overall_success = True # At least one primary DNS set successfully
            
            except subprocess.CalledProcessError as e:
                print(f"Error setting primary DNS for '{interface_name}': {e}")
                print(f"Command: {' '.join(e.cmd)}")
                print(f"Return code: {e.returncode}")
                print(f"Stderr: {e.stderr.strip() if hasattr(e, 'stderr') and e.stderr else 'N/A'}")
                print(f"Stdout: {e.stdout.strip() if hasattr(e, 'stdout') and e.stdout else 'N/A'}")
                print("Please ensure the script is run with administrator privileges and the interface name is correct.")
            except FileNotFoundError:
                print("Error: 'netsh' command not found. Ensure it's in your system PATH.")
                return False # Stop further processing if netsh is missing
            except Exception as e:
                print(f"An unexpected error occurred while setting primary DNS for '{interface_name}': {e}")
        
        return overall_success

    except subprocess.CalledProcessError as e:
        print(f"Error getting network interfaces: {e}")
        print(f"Stderr: {e.stderr.strip() if hasattr(e, 'stderr') and e.stderr else 'N/A'}")
        return False
    except FileNotFoundError:
        print("Error: 'netsh' command not found. Ensure it's in your system PATH.")
        return False
    except Exception as e:
        print(f"An unexpected error occurred while getting interfaces: {e}")
        return False

def flush_dns_windows():
    """
    Flushes the DNS cache on Windows using 'ipconfig /flushdns'.

    Returns:
        bool: True if successful, False otherwise.
    """
    print("Attempting to flush DNS cache for Windows...")
    try:
        # Changed to shell=False for ipconfig as it's a simple command
        result = subprocess.run(["ipconfig", "/flushdns"], capture_output=True, text=True, check=True)
        print("Successfully flushed DNS cache.")
        if result.stdout:
            print(f"Output: {result.stdout.strip()}")
        if result.stderr: # Should be empty on success typically
            print(f"Stderr: {result.stderr.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error flushing DNS cache: {e}")
        print(f"Command: {' '.join(e.cmd)}")
        print(f"Return code: {e.returncode}")
        print(f"Stderr: {e.stderr.strip() if hasattr(e, 'stderr') and e.stderr else 'N/A'}")
        print(f"Stdout: {e.stdout.strip() if hasattr(e, 'stdout') and e.stdout else 'N/A'}")
        print("Please ensure the script is run with administrator privileges.")
        return False
    except FileNotFoundError:
        print("Error: 'ipconfig' command not found. Ensure it's in your system PATH.")
        return False
    except Exception as e:
        print(f"An unexpected error occurred during DNS flush: {e}")
        return False

# --- Helper Functions for Linux ---

def is_command_available(command):
    """
    Checks if a command is available in the system's PATH.
    Tries common flags like --version or --help to verify executability.

    Args:
        command (str): The command to check.

    Returns:
        bool: True if the command seems available, False otherwise.
    """
    try:
        # Try with --version first
        subprocess.run([command, "--version"], capture_output=True, text=True, check=True, timeout=2)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        try: # Some commands don't have --version, try help
            subprocess.run([command, "--help"], capture_output=True, text=True, check=True, timeout=2)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
            # For commands like `which`, we can just check existence
            if command == "which": # `which` itself doesn't have --version or --help in a standard way
                 try:
                    subprocess.run(["which", "ls"], capture_output=True, text=True, check=True, timeout=2)
                    return True
                 except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
                    return False
            return False

def get_default_linux_interface():
    """
    Tries to get the default network interface on Linux by checking the route to a public IP.

    Returns:
        str or None: The name of the default interface, or None if not found or an error occurs.
    """
    try:
        # Get the interface associated with the default route to a public IP (e.g., 1.1.1.1)
        result = subprocess.run(["ip", "route", "get", "1.1.1.1"], capture_output=True, text=True, check=True)
        match = re.search(r"dev\s+([^\s]+)", result.stdout)
        if match:
            return match.group(1)
    except (subprocess.CalledProcessError, FileNotFoundError, Exception) as e:
        print(f"Could not determine default interface: {e}")
    return None

def is_service_active(service_name):
    """
    Checks if a systemd service is active using 'systemctl is-active'.

    Args:
        service_name (str): The name of the systemd service.

    Returns:
        bool: True if the service is active, False otherwise or if systemctl is not available.
    """
    if not is_command_available("systemctl"):
        return False # Cannot check systemd service status if systemctl is not present
    try:
        result = subprocess.run(["systemctl", "is-active", service_name], capture_output=True, text=True)
        return result.returncode == 0 and result.stdout.strip() == "active"
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
    except Exception as e:
        print(f"Error checking service {service_name} status: {e}")
        return False

# --- Linux DNS Setting and Flushing Functions ---

def set_dns_linux(dns_servers):
    """
    Sets DNS servers for Linux.
    Tries methods in order: nmcli, resolvectl, then direct /etc/resolv.conf modification.

    Args:
        dns_servers (list[str]): A list of DNS server IP addresses.

    Returns:
        bool: True if DNS was successfully set by any method, False otherwise.
    """
    print(f"Attempting to set DNS for Linux with servers: {dns_servers}")
    if not dns_servers:
        print("No DNS servers provided.")
        return False

    dns_servers_str = " ".join(dns_servers) # For resolvectl command argument
    dns_servers_comma_str = ",".join(dns_servers) # For nmcli command argument

    # Method 1: NetworkManager (nmcli) - Preferred if available
    if is_command_available("nmcli"):
        print("\nAttempting to set DNS using nmcli...")
        try:
            # Get active devices
            result = subprocess.run(["nmcli", "-t", "-f", "DEVICE,STATE", "dev"], capture_output=True, text=True, check=True)
            active_devices = []
            for line in result.stdout.strip().split('\n'):
                if line.endswith(":connected"):
                    active_devices.append(line.split(':')[0])
            
            if not active_devices:
                print("nmcli: No active devices found.")
            else:
                for device in active_devices:
                    print(f"nmcli: Configuring device '{device}'")
                    cmd_set_dns = ["nmcli", "dev", "mod", device, "ipv4.dns", dns_servers_comma_str]
                    set_dns_result = subprocess.run(cmd_set_dns, capture_output=True, text=True)
                    if set_dns_result.returncode == 0:
                        print(f"nmcli: Successfully set DNS for '{device}'.")
                        
                        cmd_ignore_auto = ["nmcli", "dev", "mod", device, "ipv4.ignore-auto-dns", "yes"]
                        subprocess.run(cmd_ignore_auto, capture_output=True, text=True) # Best effort
                        
                        cmd_reapply = ["nmcli", "dev", "reapply", device]
                        reapply_result = subprocess.run(cmd_reapply, capture_output=True, text=True)
                        if reapply_result.returncode == 0:
                            print(f"nmcli: Successfully reapplied configuration for '{device}'.")
                            # Assuming success for at least one interface is enough
                            # A more robust solution might check if *all* desired interfaces were configured.
                            return True 
                        else:
                            print(f"nmcli: Error reapplying configuration for '{device}': {reapply_result.stderr.strip()}")
                    else:
                        print(f"nmcli: Error setting DNS for '{device}': {set_dns_result.stderr.strip()}")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"nmcli: Error during execution: {e}")
        except Exception as e:
            print(f"nmcli: An unexpected error occurred: {e}")

    # Method 2: systemd-resolve (resolvectl) - Second preference
    if is_command_available("resolvectl"):
        print("\nAttempting to set DNS using resolvectl...")
        interface = get_default_linux_interface() # Determine the primary interface
        if interface:
            cmd = ["resolvectl", "dns", interface] + dns_servers
            print(f"resolvectl: Executing: {' '.join(cmd)}")
            try:
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode == 0:
                    print(f"resolvectl: Successfully set DNS for interface '{interface}'.")
                    # Further configuration for search domains or DNSSEC could be added here if needed.
                    # e.g., subprocess.run(["resolvectl", "domain", interface, "your.search.domain"])
                    return True
                else:
                    print(f"resolvectl: Error setting DNS: {result.stderr.strip() or result.stdout.strip()}")
            except (subprocess.CalledProcessError, FileNotFoundError) as e:
                print(f"resolvectl: Error during execution: {e}")
            except Exception as e:
                print(f"resolvectl: An unexpected error occurred: {e}")
        else:
            print("resolvectl: Could not determine default network interface.")

    # Method 3: Direct /etc/resolv.conf modification (Fallback, last resort)
    print("\nAttempting to modify /etc/resolv.conf directly (use with caution)...")
    resolv_conf_path = "/etc/resolv.conf"
    
    # Perform safety checks before modifying /etc/resolv.conf
    # Check 1: Is it a symlink to a known dynamic file?
    if os.path.islink(resolv_conf_path):
        link_target = os.readlink(resolv_conf_path)
        known_dynamic_targets = [
            "systemd/resolve/stub-resolv.conf", 
            "systemd/resolve/resolv.conf",
            "NetworkManager/resolv.conf",
            "run/resolvconf/resolv.conf" # Common for resolvconf package
        ]
        if any(target in link_target for target in known_dynamic_targets):
            print(f"Warning: /etc/resolv.conf is a symlink to '{link_target}'. "
                  "Direct modification is unsafe and will likely be overwritten.")
            print("Please configure DNS using the appropriate tool (nmcli, resolvectl, or network configuration files).")
            return False

    # Check 2: Does it contain generator comments? (Even if not a symlink)
    try:
        with open(resolv_conf_path, 'r') as f:
            current_content = f.read(1024) # Read first 1KB for comments
            generator_comments = [
                "# Generated by NetworkManager",
                "# Generated by resolvconf",
                "# Generated by systemd-resolved",
                "# Dynamic resolv.conf(5) file for glibc resolver(3) generated by resolvconf(8)",
                "#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN"
            ]
            if any(comment in current_content for comment in generator_comments):
                print("Warning: /etc/resolv.conf appears to be managed by another service "
                      "(e.g., NetworkManager, resolvconf, systemd-resolved).")
                print("Direct modification is unsafe and will likely be overwritten.")
                return False
    except FileNotFoundError:
        print(f"Error: {resolv_conf_path} not found. Cannot modify.")
        return False
    except Exception as e:
        print(f"Error reading {resolv_conf_path} for checks: {e}")
        # If we can't read it for checks but it exists, it's risky to proceed.
        return False 
    
    # If safety checks pass, proceed with backup and write
    try:
        backup_path = "/etc/resolv.conf.bak_set_dns_py" # More specific backup name
        print(f"Backing up current {resolv_conf_path} to {backup_path}...")
        # Ensure privileges for cp and subsequent write
        subprocess.run(["sudo", "cp", "-f", resolv_conf_path, backup_path], check=True)

        print(f"Writing new DNS configuration to {resolv_conf_path}...")
        # Prepare content
        new_resolv_content = f"# DNS configuration managed by set_dns_crossplatform.py (manual override)\n"
        for server in dns_servers:
            new_resolv_content += f"nameserver {server}\n"
        # Optionally add search domains if needed: new_resolv_content += "search yourdomain.com\n"
        
        # Write using sudo with a temporary file to handle permissions
        temp_resolv_path = "/tmp/resolv.conf.new"
        with open(temp_resolv_path, 'w') as tmp_f:
            tmp_f.write(new_resolv_content)
        
        subprocess.run(["sudo", "mv", "-f", temp_resolv_path, resolv_conf_path], check=True)
        
        print(f"Successfully wrote new DNS servers to {resolv_conf_path}.")
        print("Warning: This direct modification might be temporary and overwritten by system services if not configured properly elsewhere.")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError, Exception) as e:
        print(f"Error modifying {resolv_conf_path}: {e}")
        print("Make sure you are running the script with sudo privileges for cp/mv operations.")

    print("\nFailed to set DNS using any available method on Linux.")
    return False

def flush_dns_linux():
    """
    Flushes DNS cache on Linux.
    Tries methods in order: resolvectl, nscd restart, dnsmasq restart.

    Returns:
        bool: True if any known cache flushing method succeeded, False otherwise.
    """
    print("\nAttempting to flush DNS cache for Linux...")
    flushed_successfully = False

    # Method 1: systemd-resolve (resolvectl)
    if is_command_available("resolvectl"):
        print("Attempting to flush DNS cache using resolvectl...")
        try:
            result = subprocess.run(["sudo", "resolvectl", "flush-caches"], capture_output=True, text=True)
            if result.returncode == 0:
                print("resolvectl: Successfully flushed DNS caches.")
                flushed_successfully = True
            else:
                print(f"resolvectl: Error flushing caches: {result.stderr.strip() or result.stdout.strip()}")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"resolvectl: Error during execution: {e}")
        except Exception as e:
            print(f"resolvectl: An unexpected error occurred: {e}")
    
    if flushed_successfully:
        return True # If resolvectl worked, we're done.

    # Method 2: nscd (Name Service Cache Daemon) - If resolvectl didn't work or wasn't available
    if is_command_available("nscd"): # Check if nscd executable exists
        print("\nAttempting to flush DNS using nscd...")
        restarted_nscd = False
        if is_command_available("systemctl"):
            try:
                # Check if service is active or even exists before trying to restart
                if is_service_active("nscd") or is_service_active("nscd.service"): 
                    result = subprocess.run(["sudo", "systemctl", "restart", "nscd"], capture_output=True, text=True)
                    if result.returncode == 0:
                        print("nscd: Successfully restarted via systemctl.")
                        restarted_nscd = True
                    else:
                        print(f"nscd: Error restarting via systemctl: {result.stderr.strip()}")
                else:
                    print("nscd: Service not active or found via systemctl, not attempting restart.")
            except Exception as e:
                print(f"nscd: Error with systemctl restart: {e}")
        
        if not restarted_nscd and os.path.exists("/etc/init.d/nscd"): # Fallback to init.d script
            print("nscd: Trying init.d script...")
            try:
                result = subprocess.run(["sudo", "/etc/init.d/nscd", "restart"], capture_output=True, text=True)
                if result.returncode == 0:
                    print("nscd: Successfully restarted via init.d script.")
                    restarted_nscd = True
                else:
                    print(f"nscd: Error restarting via init.d: {result.stderr.strip() or result.stdout.strip()}")
            except Exception as e:
                print(f"nscd: Error with init.d restart: {e}")
        
        if restarted_nscd:
            flushed_successfully = True # If nscd restarted, count as success for flushing.
    
    if flushed_successfully:
        return True # If nscd worked, we're done.

    # Method 3: dnsmasq - If other methods didn't work or weren't available
    if is_command_available("dnsmasq"): 
        print("\nAttempting to flush DNS using dnsmasq...")
        restarted_dnsmasq = False
        if is_command_available("systemctl"):
            try:
                # dnsmasq might run as dnsmasq.service or a custom name (e.g., if part of NetworkManager)
                # Checking common service names.
                dnsmasq_service_names = ["dnsmasq", "dnsmasq.service"] 
                active_dnsmasq_service = None
                for name in dnsmasq_service_names:
                    if is_service_active(name):
                        active_dnsmasq_service = name
                        break
                
                if active_dnsmasq_service:
                    result = subprocess.run(["sudo", "systemctl", "restart", active_dnsmasq_service], capture_output=True, text=True)
                    if result.returncode == 0:
                        print(f"dnsmasq: Successfully restarted '{active_dnsmasq_service}' via systemctl.")
                        restarted_dnsmasq = True
                    else:
                        print(f"dnsmasq: Error restarting '{active_dnsmasq_service}' via systemctl: {result.stderr.strip()}")
                else:
                    print("dnsmasq: Service not active or found via systemctl, not attempting restart.")
            except Exception as e:
                print(f"dnsmasq: Error with systemctl restart: {e}")

        if not restarted_dnsmasq and os.path.exists("/etc/init.d/dnsmasq"): # Fallback to init.d
            print("dnsmasq: Trying init.d script...")
            try:
                result = subprocess.run(["sudo", "/etc/init.d/dnsmasq", "restart"], capture_output=True, text=True)
                if result.returncode == 0:
                    print("dnsmasq: Successfully restarted via init.d script.")
                    restarted_dnsmasq = True
                else:
                    print(f"dnsmasq: Error restarting via init.d: {result.stderr.strip() or result.stdout.strip()}")
            except Exception as e:
                print(f"dnsmasq: Error with init.d restart: {e}")
        
        if restarted_dnsmasq:
            flushed_successfully = True # If dnsmasq restarted, count as success for flushing.
    
    if flushed_successfully:
        return True
    else:
        print("\nNo known DNS cache flushing method fully succeeded on Linux for this configuration.")
        return False


def set_dns_macos(dns_servers):
    """
    Sets DNS servers for macOS using 'networksetup'.
    It finds all network services and applies DNS settings to each.

    Args:
        dns_servers (list[str]): A list of DNS server IP addresses.

    Returns:
        bool: True if DNS was successfully set for at least one service, False otherwise.
    """
    print(f"Attempting to set DNS for macOS with servers: {dns_servers}")
    if not dns_servers:
        print("No DNS servers provided.")
        return False

    try:
        # List all network services using networksetup
        list_services_cmd = ["networksetup", "-listallnetworkservices"]
        print(f"Executing: {' '.join(list_services_cmd)}")
        result = subprocess.run(list_services_cmd, capture_output=True, text=True)

        if result.returncode != 0:
            print(f"Error listing network services: {result.stderr.strip() or result.stdout.strip()}")
            return False

        services = result.stdout.strip().split('\n')
        if not services or (len(services) == 1 and "An asterisk (*) denotes that a network service is disabled." in services[0]):
            # The first line might be a header or an informational message if no services are found.
            # If only the informational message is there, or services list is empty.
            actual_services = [s for s in services if not s.startswith("An asterisk") and s.strip()]
            if not actual_services:
                print("No network services found to configure.")
                return False
            services = actual_services


        print(f"Found network services: {services}")
        success_on_any_service = False

        dns_servers_str = " ".join(dns_servers)
        if not dns_servers_str: # Should ideally clear DNS
            dns_servers_str = "empty" 
            print("No specific DNS servers provided, will attempt to set to automatic/DHCP.")


        for service in services:
            if service.strip().startswith("An asterisk"): # Skip disabled services header line
                continue
            if not service.strip(): # Skip empty lines
                continue

            print(f"\nConfiguring DNS for service: '{service}'")
            # Check current status (optional, mainly for info, as -setdnsservers works on active ones)
            # get_dns_cmd = ["networksetup", "-getdnsservers", service]
            # status_check = subprocess.run(get_dns_cmd, capture_output=True, text=True)
            # print(f"Current DNS for '{service}': {status_check.stdout.strip() or 'Not set/Error'}")

            set_dns_cmd = ["sudo", "networksetup", "-setdnsservers", service, dns_servers_str]
            print(f"Executing: {' '.join(set_dns_cmd)}")
            
            try:
                set_result = subprocess.run(set_dns_cmd, capture_output=True, text=True)
                if set_result.returncode == 0:
                    # networksetup commands often print to stdout on success, e.g. nothing or new settings
                    print(f"Successfully set DNS for '{service}'.")
                    if set_result.stdout.strip(): print(f"Output: {set_result.stdout.strip()}")
                    success_on_any_service = True
                else:
                    # Common errors: service not active, or permission issues.
                    # Example error: "Ethernet is not a recognized network service." (if name is wrong)
                    # Or "** Error: The amount of arguments is incorrect." if DNS IPs are malformed / empty and not "empty"
                    error_message = set_result.stderr.strip() or set_result.stdout.strip() or "Unknown error"
                    print(f"Error setting DNS for '{service}': {error_message}")
                    if "You must run this tool as root." in error_message:
                        print("macOS: Permission denied. Please run the script with sudo.")
            except FileNotFoundError:
                print("Error: 'networksetup' command not found. This should not happen on macOS.")
                return False # Critical command missing
            except Exception as e:
                print(f"An unexpected error occurred while configuring '{service}': {e}")
        
        if not success_on_any_service:
            print("\nFailed to set DNS for any active service on macOS.")
            return False
        return True

    except subprocess.CalledProcessError as e:
        print(f"Error executing networksetup command: {e}")
        print(f"Stderr: {e.stderr.strip()}")
        return False
    except FileNotFoundError:
        print("Error: 'networksetup' command not found. Ensure macOS is correctly installed.")
        return False
    except Exception as e:
        print(f"An unexpected error occurred in set_dns_macos: {e}")
        return False

def flush_dns_macos():
    print("\nAttempting to flush DNS cache for macOS...")
    flushed_dscache = False
    flushed_mdnsresponder = False

    # 1. dscacheutil -flushcache (Older macOS versions, but often run for good measure)
        # This command might not be present or effective on very new macOS versions, 
        # but it's often run for thoroughness. Newer systems rely more on mDNSResponder.
    print("Attempting: sudo dscacheutil -flushcache")
    try:
        cmd_dscache = ["sudo", "dscacheutil", "-flushcache"]
            result_dscache = subprocess.run(cmd_dscache, capture_output=True, text=True) # No check=True, assess return code
        if result_dscache.returncode == 0:
                print("dscacheutil: Successfully ran flushcache command.")
            if result_dscache.stdout.strip(): print(f"Output: {result_dscache.stdout.strip()}")
                flushed_dscache = True 
        else:
            error_msg = result_dscache.stderr.strip() or result_dscache.stdout.strip()
                if "command not found" in error_msg.lower() or "No such file or directory" in error_msg.lower():
                     print("dscacheutil: Command not found (this is common on newer macOS versions and usually not an issue).")
                     flushed_dscache = True # Effectively, this command did not fail in a way that stops the process.
            else:
                    print(f"dscacheutil: Error running flushcache: {error_msg}")
    except FileNotFoundError:
            print("dscacheutil: Command not found (this is common on newer macOS versions and usually not an issue).")
            flushed_dscache = True 
    except Exception as e:
        print(f"dscacheutil: An unexpected error occurred: {e}")

    # 2. killall -HUP mDNSResponder (This is the primary method for modern macOS)
    print("\nAttempting: sudo killall -HUP mDNSResponder")
    try:
        cmd_mdns = ["sudo", "killall", "-HUP", "mDNSResponder"]
        result_mdns = subprocess.run(cmd_mdns, capture_output=True, text=True) # No check=True
        if result_mdns.returncode == 0:
            print("mDNSResponder: Successfully sent HUP signal to flush cache.")
            if result_mdns.stdout.strip(): print(f"Output: {result_mdns.stdout.strip()}")
            flushed_mdnsresponder = True
        else:
            error_msg = result_mdns.stderr.strip() or result_mdns.stdout.strip()
            print(f"mDNSResponder: Error sending HUP signal: {error_msg}")
            if "No matching processes" in error_msg: # More general check
                print("mDNSResponder: Process not found (it might not be running or an issue exists).")
            elif "Operation not permitted" in error_msg or "must be run as root" in error_msg.lower():
                 print("mDNSResponder: Permission denied. Ensure script is run with sudo.")
            # No specific error implies it might have failed for other reasons.


    except FileNotFoundError:
        print("killall: Command not found. This should not happen on macOS.")
    except Exception as e:
        print(f"mDNSResponder: An unexpected error occurred: {e}")

    if flushed_mdnsresponder: # Primary method for modern macOS
        print("\nDNS cache flush attempt completed for macOS.")
        return True
    elif flushed_dscache: # If dscacheutil was the only thing that "succeeded" (even if obsolete)
        print("\nDNS cache flush attempt completed (dscacheutil part only, mDNSResponder might have had issues).")
        return True # Still return true as an attempt was made with a potentially relevant command.
    else:
        print("\nFailed to flush DNS cache using known methods on macOS.")
        return False

# --- Functions to GET current DNS settings ---

def get_current_dns_windows():
    print("\nGetting current DNS settings for Windows...")
    original_settings = {}
    try:
        interfaces_result = subprocess.run(["netsh", "interface", "show", "interface"], capture_output=True, text=True, check=True, shell=True)
        active_interfaces_names = []
        lines = interfaces_result.stdout.strip().split('\n')
        if len(lines) > 2:
            for line in lines[2:]:
                parts = line.split()
                if len(parts) >= 4 and parts[0] == "Enabled" and parts[1] == "Connected":
                    interface_name = " ".join(parts[3:])
                    if interface_name:
                        active_interfaces_names.append(interface_name)
        
        if not active_interfaces_names:
            print("Windows: No active interfaces found to get DNS settings from.")
            return None

        for if_name in active_interfaces_names:
            print(f"Windows: Checking DNS for interface '{if_name}'")
            cmd = ["netsh", "interface", "ipv4", "show", "dnsservers", f"name=\"{if_name}\""]
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, check=True, shell=True)
                output = result.stdout.strip()
                current_dns_servers = []
                dhcp = False
                # Example output for static:
                # Configuration for interface "Ethernet"
                #     Statically Configured DNS Servers:    8.8.8.8
                #                                           8.8.4.4
                #     Register with which suffix:           Primary only
                # Example output for DHCP:
                # Configuration for interface "Wi-Fi"
                #     DNS servers configured through DHCP:  192.168.1.1
                #     Register with which suffix:           Primary only
                if "dhcp" in output.lower(): # Check if DNS is configured through DHCP
                    dhcp = True
                    # Try to find DNS servers listed even if DHCP
                    dns_lines = re.findall(r":\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})", output)
                    current_dns_servers.extend(dns_lines) # These might be the DHCP assigned ones
                    print(f"Windows: Interface '{if_name}' uses DHCP for DNS. Servers found: {current_dns_servers if current_dns_servers else 'None explicitly listed'}")
                    original_settings[if_name] = {"servers": current_dns_servers, "dhcp": True, "method": "netsh"}

                else: # Statically configured
                    dns_lines = re.findall(r"Statically Configured DNS Servers:\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})", output)
                    # netsh lists additional servers on new lines, indented.
                    additional_dns_lines = re.findall(r"^\s+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})", output, re.MULTILINE)
                    current_dns_servers.extend(dns_lines)
                    current_dns_servers.extend(additional_dns_lines)
                    
                    if current_dns_servers:
                        print(f"Windows: Interface '{if_name}' has static DNS: {current_dns_servers}")
                        original_settings[if_name] = {"servers": current_dns_servers, "dhcp": False, "method": "netsh"}
                    else:
                        print(f"Windows: Interface '{if_name}' - No static DNS servers found, might be DHCP or unconfigured.")
                        # If no static and not explicitly DHCP, could be unconfigured or another state.
                        # For restore purposes, treating as "dhcp" might be safest if no IPs found.
                        original_settings[if_name] = {"servers": [], "dhcp": True, "method": "netsh_unknown_fallback_to_dhcp"}


            except subprocess.CalledProcessError as e:
                print(f"Windows: Error getting DNS for interface '{if_name}': {e.stderr.strip()}")
            except Exception as e_gen:
                 print(f"Windows: Unexpected error getting DNS for '{if_name}': {e_gen}")


        return original_settings if original_settings else None
    except Exception as e:
        print(f"Windows: Error listing interfaces: {e}")
        return None

def get_current_dns_linux():
    print("\nGetting current DNS settings for Linux...")
    original_settings = {}

    # Try nmcli first
    if is_command_available("nmcli"):
        print("Linux: Trying nmcli...")
        try:
            # Get active devices
            result_dev = subprocess.run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev"], capture_output=True, text=True, check=True)
            for line in result_dev.stdout.strip().split('\n'):
                parts = line.split(':')
                if len(parts) == 3 and parts[2] == "connected":
                    device = parts[0]
                    print(f"Linux (nmcli): Checking device '{device}'")
                    show_result = subprocess.run(["nmcli", "dev", "show", device], capture_output=True, text=True, check=True)
                    dns_servers = []
                    dhcp_dns = []
                    is_dhcp = True # Assume DHCP by default, look for static settings
                    
                    for L in show_result.stdout.splitlines():
                        if "IP4.DNS[" in L:
                            dns_ip = L.split(":", 1)[1].strip()
                            if dns_ip: dns_servers.append(dns_ip)
                        if "DHCP4.OPTION[6]" in L: # DNS servers from DHCP
                            dhcp_dns_ip = L.split("=",1)[1].strip().split(" ")[0] # format like 'domain_name_servers = 1.2.3.4 5.6.7.8'
                            if dhcp_dns_ip: dhcp_dns.append(dhcp_dns_ip)


                    # Heuristic: if IP4.DNS is set, it's likely static. If not, and DHCP4.OPTION[6] is set, it's DHCP.
                    # ignore-auto-dns also plays a role. If ignore-auto-dns is 'no' (default), DHCP servers are used.
                    # If ignore-auto-dns is 'yes', then only manually configured IP4.DNS are used.
                    
                    # This logic is simplified: if manual IP4.DNS are present, we assume they are the primary ones.
                    # A more robust check would inspect 'ipv4.ignore-auto-dns'.
                    if dns_servers:
                        print(f"Linux (nmcli): Device '{device}' has static DNS: {dns_servers}")
                        original_settings[device] = {"servers": dns_servers, "dhcp": False, "method": "nmcli"}
                    elif dhcp_dns:
                        print(f"Linux (nmcli): Device '{device}' uses DHCP for DNS. Servers: {dhcp_dns}")
                        original_settings[device] = {"servers": dhcp_dns, "dhcp": True, "method": "nmcli"} # Store DHCP ones if found
                    else:
                        print(f"Linux (nmcli): Device '{device}' - No explicit DNS found, assuming DHCP or unmanaged.")
                        original_settings[device] = {"servers": [], "dhcp": True, "method": "nmcli_unknown_fallback_to_dhcp"}
            if original_settings: return original_settings
        except Exception as e:
            print(f"Linux (nmcli): Error: {e}")

    # Try systemd-resolve next
    if is_command_available("resolvectl"):
        print("Linux: Trying resolvectl...")
        interface = get_default_linux_interface()
        if interface:
            try:
                result = subprocess.run(["resolvectl", "status", interface], capture_output=True, text=True, check=True)
                dns_servers = []
                # Example: "Current DNS Server: 1.1.1.1" or "DNS Servers: 1.1.1.1 8.8.8.8"
                # Multiple "DNS Servers:" lines can exist for different protocols (DoT etc)
                # We are interested in the plain DNS ones primarily for restoration.
                # Simpler to parse /etc/resolv.conf if it's managed by systemd-resolved
                resolv_conf_path = "/etc/resolv.conf"
                if os.path.islink(resolv_conf_path) and "systemd/resolve" in os.readlink(resolv_conf_path):
                    with open(resolv_conf_path, 'r') as f:
                        for line in f:
                            if line.strip().startswith("nameserver"):
                                dns_servers.append(line.strip().split()[1])
                
                if dns_servers: # If we got them from systemd's /etc/resolv.conf
                     print(f"Linux (resolvectl): Interface '{interface}' using DNS: {dns_servers} (via /etc/resolv.conf)")
                     # It's hard to tell if these are from DHCP or static via resolvectl status easily for all cases.
                     # systemd-resolved often gets them from systemd-networkd or NetworkManager.
                     # For restoration, `resolvectl revert` is the key.
                     original_settings[interface] = {"servers": dns_servers, "dhcp": "unknown_revert_to_resolvectl", "method": "resolvectl"}
                else: # Fallback to parsing resolvectl status output (less reliable)
                    for line in result.stdout.splitlines():
                        if "DNS Servers:" in line or "Current DNS Server:" in line:
                            parts = line.split(":", 1)
                            if len(parts) > 1:
                                ips = parts[1].strip().split()
                                for ip_addr in ips:
                                    if is_valid_ip(ip_addr) and ip_addr not in dns_servers:
                                        dns_servers.append(ip_addr)
                    if dns_servers:
                        print(f"Linux (resolvectl): Interface '{interface}' using DNS: {dns_servers} (parsed from status)")
                        original_settings[interface] = {"servers": dns_servers, "dhcp": "unknown_revert_to_resolvectl", "method": "resolvectl"}
                    else:
                         print(f"Linux (resolvectl): No DNS servers found for '{interface}'. Assuming DHCP managed by systemd-resolved.")
                         original_settings[interface] = {"servers": [], "dhcp": True, "method": "resolvectl"}


                if original_settings: return original_settings
            except Exception as e:
                print(f"Linux (resolvectl): Error for interface {interface}: {e}")
        else:
            print("Linux (resolvectl): Could not determine default interface.")


    # Fallback: Read /etc/resolv.conf directly (with caveats)
    print("Linux: Trying direct /etc/resolv.conf read...")
    try:
        resolv_conf_path = "/etc/resolv.conf"
        if os.path.exists(resolv_conf_path) and not os.path.islink(resolv_conf_path):
            # Check for generator comments if it's not a symlink
            with open(resolv_conf_path, 'r') as f:
                content = f.read()
                if "# Generated by" in content:
                    print("Linux: /etc/resolv.conf is not a symlink but seems auto-generated. Skipping direct read for safety.")
                    return None # Avoid using potentially misleading info
            
            dns_servers = []
            with open(resolv_conf_path, 'r') as f:
                for line in f:
                    if line.strip().startswith("nameserver"):
                        dns_servers.append(line.strip().split()[1])
            if dns_servers:
                print(f"Linux (/etc/resolv.conf): Found DNS: {dns_servers}")
                # Assume static if manually edited /etc/resolv.conf
                original_settings["/etc/resolv.conf"] = {"servers": dns_servers, "dhcp": False, "method": "resolv.conf"}
                return original_settings # Return immediately if this method is used
    except Exception as e:
        print(f"Linux (/etc/resolv.conf): Error: {e}")

    return None if not original_settings else original_settings


def get_current_dns_macos():
    print("\nGetting current DNS settings for macOS...")
    original_settings = {}
    try:
        list_services_cmd = ["networksetup", "-listallnetworkservices"]
        result_services = subprocess.run(list_services_cmd, capture_output=True, text=True, check=True)
        services = [s for s in result_services.stdout.strip().split('\n') if not s.startswith("An asterisk") and s.strip()]

        if not services:
            print("macOS: No network services found.")
            return None

        for service in services:
            print(f"macOS: Checking DNS for service '{service}'")
            cmd = ["networksetup", "-getdnsservers", service]
            try:
                result_dns = subprocess.run(cmd, capture_output=True, text=True, check=True)
                output = result_dns.stdout.strip()
                if "aren't any DNS Servers set" in output or not output:
                    print(f"macOS: Service '{service}' uses DHCP for DNS (no servers listed).")
                    original_settings[service] = {"servers": [], "dhcp": True, "method": "networksetup"}
                else:
                    current_dns_servers = output.split('\n')
                    print(f"macOS: Service '{service}' has static DNS: {current_dns_servers}")
                    original_settings[service] = {"servers": current_dns_servers, "dhcp": False, "method": "networksetup"}
            except subprocess.CalledProcessError as e:
                # This can happen if a service is disabled or invalid
                print(f"macOS: Error getting DNS for service '{service}': {e.stderr.strip() or e.stdout.strip()}")
            except Exception as e_gen:
                print(f"macOS: Unexpected error for service '{service}': {e_gen}")
        
        return original_settings if original_settings else None
    except Exception as e:
        print(f"macOS: Error listing network services: {e}")
        return None

def save_original_dns_settings(original_settings, filepath=ORIGINAL_DNS_CONFIG_FILE):
    if original_settings:
        print(f"\nSaving original DNS settings to {filepath}...")
        try:
            with open(filepath, 'w') as f:
                json.dump(original_settings, f, indent=4)
            print("Original DNS settings saved successfully.")
        except IOError as e:
            print(f"Error: Could not write original DNS settings to file {filepath}: {e}")
        except Exception as e_gen:
            print(f"Unexpected error saving original DNS settings: {e_gen}")


def load_original_dns_settings(filepath=ORIGINAL_DNS_CONFIG_FILE):
    if not os.path.exists(filepath):
        print(f"Error: Original DNS settings file '{filepath}' not found. Cannot restore.")
        return None
    try:
        with open(filepath, 'r') as f:
            original_settings = json.load(f)
        print(f"Successfully loaded original DNS settings from {filepath}.")
        return original_settings
    except (IOError, json.JSONDecodeError) as e:
        print(f"Error reading or parsing original DNS settings file '{filepath}': {e}")
        return None
    except Exception as e_gen:
        print(f"Unexpected error loading original DNS settings: {e_gen}")
        return None

# --- DNS Restoration Functions ---

def restore_dns_windows(settings):
    print("\nRestoring DNS settings for Windows...")
    success = True
    for interface_name, config in settings.items():
        print(f"Windows: Restoring DNS for interface '{interface_name}'")
        is_dhcp = config.get("dhcp", False) # Default to not DHCP if unspecified
        servers = config.get("servers", [])

        try:
            if is_dhcp: # This includes "netsh_unknown_fallback_to_dhcp" cases
                cmd = ["netsh", "interface", "ipv4", "set", "dnsservers", f"name=\"{interface_name}\"", "source=dhcp"]
                print(f"Executing: {' '.join(cmd)}")
                result = subprocess.run(cmd, capture_output=True, text=True, check=True, shell=True)
                print(f"Windows: Successfully set '{interface_name}' to DHCP for DNS.")
                if result.stdout.strip(): print(f"Output: {result.stdout.strip()}")
            elif servers: # Static configuration
                cmd_set = ["netsh", "interface", "ipv4", "set", "dnsserver", f"name=\"{interface_name}\"", "static", f"addr=\"{servers[0]}\"", "validate=no"]
                print(f"Executing: {' '.join(cmd_set)}")
                subprocess.run(cmd_set, capture_output=True, text=True, check=True, shell=True)
                print(f"Windows: Successfully set primary DNS for '{interface_name}' to {servers[0]}.")
                for i, dns_server_ip in enumerate(servers[1:], start=1):
                    cmd_add = ["netsh", "interface", "ipv4", "add", "dnsserver", f"name=\"{interface_name}\"", f"addr=\"{dns_server_ip}\"", f"index={i+1}", "validate=no"]
                    print(f"Executing: {' '.join(cmd_add)}")
                    subprocess.run(cmd_add, capture_output=True, text=True, check=True, shell=True)
                    print(f"Windows: Successfully added DNS {dns_server_ip} for '{interface_name}'.")
            else:
                print(f"Windows: No valid DNS restore configuration for '{interface_name}'. Skipping.")
                success = False
        except subprocess.CalledProcessError as e:
            print(f"Windows: Error restoring DNS for '{interface_name}': {e.stderr.strip()}")
            success = False
        except FileNotFoundError:
            print("Windows: 'netsh' command not found. Cannot restore.")
            return False # Critical failure
        except Exception as e_gen:
            print(f"Windows: Unexpected error restoring DNS for '{interface_name}': {e_gen}")
            success = False
    return success

def restore_dns_linux(settings):
    print("\nRestoring DNS settings for Linux...")
    success = True
    for interface_id, config in settings.items(): # interface_id can be device name or "/etc/resolv.conf"
        print(f"Linux: Restoring DNS for '{interface_id}' using method '{config.get('method', 'unknown')}'")
        is_dhcp = config.get("dhcp", False)
        servers = config.get("servers", [])
        method = config.get("method", "")

        try:
            if method == "nmcli" or method == "nmcli_unknown_fallback_to_dhcp":
                if is_dhcp:
                    cmd_dns = ["nmcli", "dev", "mod", interface_id, "ipv4.dns", ""]
                    cmd_auto = ["nmcli", "dev", "mod", interface_id, "ipv4.ignore-auto-dns", "no"]
                else: # Static
                    cmd_dns = ["nmcli", "dev", "mod", interface_id, "ipv4.dns", ",".join(servers)]
                    cmd_auto = ["nmcli", "dev", "mod", interface_id, "ipv4.ignore-auto-dns", "yes"] # if static, then must ignore auto
                
                print(f"Linux (nmcli): Executing: {' '.join(cmd_dns)}")
                subprocess.run(cmd_dns, capture_output=True, text=True, check=True)
                print(f"Linux (nmcli): Executing: {' '.join(cmd_auto)}")
                subprocess.run(cmd_auto, capture_output=True, text=True, check=True)
                
                cmd_reapply = ["nmcli", "dev", "reapply", interface_id]
                print(f"Linux (nmcli): Executing: {' '.join(cmd_reapply)}")
                subprocess.run(cmd_reapply, capture_output=True, text=True, check=True)
                print(f"Linux (nmcli): Successfully restored DNS for '{interface_id}'.")

            elif method == "resolvectl":
                # `resolvectl revert` is the simplest way to restore systemd-resolved managed interfaces
                # This command reverts the interface to get DNS from DHCP or other link-local configs.
                cmd = ["resolvectl", "revert", interface_id]
                print(f"Linux (resolvectl): Executing: {' '.join(cmd)}")
                subprocess.run(cmd, capture_output=True, text=True, check=True)
                # If original was static AND we want to restore that static config via resolvectl:
                # if not is_dhcp and servers:
                #    cmd_static = ["resolvectl", "dns", interface_id] + servers
                #    subprocess.run(cmd_static, check=True)
                # else: revert is usually enough to go back to DHCP-provided.
                # For simplicity, revert is used for both DHCP and original static via resolvectl for now.
                print(f"Linux (resolvectl): Successfully reverted DNS for interface '{interface_id}'.")

            elif method == "resolv.conf": # Direct modification restoration
                backup_path = "/etc/resolv.conf.bak"
                if os.path.exists(backup_path):
                    print(f"Linux (/etc/resolv.conf): Restoring from backup {backup_path}")
                    subprocess.run(["mv", backup_path, "/etc/resolv.conf"], check=True) # Use mv with sudo
                    print("Linux (/etc/resolv.conf): Successfully restored from backup.")
                else:
                    print(f"Linux (/etc/resolv.conf): Backup file {backup_path} not found. Cannot restore.")
                    success = False
            else:
                print(f"Linux: Unknown restoration method or configuration for '{interface_id}'. Skipping.")
                success = False
        except subprocess.CalledProcessError as e:
            print(f"Linux: Error restoring DNS for '{interface_id}': {e.stderr.strip() or e.stdout.strip()}")
            success = False
        except FileNotFoundError as e_fnf:
            print(f"Linux: Command not found during restore for '{interface_id}': {e_fnf.filename}. Cannot restore.")
            return False # Critical failure
        except Exception as e_gen:
            print(f"Linux: Unexpected error restoring DNS for '{interface_id}': {e_gen}")
            success = False
    return success

def restore_dns_macos(settings):
    print("\nRestoring DNS settings for macOS...")
    success = True
    for service_name, config in settings.items():
        print(f"macOS: Restoring DNS for service '{service_name}'")
        is_dhcp = config.get("dhcp", False)
        servers = config.get("servers", [])
        
        try:
            if is_dhcp:
                cmd = ["sudo", "networksetup", "-setdnsservers", service_name, "empty"]
            elif servers:
                cmd = ["sudo", "networksetup", "-setdnsservers", service_name] + servers
            else:
                print(f"macOS: No valid DNS restore configuration for '{service_name}'. Skipping.")
                success = False
                continue # next service

            print(f"Executing: {' '.join(cmd)}")
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"macOS: Successfully restored DNS for '{service_name}'.")
        except subprocess.CalledProcessError as e:
            print(f"macOS: Error restoring DNS for '{service_name}': {e.stderr.strip() or e.stdout.strip()}")
            success = False
        except FileNotFoundError:
            print("macOS: 'networksetup' command not found. Cannot restore.")
            return False # Critical failure
        except Exception as e_gen:
            print(f"macOS: Unexpected error restoring DNS for '{service_name}': {e_gen}")
            success = False
    return success

def run_restore_dns_flow():
    print("--- DNS Restoration Process ---")
    if not check_privileges():
        print("\nError: Restoration requires administrator/root privileges.")
        if get_os() == "windows": print("Please run this script as an Administrator.")
        elif get_os() in ["linux", "macos"]: print("Please run this script with sudo.")
        sys.exit(1)

    original_settings = load_original_dns_settings()
    if not original_settings:
        print("Exiting: No original settings to restore or error loading them.")
        sys.exit(1)

    current_os = get_os()
    restored_ok = False
    if current_os == "windows":
        restored_ok = restore_dns_windows(original_settings.get("windows", {}))
    elif current_os == "linux":
        restored_ok = restore_dns_linux(original_settings.get("linux", {}))
    elif current_os == "macos":
        restored_ok = restore_dns_macos(original_settings.get("macos", {}))
    else:
        print(f"Restoration not supported for unknown OS: {current_os}")
        sys.exit(1)

    if restored_ok:
        print("\nDNS settings restored successfully.")
        try:
            os.remove(ORIGINAL_DNS_CONFIG_FILE)
            print(f"Removed original DNS settings file: {ORIGINAL_DNS_CONFIG_FILE}")
        except OSError as e:
            print(f"Warning: Could not remove original DNS settings file {ORIGINAL_DNS_CONFIG_FILE}: {e}")
    else:
        print("\nDNS restoration encountered errors. Original settings file preserved if it exists.")
    
    flush_dns() # Attempt to flush DNS after restoration as well

def run_set_dns_flow():
    print("--- Set New DNS Process ---")
    if not check_privileges(): # Check privileges again for this flow specifically
        print("\nError: Setting DNS requires administrator/root privileges.")
        if get_os() == "windows": print("Please run this script as an Administrator.")
        elif get_os() in ["linux", "macos"]: print("Please run this script with sudo.")
        sys.exit(1)

    current_os = get_os() # get_os() is cheap, or pass as arg
    
    # Get and save current DNS settings BEFORE changing them
    print("Gathering current DNS settings before making changes...")
    os_specific_original_dns = {}
    if current_os == "windows":
        os_specific_original_dns = get_current_dns_windows()
    elif current_os == "linux":
        os_specific_original_dns = get_current_dns_linux()
    elif current_os == "macos":
        os_specific_original_dns = get_current_dns_macos()
    
    if os_specific_original_dns:
        # We store them under an OS-specific key in the JSON
        # This helps if the file is accidentally moved between OSes, though unlikely for this use case.
        save_original_dns_settings({current_os: os_specific_original_dns})
    else:
        print("Warning: Could not retrieve current DNS settings. Restoration might not be possible.")

    # Proceed with setting new DNS
    dns_servers_list = parse_dns_config() # From dnsConf.txt
    if dns_servers_list is None:
        print("Exiting due to DNS configuration error from dnsConf.txt.")
        # Consider if we should restore if original settings were saved but new ones are invalid.
        # For now, exiting. The original_dns_config.json would remain.
        sys.exit(1)
    
    print(f"\nDNS servers to be set from dnsConf.txt: {dns_servers_list}")
    
    set_successful = False
    if current_os == "windows":
        set_dns_windows(dns_servers_list) # This function needs to return success/failure
        # Assuming set_dns_windows and others will be modified to return boolean
        # For now, we'll just call flush if it doesn't crash.
        set_successful = set_dns_windows(dns_servers_list) 
    elif current_os == "linux":
        set_successful = set_dns_linux(dns_servers_list)
    elif current_os == "macos":
        set_successful = set_dns_macos(dns_servers_list)
    else:
        print("Operating system not supported by this script for setting DNS.")
        sys.exit(1)

    if set_successful: # Check if setting DNS was actually successful
        print("\nNew DNS settings applied successfully (or attempted).")
        flush_dns() # General flush call
    else:
        print("\nFailed to apply new DNS settings. Check logs above.")
        # Consider restoring original settings automatically if set failed.
        # For now, we leave original_dns_config.json for manual restore if needed.

def flush_dns(): # Combined flush function
    current_os = get_os()
    print(f"\nAttempting to flush DNS for {current_os} after operations...")
    if current_os == "windows":
        flush_dns_windows()
    elif current_os == "linux":
        flush_dns_linux()
    elif current_os == "macos":
        flush_dns_macos()
    else:
        print(f"DNS flush not supported for unknown OS: {current_os}")


# --- Privilege Checking ---
def check_privileges():
    """Checks if the script is running with administrator/root privileges."""
    current_os_for_privileges = get_os() # Renamed to avoid conflict in the same scope if this were in __main__
    print(f"Checking privileges for OS: {current_os_for_privileges}...") # Added print statement

    if current_os_for_privileges == "windows":
        try:
            is_admin = (ctypes.windll.shell32.IsUserAnAdmin() != 0)
            if is_admin:
                print("Windows: Administrator privileges detected.")
            else:
                print("Windows: Administrator privileges NOT detected.")
            return is_admin
        except AttributeError:
            print("Error: ctypes.windll.shell32.IsUserAnAdmin not found. Cannot check admin status on this Windows version.")
            return False # Assume no admin rights if the check fails
        except Exception as e:
            print(f"Error checking Windows admin status: {e}")
            return False
    elif current_os_for_privileges == "linux" or current_os_for_privileges == "macos":
        is_root = (os.geteuid() == 0)
        if is_root:
            print(f"{current_os_for_privileges.capitalize()}: Root privileges detected.")
        else:
            print(f"{current_os_for_privileges.capitalize()}: Root privileges NOT detected.")
        return is_root
    else:
        print(f"Unknown OS ({current_os_for_privileges}): Cannot determine privilege level.")
        return False


if __name__ == "__main__":
    current_os_for_privileges = get_os() # Renamed to avoid conflict in the same scope if this were in __main__
    print(f"Checking privileges for OS: {current_os_for_privileges}...") # Added print statement

    if current_os_for_privileges == "windows":
        try:
            is_admin = (ctypes.windll.shell32.IsUserAnAdmin() != 0)
            if is_admin:
                print("Windows: Administrator privileges detected.")
            else:
                print("Windows: Administrator privileges NOT detected.")
            return is_admin
        except AttributeError:
            print("Error: ctypes.windll.shell32.IsUserAnAdmin not found. Cannot check admin status on this Windows version.")
            return False # Assume no admin rights if the check fails
        except Exception as e:
            print(f"Error checking Windows admin status: {e}")
            return False
    elif current_os_for_privileges == "linux" or current_os_for_privileges == "macos":
        is_root = (os.geteuid() == 0)
        if is_root:
            print(f"{current_os_for_privileges.capitalize()}: Root privileges detected.")
        else:
            print(f"{current_os_for_privileges.capitalize()}: Root privileges NOT detected.")
        return is_root
    else:
        print(f"Unknown OS ({current_os_for_privileges}): Cannot determine privilege level.")
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Cross-platform DNS setting and restoration utility.")
    parser.add_argument("--restore", action="store_true", help="Restore original DNS settings.")
    args = parser.parse_args()

    if args.restore:
        run_restore_dns_flow()
    else:
        run_set_dns_flow()
    
    # Example of creating a dummy dnsConf.txt for testing - should be removed or conditional for actual use
    # This part would typically be removed or conditional for actual use
    # if not os.path.exists("dnsConf.txt") and not args.restore : # Only create if not restoring and not existing
    #     print("\nCreating a dummy 'dnsConf.txt' for testing purposes as it's missing.")
    #     with open("dnsConf.txt", "w") as f:
    #         f.write("# DNS Configuration File - dnsConf.txt\n")
    #         f.write("GoogleDNS1=8.8.8.8\n")
    #         f.write("GoogleDNS2=8.8.4.4\n")
    #         f.write("CloudflareDNS=1.1.1.1\n")
    #         f.write("#Quad9DNS=9.9.9.9 # This one will be ignored as we only take 3 (if uncommented)\n")
    #         f.write("#InvalidEntry=abc\n") 
    #         f.write("#MalformedLine\n")
    #     print("Dummy 'dnsConf.txt' created. Please populate it and run the script again to set DNS, or use --restore.")
