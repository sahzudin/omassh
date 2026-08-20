from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "bin" / "omassh-hosts"
PANEL = Path(__file__).parents[1] / "Panel.qml"
loader = importlib.machinery.SourceFileLoader("omassh_hosts", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[loader.name] = module
spec.loader.exec_module(module)


class DiscoveryTests(unittest.TestCase):
    def test_discovers_literal_hosts_and_display_options(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            included = root / "conf.d"
            included.mkdir()
            config.write_text(
                """
                Include=conf.d/*.conf
                Host *
                    ServerAliveInterval 30
                Host production prod
                    HostName=10.0.0.8
                    User deploy
                    Port 2202
                    ProxyJump bastion
                Host web-*
                    User ignored
                """,
                encoding="utf-8",
            )
            (included / "bastion.conf").write_text(
                "Host bastion\n  HostName jump.example.com\n  User ops\n",
                encoding="utf-8",
            )

            hosts, files, errors = module.discover(config)
            self.assertEqual([host.alias for host in hosts], ["bastion", "production", "prod"])
            self.assertEqual(errors, [])
            self.assertEqual(len(files), 2)
            production = hosts[1].as_json()
            self.assertEqual(production["details"], "deploy@10.0.0.8:2202  via bastion")
            self.assertIn("production", production["searchText"])
            self.assertIn("10.0.0.8", production["searchText"])

    def test_match_context_does_not_leak_into_following_host(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "config"
            config.write_text(
                "Match user root\n  User matched\nHost safe\n  User normal\n",
                encoding="utf-8",
            )
            hosts, _, _ = module.discover(config)
            self.assertEqual(len(hosts), 1)
            self.assertEqual(hosts[0].options["user"], "normal")

    def test_missing_config_is_reported_without_crashing(self) -> None:
        missing = Path("/definitely/not/an/omassh/config")
        hosts, files, errors = module.discover(missing)
        self.assertEqual(hosts, [])
        self.assertEqual(files, [])
        self.assertIn("SSH config not found", errors[0])


class RecentTests(unittest.TestCase):
    def test_recent_state_round_trip_uses_private_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": temporary}):
                module.write_recents({"prod": 20, "dev": 10})
                self.assertEqual(module.read_recents(), {"prod": 20, "dev": 10})
                mode = module.state_path().stat().st_mode & 0o777
                self.assertEqual(mode, 0o600)


class QmlSafetyTests(unittest.TestCase):
    def test_every_text_item_forces_plain_text(self) -> None:
        panel = PANEL.read_text(encoding="utf-8")
        self.assertGreater(panel.count("Text {"), 0)
        self.assertEqual(
            panel.count("Text {"),
            panel.count("textFormat: Text.PlainText"),
            "Every QML Text item must opt out of auto-rich-text rendering.",
        )


if __name__ == "__main__":
    unittest.main()
