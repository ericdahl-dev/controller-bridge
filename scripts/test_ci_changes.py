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
