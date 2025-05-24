import unittest
import os
import shutil
import platform
from unittest.mock import patch 

# Add the parent directory to sys.path to allow importing set_dns_crossplatform
import sys
# Assuming test_set_dns_crossplatform.py is in the same directory as set_dns_crossplatform.py
# If it's in a subdirectory, adjust the path accordingly.
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

try:
    import set_dns_crossplatform
except ModuleNotFoundError:
    print("ERROR: Could not import set_dns_crossplatform.py. Make sure it's in the same directory or PYTHONPATH is set correctly.")
    sys.exit(1)


class TestDnsScript(unittest.TestCase):

    def setUp(self):
        # Create a temporary directory for test files
        self.test_dir = "temp_test_dns_config"
        os.makedirs(self.test_dir, exist_ok=True)
        self.dummy_conf_path = os.path.join(self.test_dir, "dnsConf.txt")

    def tearDown(self):
        # Remove the temporary directory and its contents
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def write_dummy_config(self, content):
        with open(self.dummy_conf_path, 'w') as f:
            f.write(content)

    # --- Tests for get_os ---
    def test_get_os_windows(self):
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="Windows"), "windows")
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="Win32NT"), "windows")

    def test_get_os_linux(self):
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="Linux"), "linux")

    def test_get_os_macos(self):
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="Darwin"), "macos")

    def test_get_os_unknown(self):
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="SunOS"), "unknown")
        self.assertEqual(set_dns_crossplatform.get_os(test_platform_system="FreeBSD"), "unknown")
    
    # To test the actual platform.system() call if no argument is passed (optional, less controlled)
    @patch('platform.system')
    def test_get_os_mocked_current_platform(self, mock_system):
        mock_system.return_value = "Linux"
        self.assertEqual(set_dns_crossplatform.get_os(), "linux")
        mock_system.return_value = "Windows"
        self.assertEqual(set_dns_crossplatform.get_os(), "windows")
        mock_system.return_value = "Darwin"
        self.assertEqual(set_dns_crossplatform.get_os(), "macos")


    # --- Tests for parse_dns_config ---
    def test_parse_valid_config_less_than_3_ips(self):
        content = "GoogleDNS1=8.8.8.8\nCloudflareDNS=1.1.1.1\n"
        self.write_dummy_config(content)
        expected = ["8.8.8.8", "1.1.1.1"]
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)

    def test_parse_valid_config_exactly_3_ips(self):
        content = "DNS1=8.8.8.8\nDNS2=1.1.1.1\nDNS3=9.9.9.9\n"
        self.write_dummy_config(content)
        expected = ["8.8.8.8", "1.1.1.1", "9.9.9.9"]
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)

    def test_parse_valid_config_more_than_3_ips(self):
        content = "DNS1=8.8.8.8\nDNS2=1.1.1.1\nDNS3=9.9.9.9\nDNS4=4.4.4.4\n"
        self.write_dummy_config(content)
        expected = ["8.8.8.8", "1.1.1.1", "9.9.9.9"] # Should only take the first 3
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)

    def test_parse_config_with_comments_and_empty_lines(self):
        content = "# This is a comment\nGoogleDNS1=8.8.8.8\n\nCloudflareDNS=1.1.1.1\n#AnotherComment\n\n"
        self.write_dummy_config(content)
        expected = ["8.8.8.8", "1.1.1.1"]
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)

    def test_parse_empty_config_file(self):
        content = ""
        self.write_dummy_config(content)
        # Expect None because the file is empty, and parse_dns_config prints an error
        self.assertIsNone(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path))

    def test_parse_config_file_with_only_comments_or_empty_lines(self):
        content = "# Comment 1\n\n# Comment 2\n   \n"
        self.write_dummy_config(content)
        # Expect None because no valid DNS entries are found
        self.assertIsNone(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path))

    def test_parse_config_malformed_entries_no_equals(self):
        content = "GoogleDNS18.8.8.8\nCloudflareDNS=1.1.1.1\n" # First entry malformed
        self.write_dummy_config(content)
        expected = ["1.1.1.1"] # Should skip the malformed one
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)

    def test_parse_config_malformed_entries_invalid_ip(self):
        content = "GoogleDNS1=8.8.8.256\nCloudflareDNS=1.1.1.1\nAnotherInvalid=123.456.789\nDNS3=9.9.9.9"
        self.write_dummy_config(content)
        expected = ["1.1.1.1", "9.9.9.9"] # Should skip invalid IPs
        self.assertEqual(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path), expected)
    
    def test_parse_config_all_malformed_or_invalid(self):
        content = "GoogleDNS1=8.8.8.256\nNoEqualsHere\nInvalidIP=1.2.3.4.5\n"
        self.write_dummy_config(content)
        self.assertIsNone(set_dns_crossplatform.parse_dns_config(self.dummy_conf_path))


    def test_parse_non_existent_config_file(self):
        non_existent_path = os.path.join(self.test_dir, "non_existent_conf.txt")
        self.assertIsNone(set_dns_crossplatform.parse_dns_config(non_existent_path))

    # --- is_valid_ip tests (already implicitly tested by parse_dns_config tests, but can be explicit) ---
    def test_is_valid_ip_true(self):
        self.assertTrue(set_dns_crossplatform.is_valid_ip("8.8.8.8"))
        self.assertTrue(set_dns_crossplatform.is_valid_ip("192.168.0.1"))
        self.assertTrue(set_dns_crossplatform.is_valid_ip("0.0.0.0"))
        self.assertTrue(set_dns_crossplatform.is_valid_ip("255.255.255.255"))

    def test_is_valid_ip_false(self):
        self.assertFalse(set_dns_crossplatform.is_valid_ip("8.8.8.256"))
        self.assertFalse(set_dns_crossplatform.is_valid_ip("192.168.0"))
        self.assertFalse(set_dns_crossplatform.is_valid_ip("1.1.1.1.1"))
        self.assertFalse(set_dns_crossplatform.is_valid_ip("abc.def.ghi.jkl"))
        self.assertFalse(set_dns_crossplatform.is_valid_ip("8.8.8"))
        self.assertFalse(set_dns_crossplatform.is_valid_ip("8.8.8.8."))
        self.assertFalse(set_dns_crossplatform.is_valid_ip(""))


if __name__ == '__main__':
    unittest.main(argv=['first-arg-is-ignored'], exit=False)
