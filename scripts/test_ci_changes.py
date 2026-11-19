#!/usr/bin/env python3
"""Tests for scripts/ci_changes.py: which changes need CI's Mac jobs (Kit tests, App build).
Run: python3 -I scripts/test_ci_changes.py"""
import os, subprocess, sys, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ci_changes


class NeedsMacTests(unittest.TestCase):
    def test_a_website_only_change_skips_the_mac_jobs(self):
        self.assertFalse(ci_changes.needs_mac(["website/site.css", "website/index.html"]))

    def test_no_known_changes_run_the_mac_jobs(self):
        # an empty diff means CI couldn't tell (a new branch, a force push): run everything
        self.assertTrue(ci_changes.needs_mac([]))

    def test_any_app_change_runs_the_mac_jobs(self):
        self.assertTrue(ci_changes.needs_mac(["website/site.css", "Packages/ControllerBridgeKit/Package.swift"]))
        self.assertTrue(ci_changes.needs_mac(["App/BridgeModel.swift"]))

    def test_site_scripts_and_markdown_docs_skip_the_mac_jobs(self):
        self.assertFalse(ci_changes.needs_mac([
            "scripts/check_site.py", "scripts/test_check_site.py", "scripts/site-preview.sh",
            "scripts/test_analytics.mjs", "scripts/test_capture.mjs",
            "README.md", "CHANGELOG.md", "docs/research/controllers.md"]))

    def test_the_domain_docs_and_their_check_skip_the_mac_jobs(self):
        self.assertFalse(ci_changes.needs_mac([
            "GLOSSARY.md", "docs/adr/0001-native-swift-menu-bar-app.md",
            "scripts/check_domain_docs.py", "scripts/test_check_domain_docs.py"]))

    def test_the_lc6000_firmware_tool_skips_the_mac_jobs(self):
        # tools/lc6000-firmware (#430): Python with its own tests, run by the Site check job
        self.assertFalse(ci_changes.needs_mac([
            "tools/lc6000-firmware/dfupatch.py", "tools/lc6000-firmware/test_dfupatch.py",
            "tools/lc6000-firmware/.gitignore"]))

    def test_the_drawn_display_firmware_skips_the_mac_jobs(self):
        # tools/lc6000-display-fw (#457): C with its own tests, run by the Display firmware job on Linux
        self.assertFalse(ci_changes.needs_mac([
            "tools/lc6000-display-fw/src/dfw.c", "tools/lc6000-display-fw/test/test_modes.c",
            "tools/lc6000-display-fw/Makefile", "tools/lc6000-display-fw/README.md"]))

    def test_the_shared_message_vectors_run_the_mac_jobs(self):
        # the vectors file (#456) is walked by the Kit tests too, so a change to it alone must still run them
        self.assertTrue(ci_changes.needs_mac(["tools/lc6000-display-fw/vectors/messages.json"]))

    def test_workflow_and_release_script_changes_run_the_mac_jobs(self):
        for path in [".github/workflows/ci.yml", "scripts/ci_profile.py", "scripts/smoke.sh", "project.yml",
                     ".github/pull_request_template.md"]:
            self.assertTrue(ci_changes.needs_mac([path]), path)


class OutputTests(unittest.TestCase):
    def run_script(self, stdin):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci_changes.py")
        return subprocess.run([sys.executable, "-I", script], input=stdin, capture_output=True, text=True, check=True).stdout

    def test_it_prints_one_github_output_line(self):
        self.assertEqual(self.run_script("website/site.css\n\nREADME.md\n"), "mac=false\n")
        self.assertEqual(self.run_script("App/UDP.swift\n"), "mac=true\n")
        self.assertEqual(self.run_script(""), "mac=true\n")


if __name__ == "__main__":
    unittest.main()
