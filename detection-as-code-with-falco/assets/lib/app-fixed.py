#!/usr/bin/env python3
# Patched netcheck service: the /ping handler no longer builds a shell command
# from user input. It validates the host and passes ping an argv list (no shell).
import re
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

HOST_RE = re.compile(r"^[A-Za-z0-9.-]+$")   # hostnames / IPv4 only; no shell metachars


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/healthz":
            return self._send(200, "ok\n")
        if u.path == "/ping":
            host = q.get("host", ["127.0.0.1"])[0]
            if not HOST_RE.match(host):
                return self._send(400, "invalid host\n")
            # FIXED: argv list, no shell=True -> user input can't become a command.
            out = subprocess.run(
                ["ping", "-c1", host],
                capture_output=True, text=True, timeout=10,
            )
            return self._send(200, out.stdout + out.stderr)
        self._send(404, "not found\n")

    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
