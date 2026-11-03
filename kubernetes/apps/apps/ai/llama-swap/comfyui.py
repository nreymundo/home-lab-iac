import json
import os
import signal
import subprocess
import sys
import urllib.request


def main():
    stopping = False

    def stop(signum, frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    process = subprocess.Popen(["kubeswap", "serve", *sys.argv[2:]])
    queue_url = f"http://127.0.0.1:{int(sys.argv[1])}/queue"
    keepalive = urllib.request.Request(
        "http://127.0.0.1:8080/comfyui/queue",
        headers={"Authorization": f"Bearer {os.environ['LLAMA_SWAP_API_KEY']}"},
    )
    busy = False
    try:
        while not stopping and process.poll() is None:
            try:
                with urllib.request.urlopen(queue_url, timeout=5) as response:
                    queue = json.load(response)
                busy = bool(queue.get("queue_running") or queue.get("queue_pending"))
            except (OSError, ValueError):
                # A failed poll must not turn a known active queue into idle time.
                pass
            if busy and not stopping:
                try:
                    # Browser jobs outlive POST /prompt; WebSockets do not extend llama-swap's TTL.
                    with urllib.request.urlopen(keepalive, timeout=5) as response:
                        response.read()
                except OSError as error:
                    print(f"ComfyUI queue keepalive failed: {error}", flush=True)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
    finally:
        # Stop queue keepalives before deleting, so shutdown cannot request a new backend.
        try:
            subprocess.run(
                ["kubeswap", "delete", "--namespace", "ai-backends", "--model", "comfyui_auto", "--wait", "60s"],
                check=True,
                timeout=70,
            )
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    return 0 if stopping else process.returncode


if __name__ == "__main__":
    sys.exit(main())
