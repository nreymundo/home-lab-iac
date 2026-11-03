import json
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request


def idle_after_generation():
    with urllib.request.urlopen("http://127.0.0.1:8000/queue", timeout=5) as response:
        queue = json.load(response)
    if queue.get("queue_running") or queue.get("queue_pending"):
        return False
    with urllib.request.urlopen("http://127.0.0.1:8000/history", timeout=5) as response:
        history = json.load(response)
    latest = 0
    for item in history.values():
        status = item.get("status") or {}
        if not (status.get("completed") is True or status.get("status_str") == "success"):
            continue
        for message in status.get("messages") or []:
            if not isinstance(message, (list, tuple)) or len(message) < 2:
                continue
            if not isinstance(message[1], dict):
                continue
            timestamp = message[1].get("timestamp")
            if isinstance(timestamp, (int, float)):
                if timestamp > 10_000_000_000:
                    timestamp /= 1000
                latest = max(latest, timestamp)
    return bool(latest and time.time() - latest >= 60)


# Preserve the former timer policy; a fresh process clears history and GPU allocations.
process = subprocess.Popen([sys.executable, "/opt/ComfyUI/main.py", *sys.argv[1:]], cwd="/opt/ComfyUI")
stopping = False


def stop(signum, frame):
    global stopping
    stopping = True
    process.terminate()


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
while not stopping:
    try:
        sys.exit(process.wait(timeout=15))
    except subprocess.TimeoutExpired:
        pass
    try:
        if idle_after_generation():
            print("ComfyUI idle for 60 seconds after generation; releasing process memory", flush=True)
            stop(None, None)
    except (OSError, ValueError):
        pass
try:
    process.wait(timeout=30)
except subprocess.TimeoutExpired:
    process.kill()
    process.wait()
