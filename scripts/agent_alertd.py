#!/usr/bin/env python3
"""Durable local alert daemon for Agent Pulse.

The protocol is intentionally tiny: one JSON request per Unix-socket line and
one JSON response. No network socket is opened.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shlex
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid
import re
from pathlib import Path
from typing import Any


APP_DIR = Path(os.environ.get("AGENT_PULSE_STATE", "~/.local/state/agent-pulse")).expanduser()
STATE_PATH = APP_DIR / "alerts.json"
SOCKET_PATH = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "agent-alertd.sock"
BOOT_ID_PATH = Path("/proc/sys/kernel/random/boot_id")


def now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat()


def parse_when(value: str) -> dt.datetime:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
    return parsed.astimezone(dt.timezone.utc)


def parse_after(value: str) -> dt.datetime:
    """Turn durations such as 90m or 1h30m into a due time."""
    normalized = value.lower().replace(" ", "")
    matches = re.findall(r"(\d+)([smhd])", normalized)
    if not matches or "".join(number + unit for number, unit in matches) != normalized:
        raise ValueError("duration must look like 30s, 90m, 2h, 1d, or 1h30m")
    seconds = sum(int(number) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit] for number, unit in matches)
    return now() + dt.timedelta(seconds=seconds)


def boot_id() -> str:
    try:
        return BOOT_ID_PATH.read_text().strip()
    except OSError:
        return "unknown"


class Store:
    def __init__(self, path: Path = STATE_PATH):
        self.path = path
        self.lock = threading.RLock()
        self.data = {"version": 1, "boot_id": boot_id(), "alerts": []}
        self.load()

    def load(self) -> None:
        with self.lock:
            try:
                self.data = json.loads(self.path.read_text())
            except (OSError, ValueError):
                self.data = {"version": 1, "boot_id": boot_id(), "alerts": []}
            self.data.setdefault("alerts", [])
            self.data["boot_id"] = boot_id()
            self.save()

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temp = self.path.with_suffix(".tmp")
        temp.write_text(json.dumps(self.data, indent=2, sort_keys=True) + "\n")
        os.replace(temp, self.path)

    def list(self) -> list[dict[str, Any]]:
        with self.lock:
            return [dict(item) for item in self.data["alerts"]]

    def add(self, alert: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            self.data["alerts"].append(alert)
            self.save()
            return dict(alert)

    def update(self, alert_id: str, **changes: Any) -> dict[str, Any] | None:
        with self.lock:
            for item in self.data["alerts"]:
                if item["id"] == alert_id:
                    item.update(changes)
                    self.save()
                    return dict(item)
        return None


def make_alert(args: argparse.Namespace) -> dict[str, Any]:
    trigger = "time" if args.when or args.after else args.trigger
    due = iso(parse_when(args.when)) if args.when else iso(parse_after(args.after)) if args.after else None
    return {
        "id": uuid.uuid4().hex[:12],
        "title": args.title,
        "message": args.message,
        "agent": args.agent or "generic",
        "trigger": trigger,
        "due": due,
        "boot_id": boot_id(),
        "resume_command": args.resume_command,
        "new_command": args.new_command,
        "status": "pending",
        "created": iso(now()),
        "fired": None,
        "acted": None,
    }


def command_for(alert: dict[str, Any], action: str) -> list[str] | None:
    value = alert.get("resume_command" if action == "resume" else "new_command")
    if not value:
        return None
    substitutions = {f"{{{key}}}": str(alert.get(key, "")) for key in ("id", "title", "message", "agent")}
    rendered = value
    for key, replacement in substitutions.items():
        rendered = rendered.replace(key, replacement)
    return shlex.split(rendered)


def notify(alert: dict[str, Any]) -> None:
    title = f"AGENT PULSE // {alert['title']}"
    message = alert["message"]
    try:
        subprocess.Popen(["notify-send", "-a", "Agent Pulse", "-u", "normal", title, message],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


class Daemon:
    def __init__(self, store: Store):
        self.store = store
        self.stop_event = threading.Event()
        self.last_wifi = False

    def wifi_connected(self) -> bool:
        try:
            result = subprocess.run(
                ["nmcli", "-t", "-f", "GENERAL.STATE", "device", "show"],
                capture_output=True, text=True, timeout=2, check=False,
            )
            return any(line.startswith("100") for line in result.stdout.splitlines())
        except (OSError, subprocess.SubprocessError):
            return False

    def fire(self, alert: dict[str, Any]) -> None:
        updated = self.store.update(alert["id"], status="fired", fired=iso(now()))
        if updated:
            notify(updated)

    def tick(self) -> None:
        current = now()
        wifi = self.wifi_connected()
        for alert in self.store.list():
            if alert.get("status") != "pending":
                continue
            trigger = alert.get("trigger")
            if trigger == "time" and alert.get("due") and current >= parse_when(alert["due"]):
                self.fire(alert)
            elif trigger == "boot" and alert.get("boot_id") != boot_id():
                self.fire(alert)
            elif trigger == "wifi" and wifi and not self.last_wifi:
                self.fire(alert)
        self.last_wifi = wifi

    def action(self, alert_id: str, action: str) -> dict[str, Any]:
        alert = next((item for item in self.store.list() if item["id"] == alert_id), None)
        if not alert:
            return {"ok": False, "error": "unknown alert"}
        command = command_for(alert, action)
        if not command:
            return {"ok": False, "error": f"no {action} command configured"}
        try:
            subprocess.Popen(command, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, ValueError) as error:
            return {"ok": False, "error": str(error)}
        updated = self.store.update(alert_id, acted=action, status="acted")
        return {"ok": True, "alert": updated}

    def request(self, request: dict[str, Any]) -> dict[str, Any]:
        operation = request.get("op", "status")
        if operation == "list":
            return {"ok": True, "alerts": self.store.list()}
        if operation == "status":
            pending = sum(item.get("status") == "pending" for item in self.store.list())
            return {"ok": True, "pending": pending, "socket": str(SOCKET_PATH)}
        if operation == "add":
            return {"ok": True, "alert": self.store.add(request["alert"])}
        if operation in {"ack", "dismiss"}:
            updated = self.store.update(request["id"], status="acknowledged" if operation == "ack" else "dismissed")
            return {"ok": bool(updated), "alert": updated}
        if operation in {"resume", "new"}:
            return self.action(request["id"], operation)
        return {"ok": False, "error": "unknown operation"}

    def serve_client(self, connection: socket.socket) -> None:
        with connection:
            line = connection.makefile("r").readline()
            try:
                response = self.request(json.loads(line))
            except (ValueError, KeyError, TypeError) as error:
                response = {"ok": False, "error": str(error)}
            connection.sendall((json.dumps(response) + "\n").encode())

    def run(self) -> None:
        SOCKET_PATH.parent.mkdir(parents=True, exist_ok=True)
        try:
            SOCKET_PATH.unlink()
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(SOCKET_PATH))
        os.chmod(SOCKET_PATH, 0o600)
        server.listen(8)
        server.settimeout(1)
        signal.signal(signal.SIGTERM, lambda *_: self.stop_event.set())
        signal.signal(signal.SIGINT, lambda *_: self.stop_event.set())
        try:
            while not self.stop_event.is_set():
                self.tick()
                try:
                    connection, _ = server.accept()
                    threading.Thread(target=self.serve_client, args=(connection,), daemon=True).start()
                except socket.timeout:
                    continue
        finally:
            server.close()
            try:
                SOCKET_PATH.unlink()
            except FileNotFoundError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", action="store_true")
    args = parser.parse_args()
    if not args.daemon:
        parser.error("the daemon is normally started by systemd; use agent-alertctl for requests")
    Daemon(Store()).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
