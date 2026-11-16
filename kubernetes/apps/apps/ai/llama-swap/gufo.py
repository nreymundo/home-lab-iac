import http.client
import json
import signal
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


port = int(sys.argv[1])
backend_port = port + 20000
args = sys.argv[2:]
listen = args.index("--listen") + 1
args[listen] = f"127.0.0.1:{backend_port}"


def translate(path, body):
    if path not in {
        "/v1/responses", "/v/responses", "/v1/responses/input_tokens",
        "/v1/completions", "/v/completions", "/completion",
        "/v1/messages", "/v1/messages/count_tokens",
    }:
        return body
    data = json.loads(body)
    effort = data.pop("reasoning_effort", None)
    if path in {"/v1/responses", "/v/responses", "/v1/responses/input_tokens"}:
        if effort is not None:
            reasoning = data.get("reasoning") or {}
            reasoning["effort"] = effort
            data["reasoning"] = reasoning
        default_limit = data.pop("max_tokens", None)
        if default_limit is not None:
            data.setdefault("max_output_tokens", default_limit)
    elif path in {"/v1/messages", "/v1/messages/count_tokens"}:
        if effort == "none":
            data["thinking"] = {"type": "disabled"}
        elif effort is not None:
            output_config = data.get("output_config") or {}
            output_config["effort"] = effort
            data["output_config"] = output_config
    elif path == "/completion":
        default_limit = data.pop("max_tokens", None)
        if default_limit is not None:
            data.setdefault("n_predict", default_limit)
    return json.dumps(data, separators=(",", ":")).encode()


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def forward(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        path = self.path.split("?", 1)[0]
        if body and "application/json" in self.headers.get("Content-Type", ""):
            try:
                body = translate(path, body)
            except (ValueError, TypeError):
                self.send_error(400, "Invalid request body")
                return
        headers = {key: value for key, value in self.headers.items() if key.lower() not in {
            "connection", "content-length", "host", "transfer-encoding"
        }}
        if body:
            headers["Content-Length"] = str(len(body))
        connection = http.client.HTTPConnection("127.0.0.1", backend_port, timeout=None)
        try:
            connection.request(self.command, self.path, body=body if body else None, headers=headers)
            response = connection.getresponse()
            self.send_response_only(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "keep-alive"}:
                    self.send_header(key, value)
            self.send_header("Connection", "close")
            self.end_headers()
            while chunk := response.read1(65536):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        except OSError as error:
            print(f"Gufo proxy error: {error}", file=sys.stderr, flush=True)
        finally:
            connection.close()
            self.close_connection = True

    do_GET = forward
    do_POST = forward


server = ThreadingHTTPServer(("127.0.0.1", port), Proxy)
server.daemon_threads = True
process = subprocess.Popen(["kubeswap", "serve", *args])


def stop(signum, frame):
    if process.poll() is None:
        process.terminate()


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    exit_code = process.wait()
finally:
    server.shutdown()
    server.server_close()
    thread.join()
sys.exit(exit_code)
