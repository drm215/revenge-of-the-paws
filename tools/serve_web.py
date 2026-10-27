"""Serves the web export (build/web) to phones on the same Wi-Fi, with caching off so a fresh
export shows up on reload.

Godot web builds only start in a secure context, so phones need HTTPS. With --https this uses a
self-signed certificate for this PC's LAN address (made with openssl on first run, kept in
build/cert); the phone shows a one-time "not private" warning that you tap through.

    godot --headless --path . --export-release "Web" build/web/index.html
    python tools/serve_web.py --https    # then open https://<this PC's IP>:8000 on the phone
"""
import http.server
import os
import socket
import ssl
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "build", "web")
CERT_DIR = os.path.join(HERE, "..", "build", "cert")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream"}

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def ensure_cert(ip):
    """Self-signed certificate valid for this PC's LAN IP (regenerated if the IP changes)."""
    os.makedirs(CERT_DIR, exist_ok=True)
    cert, key, stamp = (os.path.join(CERT_DIR, n) for n in ("cert.pem", "key.pem", "ip.txt"))
    if os.path.exists(cert) and os.path.exists(stamp) and open(stamp).read() == ip:
        return cert, key
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "825",
                    "-keyout", key, "-out", cert, "-subj", "/CN=Revenge of the Paws dev",
                    "-addext", "subjectAltName=IP:%s,IP:127.0.0.1,DNS:localhost" % ip],
                   check=True, capture_output=True)
    with open(stamp, "w") as f:
        f.write(ip)
    return cert, key


if __name__ == "__main__":
    use_https = "--https" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    port = int(args[0]) if args else 8000
    ip = lan_ip()
    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    if use_https:
        cert, key = ensure_cert(ip)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print("Open on your phone (same Wi-Fi): %s://%s:%d" % ("https" if use_https else "http", ip, port), flush=True)
    server.serve_forever()
