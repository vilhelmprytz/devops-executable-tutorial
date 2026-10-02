#!/usr/bin/env python3
# Deliberately vulnerable demo service for an authorised, self-contained lab.
# /ping?host=<x> passes x to a shell on purpose (command injection) so Falco can
# detect the resulting shell/file activity. The lab ends by fixing this (step 6).
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/healthz":
            return self._send(200, "ok\n")
        if u.path == "/ping":
            host = q.get("host", ["127.0.0.1"])[0]
            # VULNERABLE ON PURPOSE: user input flows straight into a shell.
            out = subprocess.run(
                f"ping -c1 {host}", shell=True,
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
