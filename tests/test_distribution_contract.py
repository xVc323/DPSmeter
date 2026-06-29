import pathlib
import re
import subprocess
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


class DistributionContract(unittest.TestCase):
    def read(self, path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def test_distribution_scripts_exist(self):
        for path in [
            "scripts/install-macos.sh",
            "scripts/uninstall-macos.sh",
            "scripts/install-windows.ps1",
            "scripts/uninstall-windows.ps1",
            "scripts/package-release.sh",
        ]:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_shell_scripts_parse(self):
        for path in ["scripts/install-macos.sh", "scripts/uninstall-macos.sh", "scripts/package-release.sh"]:
            result = subprocess.run(["bash", "-n", str(ROOT / path)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_macos_installer_targets_executable_adjacent_mods_and_does_not_touch_saves(self):
        script = self.read("scripts/install-macos.sh")
        self.assertIn("SlayTheSpire2.app/Contents/MacOS/mods", script)
        self.assertIn("DPSMETER_PACKAGE", script)
        self.assertIn("releases/latest/download/DPSMeter.zip", script)
        self.assertIn("backup_mod_dir", script)
        self.assertNotRegex(script, r"ln\s+-s")
        self.assertNotIn("modded/profile", script)
        self.assertNotIn("profile1/saves", script)
        self.assertNotIn("DPSMETER_UNLINK_SAVES", script)
        self.assertIn("affects_gameplay", script)
        self.assertIn("DPSMETER_DRY_RUN", script)
        self.assertIn("DPSMETER_TEMP_DIR", script)

    def test_macos_uninstaller_removes_only_mod_by_default(self):
        script = self.read("scripts/uninstall-macos.sh")
        self.assertIn("SlayTheSpire2.app/Contents/MacOS/mods", script)
        self.assertIn("rm -rf", script)
        self.assertIn("DPSMeter", script)
        self.assertNotIn("DPSMETER_UNLINK_SAVES", script)
        self.assertNotIn("profile1/saves", script)
        self.assertNotIn("modded/profile", script)
        self.assertNotIn("rm -rf \"$account/profile", script)

    def test_windows_installer_targets_executable_adjacent_mods_and_does_not_touch_saves(self):
        script = self.read("scripts/install-windows.ps1")
        self.assertIn("Find-Sts2Executable", script)
        self.assertIn("Split-Path", script)
        self.assertIn("mods", script)
        self.assertIn("DPSMeter.zip", script)
        self.assertIn("Backup-ModDir", script)
        self.assertNotRegex(script, r"ItemType\s+Junction")
        self.assertNotIn("Share-Saves", script)
        self.assertNotIn("Convert-SaveLinks", script)
        self.assertNotIn("modded", script)
        self.assertIn("affects_gameplay", script)
        self.assertIn("DPSMETER_PACKAGE", script)

    def test_windows_uninstaller_removes_only_mod_by_default(self):
        script = self.read("scripts/uninstall-windows.ps1")
        self.assertIn("Find-Sts2Executable", script)
        self.assertIn("Remove-Item", script)
        self.assertNotIn("DPSMETER_UNLINK_SAVES", script)
        self.assertNotIn("Convert-SaveLinks", script)
        self.assertNotIn("Share-Saves", script)
        self.assertNotIn("profile1\\saves' -Recurse", script)


    def test_installers_keep_backups_outside_scanned_mods_folder(self):
        mac = self.read("scripts/install-macos.sh")
        win = self.read("scripts/install-windows.ps1")

        self.assertIn("backup_mod_dir", mac)
        self.assertIn("dpsmeter-backups", mac)
        self.assertNotIn('backup_path "$mod_dir"', mac)
        self.assertIn("Backup-ModDir", win)
        self.assertIn("dpsmeter-backups", win)
        self.assertNotIn("Backup-Path $ModDir", win)

    def test_readme_documents_public_install_and_uninstall(self):
        readme = self.read("README.md")
        self.assertIn("curl -fsSL", readme)
        self.assertIn("install-macos.sh", readme)
        self.assertIn("uninstall-macos.sh", readme)
        self.assertIn("irm", readme)
        self.assertIn("install-windows.ps1", readme)
        self.assertIn("uninstall-windows.ps1", readme)
        self.assertIn("do not touch, copy, delete, symlink, or junction any saves", readme)
        self.assertIn("Steam Cloud", readme)
        self.assertIn("DPSMeter.zip", readme)

    def test_package_script_creates_expected_zip_when_run(self):
        script = self.read("scripts/package-release.sh")
        self.assertIn("dotnet build", script)
        self.assertIn("DPSMeter.zip", script)
        self.assertIn("DPSMeter.dll", script)
        self.assertIn("DPSMeter.json", script)


if __name__ == "__main__":
    unittest.main()
