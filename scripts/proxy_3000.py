#!/usr/bin/env python3
import http.server
import urllib.request
import urllib.error
import socketserver
import sys

TARGET_PORT = 56500
LISTEN_PORT = 3000

class ProxyHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.proxy_request('GET')

    def do_POST(self):
        self.proxy_request('POST')

    def do_PUT(self):
        self.proxy_request('PUT')

    def do_DELETE(self):
        self.proxy_request('DELETE')

    def do_HEAD(self):
        self.proxy_request('HEAD')

    def do_OPTIONS(self):
        self.proxy_request('OPTIONS')

    def proxy_request(self, method):
        target_url = f"http://127.0.0.1:{TARGET_PORT}{self.path}"
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        req = urllib.request.Request(target_url, data=body, method=method)
        for key, val in self.headers.items():
            if key.lower() not in ['host', 'connection']:
                req.add_header(key, val)

        try:
            with urllib.request.urlopen(req) as resp:
                self.send_response(resp.status)
                for key, val in resp.getheaders():
                    if key.lower() not in ['transfer-encoding', 'connection']:
                        self.send_header(key, val)
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for key, val in e.headers.items():
                if key.lower() not in ['transfer-encoding', 'connection']:
                    self.send_header(key, val)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(e).encode())

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(("", LISTEN_PORT), ProxyHTTPRequestHandler) as httpd:
            print(f"Proxying port {LISTEN_PORT} -> {TARGET_PORT}")
            httpd.serve_forever()
    except Exception as e:
        print(f"Proxy error: {e}")
