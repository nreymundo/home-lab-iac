"""SSE-to-PCM16 adapter for the audio.cpp Higgs streaming TTS lane.

Forwards OpenAI /v1/audio/speech requests to llama-swap with stream:true and
re-emits the SSE speech.audio.delta events as a chunked raw PCM16 body, which
the speech-to-speech OpenAI TTS backend consumes directly. Stdlib only.
"""

import base64
import json
import os

import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_HOST = os.environ.get("UPSTREAM_HOST", "llama-swap.external-proxy.svc.cluster.local")
UPSTREAM_PORT = int(os.environ.get("UPSTREAM_PORT", "8080"))
API_KEY = os.environ.get("LLAMA_SWAP_API_KEY", "")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/audio/speech":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            request = json.loads(self.rfile.read(length))
        except ValueError:
            self.send_error(400, "invalid JSON body")
            return
        request["stream"] = True

        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=600)
        try:
            conn.request(
                "POST",
                "/v1/audio/speech",
                body=json.dumps(request),
                headers={
                    "Content-Type": "application/json",
                    "Accept": "text/event-stream",
                    "Authorization": "Bearer " + API_KEY,
                },
            )
            resp = conn.getresponse()
        except OSError:
            self.send_error(502, "upstream connection failed")
            conn.close()
            return

        if resp.status != 200:
            body = resp.read()
            self.send_response(resp.status)
            self.send_header("Content-Type", resp.getheader("Content-Type", "text/plain"))
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            conn.close()
            return

        content_type = resp.getheader("Content-Type", "")
        self.send_response(200)
        if "text/event-stream" in content_type:
            self.send_header("Content-Type", "audio/L16; rate=24000")
        else:
            self.send_header("Content-Type", content_type)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        try:
            if "text/event-stream" in content_type:
                for raw_line in resp:
                    line = raw_line.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    payload = line[len("data:") :].strip()
                    if not payload or payload == "[DONE]":
                        continue
                    try:
                        event = json.loads(payload)
                    except ValueError:
                        continue
                    if event.get("type") != "speech.audio.delta":
                        continue
                    chunk = base64.b64decode(event.get("audio", ""))
                    if chunk:
                        self.wfile.write(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n")
            else:
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass  # client barge-in: connection closed mid-synthesis
        finally:
            conn.close()

    def log_message(self, format, *args):  # noqa: A002
        print("shim: " + format % args, flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8766), Handler)
    print(f"shim: listening on :8766, upstream {UPSTREAM_HOST}:{UPSTREAM_PORT}", flush=True)
    server.serve_forever()
