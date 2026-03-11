#!/usr/bin/env python3
from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER_SCRIPT = ROOT / "server" / "fricu_server.py"


class PythonServerE2ETests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "fricu_server.db"
        self.state_dir = Path(self.temp_dir.name)
        self.port = self._free_port()
        self.proc = subprocess.Popen(
            [
                "python3",
                str(SERVER_SCRIPT),
                "--host",
                "127.0.0.1",
                "--port",
                str(self.port),
                "--db-file",
                str(self.db_path),
                "--state-dir",
                str(self.state_dir),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self._wait_until_ready()

    def tearDown(self) -> None:
        if getattr(self, "proc", None) is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
        if getattr(self, "temp_dir", None) is not None:
            self.temp_dir.cleanup()

    def test_health_endpoint(self) -> None:
        status, headers, body = self._request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertTrue(headers.get("x-log-id"))
        self.assertEqual(json.loads(body), {"status": "ok"})

    def test_missing_account_header_is_rejected(self) -> None:
        status, _, body = self._request("GET", "/v1/data/activities")
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(body)["error"], "missing X-Account-Id")

    def test_put_then_get_round_trip(self) -> None:
        payload = [{"id": "a1", "sport": "cycling"}]
        status, headers, body = self._request(
            "PUT",
            "/v1/data/activities",
            headers={"X-Account-Id": "tester", "X-Log-Id": "cli-activities-123"},
            body=json.dumps(payload).encode("utf-8"),
        )
        self.assertEqual(status, 204)
        self.assertEqual(body, b"")
        self.assertEqual(headers.get("x-log-id"), "cli-activities-123")

        status, headers, body = self._request(
            "GET",
            "/v1/data/activities",
            headers={"X-Account-Id": "tester", "X-Log-Id": "cli-activities-456"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(headers.get("x-log-id"), "cli-activities-456")
        self.assertEqual(json.loads(body), payload)

    def test_object_keys_default_to_empty_object(self) -> None:
        status, _, body = self._request(
            "GET",
            "/v1/data/app_settings",
            headers={"X-Account-Id": "tester"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {})

    def _request(self, method: str, path: str, headers: dict[str, str] | None = None, body: bytes | None = None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, {k.lower(): v for k, v in response.getheaders()}, response.read()
        finally:
            connection.close()

    def _wait_until_ready(self) -> None:
        deadline = time.time() + 10
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"server exited early with code {self.proc.returncode}")
            try:
                status, _, _ = self._request("GET", "/health")
                if status == 200:
                    return
            except OSError:
                time.sleep(0.05)
                continue
        raise TimeoutError("server did not become ready")

    @staticmethod
    def _free_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])


if __name__ == "__main__":
    unittest.main()
