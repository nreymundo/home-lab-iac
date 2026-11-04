import logging
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, "/photon")
from src import index  # noqa: E402
from src.process_manager import PhotonManager  # noqa: E402
from src.utils.logger import setup_logging  # noqa: E402

DATA = Path("/photon/data")
ATTEMPT = DATA / ".photon-update-attempted"
FAILURE = DATA / ".photon-update-failed"
BACKUP = DATA / "photon_data.backup"
MONTH = 30 * 24 * 60 * 60
DAY = 24 * 60 * 60
MIN_FREE = 500 * 1024**3
logger = logging.getLogger(__name__)


def mtime(path):
    try:
        return path.stat().st_mtime
    except FileNotFoundError:
        return 0


def available_bytes():
    stats = os.statvfs(DATA)
    return stats.f_bavail * stats.f_frsize


class UpdateErrors(logging.Handler):
    def __init__(self):
        super().__init__(logging.WARNING)
        self.failed = False

    def emit(self, record):
        message = record.getMessage()
        if (
            "Update failed" in message
            or "Update run failed unexpectedly" in message
            or "Could not determine remote time" in message
        ):
            self.failed = True


class Metrics(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        metrics = (
            f"photon_index_updated_timestamp_seconds {index.last_updated()}\n"
            f"photon_update_attempt_timestamp_seconds {mtime(ATTEMPT)}\n"
            f"photon_update_failed {int(FAILURE.exists())}\n"
            f"photon_update_backup_present {int(BACKUP.exists())}\n"
            f"photon_data_available_bytes {available_bytes()}\n"
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(metrics)))
        self.end_headers()
        self.wfile.write(metrics)

    def log_message(self, format, *args):
        pass


class PersistentPhotonManager(PhotonManager):
    def schedule_updates(self):
        def loop():
            while not self.should_exit:
                try:
                    self.check_update()
                except Exception:
                    logger.exception("Photon update scheduling failed")
                for _ in range(60):
                    if self.should_exit:
                        return
                    time.sleep(1)

        threading.Thread(target=loop, daemon=True).start()

    def check_update(self):
        now = time.time()
        if now - index.last_updated() < MONTH or now - mtime(ATTEMPT) < DAY:
            return
        if BACKUP.exists():
            logger.error("Previous Photon backup remains; refusing another update")
            return
        if available_bytes() < MIN_FREE:
            logger.error("Photon update postponed: less than 500 GiB free on the node")
            return
        ATTEMPT.touch()
        FAILURE.touch()
        logger.info("Running restart-safe monthly Photon update")
        errors = UpdateErrors()
        logging.getLogger().addHandler(errors)
        try:
            self.run_update()
        finally:
            logging.getLogger().removeHandler(errors)
        if not errors.failed and not BACKUP.exists():
            FAILURE.unlink(missing_ok=True)


if __name__ == "__main__":
    setup_logging()
    server = ThreadingHTTPServer(("0.0.0.0", 2323), Metrics)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    PersistentPhotonManager().run()
