#!/usr/bin/env python3
"""CLI client for the Agent Pulse local alert daemon."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import socket
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from agent_alertd import SOCKET_PATH, iso, make_alert


def call(payload: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5)
        client.connect(str(SOCKET_PATH))
        client.sendall((json.dumps(payload) + "\n").encode())
        return json.loads(client.makefile("r").readline())


def main() -> int:
    parser = argparse.ArgumentParser(description="Create and control local Agent Pulse alerts")
    sub = parser.add_subparsers(dest="operation", required=True)
    add = sub.add_parser("add", help="create a durable alert")
    add.add_argument("--title", required=True)
    add.add_argument("--message", required=True)
    when = add.add_mutually_exclusive_group(required=True)
    when.add_argument("--when", help="ISO-8601 timestamp")
    when.add_argument("--after", help="relative duration such as 90m, 2h, or 1h30m")
    when.add_argument("--on", dest="trigger", choices=("boot", "wifi"))
    add.add_argument("--agent", default="generic")
    add.add_argument("--resume-command")
    add.add_argument("--new-command")
    for name in ("list", "status"):
        sub.add_parser(name)
    for name in ("ack", "dismiss", "resume", "new"):
        cmd = sub.add_parser(name)
        cmd.add_argument("id")
    args = parser.parse_args()
    if args.operation == "add":
        alert = make_alert(args)
        result = call({"op": "add", "alert": alert})
    elif args.operation in {"list", "status"}:
        result = call({"op": args.operation})
    else:
        result = call({"op": args.operation, "id": args.id})
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
