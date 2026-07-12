#!/usr/bin/env python3
"""Minimal HTTP service — replace with your application."""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/health"):
            body = json.dumps({"status": "ok", "service": os.environ.get("APP_NAME", "myapp")})
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body.encode())
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt: str, *args: object) -> None:
        return  # quiet default access log in containers


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
