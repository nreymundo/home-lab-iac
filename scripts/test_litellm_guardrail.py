"""Guardrail regressions; run with the image selected by the LiteLLM HelmRelease."""

import asyncio
import copy
from contextlib import closing
import hashlib
import io
import json
import logging
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "kubernetes/apps/apps/ai/litellm/scripts"))
os.environ["GUARDRAIL_SECRETS_MODE"] = "redact"
os.environ["GUARDRAIL_SECRETS_JUDGE"] = "off"
os.environ.pop("GUARDRAIL_SECRETS_FINGERPRINTS", None)

import secrets_guardrail as g
import litellm
from litellm.caching.caching import DualCache
from litellm.proxy.utils import ProxyLogging
from litellm.types.utils import Delta, ModelResponseStream, StreamingChoices
from litellm.utils import async_pre_call_deployment_hook
from prometheus_client import REGISTRY, generate_latest

g._AUDIT_LOGGER.setLevel(logging.CRITICAL)
SECRET = "".join(chr(i) for i in (78, 55, 113, 88, 50, 109, 80, 57, 107, 82, 52, 119, 90, 54, 99, 84, 56))
OPAQUE = hashlib.sha256(b"synthetic-review-only").hexdigest()[:32]
REF = "process.env.SERVICE_TOKEN"
ASSIGN = "api_" + "key: "
BENIGN_REFERENCES = (
    REF, REF + "!", '"' + REF + '"', "'" + REF + "'", '"' + REF + '!"',
    REF + ' || ""', REF + ' ?? "not configured"', REF + ' + "-suffix"',
    REF + "!;", REF + ' ||\n ""', REF + '\n ?? "not configured"',
    '"' + REF + '" || ""', REF + ".toString()",
    'process.env["SERVICE_ACCESS"]', "process.env['SERVICE_ACCESS']",
    'process.env[ "SERVICE_ACCESS" ] ?? ""',
    'os.environ["SERVICE_ACCESS"]', "os.environ['SERVICE_ACCESS']",
    'os.getenv("SERVICE_ACCESS")', 'os.getenv("SERVICE_ACCESS", "")',
    'os.environ.get("SERVICE_ACCESS", "not configured")',
    'getenv("SERVICE_ACCESS")', 'System.getenv("SERVICE_ACCESS")',
    "config.credentials.accessToken", "settings.credentials.accessToken",
    "credentials.accessToken", "config.credentials.accessToken || null",
    "os.environ/DOCS_API_TOKEN", "env:DOCS_API_TOKEN", "${DOCS_API_TOKEN}",
    '"your-documentation-api-key"', '"example-api-key-here"', '"<YOUR_API_KEY>"',
    '"dummy-api-key-here"', '"sample-secret-value"', '"not-a-real-api-key"', '"placeholder-access-token"',
    "os.getenv('DATABASE_ACCESS', '')", "os.environ.get('DATABASE_ACCESS', None)",
    'process.env["DATABASE_ACCESS"]?.trim() ?? ""', 'settings.api.accessToken?.trim()',
    'config.credentials.accessToken ?? "not configured"', 'credentials.accessToken || ""',
    REF + ' || `not configured`', REF + ' || `${config.credentials.accessToken}`',
    REF + ' || `prefix-${config.credentials.accessToken}`',
)
FORMATS = {
    "anthropic": "sk-ant-" + SECRET,
    "openrouter": "sk-or-v1-" + SECRET,
    "openai": "sk-proj-" + SECRET + "A1B2C3D4",
    "bearer_token": "Bearer " + SECRET,
    "github": "ghp_" + SECRET,
    "aws": "AKIA" + "B7C8D9E2F3G4H5J6",
    "google": "AIza" + (SECRET * 3)[:35],
    "slack": "xoxb-" + SECRET,
    "gitlab": "glpat-" + SECRET,
    "groq": "gsk_" + SECRET,
    "sendgrid": "SG." + SECRET + "." + SECRET[::-1],
    "stripe": "sk_live_" + SECRET,
    "jwt": "eyJ" + SECRET + ".eyJ" + SECRET[::-1] + "." + SECRET,
    "telegram": "123456789:" + (SECRET * 3)[:35],
    "age_private_key": "AGE-" + "SECRET-" + "KEY-1" + (SECRET * 4)[:58],
    "private_key_block": "-----BEGIN " + "PRIVATE KEY-----\nfixture\n-----END " + "PRIVATE KEY-----",
    "credential_url": "postgres://user:" + SECRET + "@db.invalid",
}


def redact(text, fingerprints=None, judge=None):
    return g._redact_text(text, fingerprints or {}, judge)[0]


def guard():
    return g.SecretsObserverGuardrail(
        guardrail_name="secrets-observer", event_hook=["pre_call", "post_call"], default_on=True,
    )


async def drain():
    while g._JUDGE_TASKS:
        await asyncio.gather(*list(g._JUDGE_TASKS))


class ScannerTests(unittest.TestCase):
    def test_all_format_detectors(self):
        for label, text in FORMATS.items():
            with self.subTest(detector=label):
                self.assertIn(label, [m[2] for m in g._scan_text(text, {})])
                self.assertNotEqual(redact(text), text)

    def test_benign_reference_corpus(self):
        for index, expression in enumerate(BENIGN_REFERENCES):
            with self.subTest(case=index):
                text = ASSIGN + expression + ',\nother: "keep"'
                self.assertEqual(redact(text), text)

    def test_quoted_property_literal_is_not_exempt(self):
        for expression in ('"config.credentials.accessToken"', '"settings.credentials.accessToken"', "process.env.TOKENfoo"):
            with self.subTest(expression=expression):
                self.assertNotEqual(redact(ASSIGN + expression), ASSIGN + expression)

    def test_reference_defaults_and_concatenation(self):
        expressions = [
            REF + ' || "VALUE"', REF + ' + "VALUE"', REF + ' ||\n "VALUE"',
            '"' + REF + '" ?? "VALUE"', REF + ' || getValue("VALUE")',
            REF + ' + "-suffix" + "VALUE"',
            'process.env["SERVICE_ACCESS"] ?? "VALUE"',
            'os.getenv("SERVICE_ACCESS", "VALUE")',
            'os.environ.get("SERVICE_ACCESS", "VALUE")',
            'config.credentials.accessToken || "VALUE"',
            'settings.credentials.accessToken + "VALUE"',
            REF + ' || `VALUE`',
            REF + ' || `VALUE-${config.credentials.accessToken}`',
            REF + ' || `${config.credentials.accessToken}-VALUE`',
            REF + ' || `${config.credentials.accessToken ?? "VALUE"}`',
        ]
        for index, expression in enumerate(expressions):
            with self.subTest(case=index):
                clean = redact(ASSIGN + expression.replace("VALUE", SECRET))
                self.assertNotIn(SECRET, clean)
                self.assertIn("[REDACTED: sensitive_assignment]", clean)

    def test_expression_boundaries(self):
        for boundary in (', note: ', '; const note = ', '\nnote: '):
            text = ASSIGN + REF + boundary + '"' + SECRET + '"'
            with self.subTest(boundary=boundary):
                self.assertEqual(redact(text), text)

    def test_marker_fingerprint_precedence(self):
        for value in (SECRET, "abcdefghijklmnopqrstuvwxyz", REF):
            fingerprint = {"fixture": hashlib.sha256(value.encode()).digest()}
            for text in (value, "[REDACTED: " + value + "]", "ENC[AES256_GCM," + value + "]", ASSIGN + value):
                with self.subTest(value_length=len(value), wrapper=text[:8]):
                    self.assertNotIn(value, redact(text, fingerprint))

    def test_known_markers_are_idempotent(self):
        for label in (*FORMATS, "sensitive_assignment", "fingerprint:fixture"):
            text = ASSIGN + '"[REDACTED: ' + label + ']"'
            with self.subTest(label=label):
                self.assertEqual(redact(text), text)
        text = redact(ASSIGN + '"' + SECRET + '"')
        self.assertEqual(redact(text), text)

    def test_unknown_marker_cannot_hide_format(self):
        for prefix in ("[REDACTED: ", "[REDACTED: fingerprint:"):
            text = prefix + FORMATS["github"] + "]"
            self.assertNotIn(FORMATS["github"], redact(text))

    def test_placeholder_substrings_do_not_exempt_tokens(self):
        for word in ("example", "placeholder", "changeme", "dummy", "xxxxxx", "sample", "fake"):
            value = SECRET[:8] + word + SECRET[8:]
            for text in (ASSIGN + '"' + value + '"', "ghp_" + value, "sk-proj-" + value):
                with self.subTest(word=word, prefix=text[:5]):
                    self.assertNotIn(value, redact(text))

    def test_exact_published_and_masked_examples(self):
        examples = list(g._PUBLISHED_PLACEHOLDERS) + ["ghp_" + "x" * 36, "sk-proj-" + "x" * 32]
        for value in examples:
            with self.subTest(length=len(value)):
                self.assertEqual(redact(value), value)
                self.assertEqual(redact(ASSIGN + '"' + value + '"'), ASSIGN + '"' + value + '"')
                fingerprint = {"fixture": hashlib.sha256(value.encode()).digest()}
                self.assertNotEqual(redact(value, fingerprint), value)

    def test_reference_field_names_and_sops(self):
        for key in ("token_ref", "credential_name", "secret_id", "token_path", "api_key_url"):
            text = key + ': "' + SECRET + '"'
            self.assertEqual(redact(text), text)
            self.assertNotEqual(redact(key + ': "' + FORMATS["github"] + '"'), key + ': "' + FORMATS["github"] + '"')
        text = ASSIGN + '"ENC[AES256_GCM,data:opaque-data,iv:opaque,tag:opaque,type:str]"'
        self.assertEqual(redact(text), text)


class JudgeTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.judges = []
        self.text = ASSIGN + '"' + OPAQUE + '"'

    def make_judge(self, filename="judge.db", **kwargs):
        params = dict(db_path=str(Path(self.tmp.name) / filename), endpoint="http://judge.invalid/v1", auth="", model="d3-mini", timeout_s=30, cap=2)
        params.update(kwargs)
        judge = g._SpanJudge(**params)
        self.judges.append(judge)
        return judge

    async def asyncTearDown(self):
        await drain()
        for judge in self.judges:
            if judge._candidates:
                g._metric(g._JUDGE_QUEUED, "dec", len(judge._candidates))
            if judge._db:
                judge._db.close()

    async def classify(self, judge, response="PASS", text=None):
        with patch.object(g, "_judge_http", return_value=response) as http:
            clean = redact(text or self.text, judge=judge)
            judge.schedule()
            await drain()
        return clean, http

    async def test_first_request_redacts_then_cached_pass(self):
        judge = self.make_judge()
        clean, http = await self.classify(judge, "  pass\n")
        self.assertNotIn(OPAQUE, clean)
        self.assertEqual(redact(self.text, judge=judge), self.text)
        self.assertEqual(judge.schedule(), 0)
        self.assertEqual(http.call_count, 1)

    async def test_cached_redact_is_final_until_expiry(self):
        judge = self.make_judge()
        await self.classify(judge, "REDACT")
        with patch.object(g, "_judge_http", return_value="PASS") as http:
            for _ in range(3):
                self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
                judge.schedule()
                await drain()
            http.assert_not_called()

    async def test_strict_responses(self):
        for index, response in enumerate(("Do not PASS", "PASS or REDACT", "", "PASS.", "```PASS```", None, 7)):
            with self.subTest(case=index):
                judge = self.make_judge(filename=str(index) + ".db")
                await self.classify(judge, response)
                self.assertFalse(judge._overlay)
                self.assertNotIn(OPAQUE, redact(self.text, judge=judge))

    async def test_scope_changes_require_new_verdict(self):
        judge = self.make_judge()
        await self.classify(judge)
        self.assertEqual(redact(self.text + "\nnew turn", judge=judge), self.text + "\nnew turn")
        for text in ("Production credential: " + self.text, "Production credential:\n" + self.text, self.text + " // production"):
            with self.subTest(context=text[:12]):
                self.assertNotIn(OPAQUE, redact(text, judge=judge))
        for options in ({"model": "new-model"}, {"version": "new-policy"}, {"endpoint": "http://other.invalid/v1"}):
            other = self.make_judge(**options)
            self.assertNotIn(OPAQUE, redact(self.text, judge=other))

    async def test_fingerprints_and_formats_never_judged(self):
        judge = self.make_judge()
        await self.classify(judge)
        fp = {"fixture": hashlib.sha256(OPAQUE.encode()).digest()}
        self.assertNotIn(OPAQUE, redact(self.text, fp, judge))
        with patch.object(g, "_judge_http", return_value="PASS") as http:
            for text in FORMATS.values():
                self.assertNotEqual(redact(text, judge=judge), text)
            judge.schedule()
            await drain()
            http.assert_not_called()

    async def test_restart_and_storage_hygiene(self):
        judge = self.make_judge()
        await self.classify(judge)
        restarted = self.make_judge()
        self.assertEqual(redact(self.text, judge=restarted), self.text)
        for file in Path(self.tmp.name).iterdir():
            self.assertNotIn(OPAQUE.encode(), file.read_bytes())
            self.assertNotIn(ASSIGN.encode(), file.read_bytes())
        self.assertEqual(len(judge._db.execute("SELECT * FROM scoped_verdicts").fetchall()), 1)

    async def test_expiry_pass_and_redact(self):
        for verdict, ttl in (("PASS", 10), ("REDACT", 20)):
            judge = self.make_judge(filename=verdict + ".db", pass_ttl_s=10, redact_ttl_s=20)
            await self.classify(judge, verdict)
            now = time.time()
            with patch.object(g.time, "time", return_value=now + ttl + 1):
                self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
                self.assertFalse(judge._overlay)
                restarted = self.make_judge(filename=verdict + ".db")
                self.assertFalse(restarted._overlay)

    async def test_legacy_global_verdict_is_invalidated(self):
        path = Path(self.tmp.name) / "judge.db"
        with closing(sqlite3.connect(path)) as db:
            with db:
                db.execute("CREATE TABLE verdicts (digest TEXT, verdict TEXT)")
                db.execute("INSERT INTO verdicts VALUES (?, 'pass')", (g._span_digest(OPAQUE),))
        judge = self.make_judge()
        self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
        self.assertIsNone(judge._db.execute("SELECT name FROM sqlite_master WHERE name='verdicts'").fetchone())

    async def test_slow_judge_does_not_delay_requests_and_drains_queue(self):
        judge = self.make_judge(cap=2)
        entered = threading.Event()
        release = threading.Event()
        count = 0
        peak = 0
        lock = threading.Lock()

        def slow(*args):
            nonlocal count, peak
            with lock:
                count += 1
                peak = max(peak, count)
            if count == 2:
                entered.set()
            release.wait(5)
            with lock:
                count -= 1
            return "REDACT"

        with patch.object(g, "_judge_http", side_effect=slow) as http:
            for index in range(8):
                redact(self.text + f" // case {index}", judge=judge)
                judge.schedule()
            try:
                self.assertTrue(await asyncio.to_thread(entered.wait, 2))
                started = time.monotonic()
                for _ in range(10):
                    self.assertNotIn(OPAQUE, redact(self.text + " // case 0", judge=judge))
                    judge.schedule()
                self.assertLess(time.monotonic() - started, 0.5)
                self.assertLessEqual(len(judge._inflight), 2)
                self.assertEqual(len(judge._candidates), 6)
            finally:
                release.set()
            await drain()
        self.assertEqual(http.call_count, 8)
        self.assertEqual(peak, 2)
        self.assertFalse(judge._candidates)

    async def test_queue_cap_age_and_oversize(self):
        judge = self.make_judge()
        with patch.object(g, "_JUDGE_QUEUE_CAP", 3):
            for i in range(12):
                redact(self.text + str(i), judge=judge)
            self.assertEqual(len(judge._candidates), 3)
        judge._prune(time.monotonic() + g._JUDGE_QUEUE_TTL_S + 1)
        self.assertFalse(judge._candidates)
        judge.collect("sensitive_assignment", "A" * (g._JUDGE_MAX_SPAN + 1), "", "")
        self.assertFalse(judge._candidates)

    async def test_timeout_backoff_pause_and_recovery(self):
        judge = self.make_judge(cap=1)
        with patch.object(g, "_judge_http", side_effect=TimeoutError) as http:
            for i in range(3):
                text = self.text + str(i)
                redact(text, judge=judge)
                judge.schedule()
                await drain()
                redact(text, judge=judge)
                judge.schedule()
            self.assertEqual(http.call_count, 3)
            self.assertGreater(judge._paused_until, time.monotonic())
            self.assertFalse(judge._overlay)
        judge._paused_until = time.monotonic() - 1
        judge._backoff = type(judge._backoff)((key, time.monotonic() - 1) for key in judge._backoff)
        await self.classify(judge, "REDACT")
        self.assertFalse(judge._backoff)

    async def test_database_failure_stays_redacted_and_observable(self):
        judge = self.make_judge()
        with patch.object(judge, "_store", side_effect=sqlite3.OperationalError("synthetic sensitive failure")):
            with self.assertLogs(g._AUDIT_LOGGER, level="INFO") as logs:
                await self.classify(judge)
        self.assertFalse(judge._overlay)
        self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
        self.assertIn("store_error", " ".join(logs.output))
        self.assertNotIn("verdict recorded", " ".join(logs.output))
        self.assertNotIn("synthetic sensitive failure", " ".join(logs.output))

    async def test_slow_database_does_not_block_request_thread(self):
        judge = self.make_judge()
        release = threading.Event()
        entered = threading.Event()
        store = judge._store

        def slow(*args):
            entered.set()
            release.wait(5)
            store(*args)

        with patch.object(judge, "_store", side_effect=slow), patch.object(g, "_judge_http", return_value="PASS"):
            redact(self.text, judge=judge)
            judge.schedule()
            try:
                self.assertTrue(await asyncio.to_thread(entered.wait, 2))
                self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
                self.assertFalse(judge._overlay)
            finally:
                release.set()
            await drain()
        self.assertEqual(redact(self.text, judge=judge), self.text)

    async def test_storage_and_backoff_caps(self):
        judge = self.make_judge()
        with patch.object(g, "_JUDGE_OVERLAY_CAP", 3):
            for i in range(6):
                await self.classify(judge, text=self.text + str(i))
            self.assertLessEqual(len(judge._overlay), 3)
            self.assertLessEqual(judge._db.execute("SELECT COUNT(*) FROM scoped_verdicts").fetchone()[0], 3)
            with patch.object(g, "_judge_http", side_effect=TimeoutError):
                for i in range(6):
                    judge._paused_until = 0
                    redact(self.text + " failure " + str(i), judge=judge)
                    judge.schedule()
                    await drain()
            self.assertLessEqual(len(judge._backoff), 3)

    async def test_unavailable_store_and_invalid_settings(self):
        judge = self.make_judge(db_path=self.tmp.name)
        self.assertFalse(judge.ready)
        self.assertNotIn(OPAQUE, redact(self.text, judge=judge))
        self.assertEqual(judge.schedule(), 0)
        for value in (0, -1, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.make_judge(pass_ttl_s=value)

    async def test_environment_configuration_and_modes(self):
        settings = {
            "GUARDRAIL_SECRETS_JUDGE": "async",
            "GUARDRAIL_SECRETS_JUDGE_DB": str(Path(self.tmp.name) / "configured.db"),
            "GUARDRAIL_SECRETS_JUDGE_ENDPOINT": "http://judge.invalid/v1",
            "GUARDRAIL_SECRETS_JUDGE_PASS_TTL": "120",
            "GUARDRAIL_SECRETS_JUDGE_REDACT_TTL": "240",
            "GUARDRAIL_SECRETS_JUDGE_VERSION": "model-revision-2",
        }
        with patch.dict(os.environ, settings):
            instance = guard()
            judge = instance._judge
            self.judges.append(judge)
            self.assertEqual(judge._ttls, {"pass": 120, "redact": 240})
            self.assertEqual(judge._version, g._JUDGE_POLICY_VERSION + ":model-revision-2")
            for mode in ("observe", "off"):
                with patch.dict(os.environ, {"GUARDRAIL_SECRETS_MODE": mode}):
                    self.assertIsNone(guard()._judge)
            with patch.dict(os.environ, {"GUARDRAIL_SECRETS_JUDGE_PASS_TTL": "invalid"}):
                self.assertIsNone(guard()._judge)

    async def test_judge_uses_only_bounded_context_as_data(self):
        judge = self.make_judge()
        text = "earlier conversation\n" + "untrusted " * 100 + "\n" + self.text + "\nlater conversation"
        _, http = await self.classify(judge, text=text)
        state = json.loads(http.call_args.args[3])
        self.assertEqual(state["value"], OPAQUE)
        self.assertLessEqual(len(state["before"]), g._JUDGE_RADIUS)
        self.assertLessEqual(len(state["after"]), g._JUDGE_RADIUS)
        self.assertNotIn("earlier conversation", state["before"])
        self.assertNotIn("later conversation", state["after"])

    async def test_real_hooks_use_cached_judgment_on_replay(self):
        judge = self.make_judge()
        instance = guard()
        instance._judge = judge
        with patch.object(g, "_judge_http", return_value="PASS") as http:
            first = {"model": "cloud/general", "input": self.text}
            await instance.async_pre_call_hook(None, None, first, "responses")
            self.assertNotIn(OPAQUE, first["input"])
            await drain()
            replay = {"model": "cloud/general", "input": self.text}
            await instance.async_pre_call_hook(None, None, replay, "responses")
            self.assertEqual(replay["input"], self.text)
            await instance.async_pre_call_deployment_hook(replay, "responses")
            self.assertEqual(replay["input"], self.text)
            self.assertEqual(http.call_count, 1)

    async def test_success_metrics_and_failure_metrics(self):
        def events(outcome):
            return REGISTRY.get_sample_value("litellm_secrets_judge_events_total", {"outcome": outcome}) or 0

        judge = self.make_judge()
        passed = events("pass")
        errors = events("judge_error")
        await self.classify(judge)
        await self.classify(judge, "invalid", text=self.text + " changed")
        self.assertEqual(events("pass"), passed + 1)
        self.assertEqual(events("judge_error"), errors + 1)
        self.assertEqual(REGISTRY.get_sample_value("litellm_secrets_judge_inflight"), 0)
        self.assertFalse(judge._inflight)


class MetricsTests(unittest.TestCase):
    def test_multiprocess_scrape_exports_custom_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, PROMETHEUS_MULTIPROC_DIR=directory)
            env["PYTHONPATH"] = str(ROOT / "kubernetes/apps/apps/ai/litellm/scripts")
            source = """
import secrets_guardrail as g
from prometheus_client import CollectorRegistry, generate_latest, multiprocess
g._judge_event('pass')
g._JUDGE_LATENCY.labels(outcome='pass').observe(3)
g._JUDGE_QUEUED.inc(2)
g._SCAN_FAILURES.inc()
registry = CollectorRegistry()
multiprocess.MultiProcessCollector(registry)
print(generate_latest(registry).decode())
"""
            output = subprocess.check_output([sys.executable, "-c", source], env=env, text=True)
            self.assertIn('litellm_secrets_judge_events_total{outcome="pass"} 1.0', output)
            self.assertIn('litellm_secrets_judge_duration_seconds_sum{outcome="pass"} 3.0', output)
            self.assertIn('litellm_secrets_judge_queued 2.0', output)
            self.assertIn('litellm_secrets_scan_failures_total 1.0', output)


class HttpTests(unittest.TestCase):
    def test_native_decisions_contract(self):
        response = {"answers": {"verdict": {"type": "choice", "choice": "PASS"}}}
        for endpoint in ("http://judge.invalid", "http://judge.invalid/v1", "http://judge.invalid/v1/"):
            with patch.object(g.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())) as http:
                self.assertEqual(g._judge_http(endpoint, "test-auth", "d3-mini", "synthetic context", 30), "PASS")
                request = http.call_args.args[0]
                body = json.loads(request.data)
                self.assertEqual(request.full_url, "http://judge.invalid/v1/systemone")
                self.assertEqual(body["state"], "synthetic context")
                self.assertEqual(body["model"], "d3-mini")
                self.assertEqual(body["questions"]["verdict"]["type"], "choice")
                self.assertEqual(set(body["questions"]["verdict"]["criteria"]), {"PASS", "REDACT"})
                self.assertEqual(request.get_header("Authorization"), "Bearer test-auth")
                self.assertEqual(http.call_args.kwargs["timeout"], 30)
                self.assertNotIn("messages", body)

    def test_malformed_responses(self):
        for response in ({}, [], {"answers": []}, {"answers": {"verdict": None}}, {"answers": {"verdict": {"choice": "PASS"}}}, {"answers": {"verdict": {"type": "score", "choice": "PASS"}}}, {"answers": {"verdict": {"type": "choice", "choice": 1}}}):
            with patch.object(g.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(response).encode())):
                self.assertEqual(g._judge_http("http://judge.invalid/v1", "", "d3-mini", "fixture", 30), "")


class LifecycleTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        g._SEEN_SPANS.clear()
        g._CALL_STATES.clear()
        g._CALL_STATE.set(None)
        self.guard = guard()

    async def test_payload_surfaces(self):
        cases = [
            ("messages", [{"role": "user", "content": ASSIGN + '"' + SECRET + '"'}]),
            ("messages", [{"role": "assistant", "tool_calls": [{"function": {"name": "probe", "arguments": json.dumps({"api_key": SECRET})}}]}]),
            ("input", [{"type": "function_call_output", "output": json.dumps({"api_key": SECRET})}]),
            ("state", {"description": FORMATS["github"]}),
            ("questions", {"question": {"instructions": FORMATS["github"]}}),
        ]
        cases.extend((root, FORMATS["github"]) for root in g._CONTENT_ROOTS)
        for root, value in cases:
            with self.subTest(root=root):
                data = {"model": "cloud/general", root: copy.deepcopy(value)}
                await self.guard.async_pre_call_hook(None, None, data, "completion")
                self.assertNotIn(SECRET, json.dumps(data))

    async def test_binary_skip_but_structured_data_scanned(self):
        for kind in ("input_image", "input_audio", "input_file"):
            value = {"type": kind, "data": FORMATS["github"]}
            self.assertEqual(g._redact_value(value, {})[0], value)
        value = {"type": "text", "data": FORMATS["github"]}
        self.assertNotEqual(g._redact_value(value, {})[0], value)

    async def test_local_exemption_and_cloud_fallback(self):
        for model in ("local/decision", "hosted_vllm/d3-mini"):
            data = {"model": model, "state": FORMATS["github"]}
            await self.guard.async_pre_call_hook(None, None, data, "decisions")
            self.assertEqual(data["state"], FORMATS["github"])
            data["api_base"] = "https://cloud.invalid/v1"
            with patch.object(litellm, "callbacks", [self.guard]):
                data = await async_pre_call_deployment_hook(data, "decisions")
            self.assertNotIn(SECRET, json.dumps(data))

    async def test_native_ingress_blocks_scanner_failure(self):
        proxy = ProxyLogging(DualCache())
        data = {"model": "cloud/general", "messages": [{"role": "user", "content": FORMATS["github"]}]}
        with patch.object(g, "_scan_text", side_effect=RuntimeError(SECRET)):
            with self.assertRaises(g.HTTPException) as caught:
                await proxy._run_sequential_guardrail_callback(self.guard, data, None, None, "completion")
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn(SECRET, str(caught.exception))

    async def test_native_deployment_blocks_scanner_failure(self):
        data = {"model": "local/decision", "api_base": "https://cloud.invalid/v1", "state": FORMATS["github"]}
        with patch.object(litellm, "callbacks", [self.guard]), patch.object(g, "_scan_text", side_effect=RuntimeError(SECRET)):
            with self.assertRaises(g.HTTPException) as caught:
                await async_pre_call_deployment_hook(data, "decisions")
        self.assertEqual(caught.exception.status_code, 503)

    async def test_partial_scan_failure_cannot_forward(self):
        original = g._scan_text
        calls = 0

        def fail_second(*args):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise RuntimeError("fixture")
            return original(*args)

        data = {"model": "cloud/general", "input": FORMATS["github"], "state": FORMATS["github"]}
        with patch.object(g, "_scan_text", side_effect=fail_second), self.assertRaises(g.HTTPException):
            self.guard._process(data, "ingress")

    async def test_observe_off_and_local_keep_their_policy(self):
        for mode, model in (("off", "cloud/general"), ("observe", "cloud/general"), ("redact", "local/decision")):
            self.guard._mode = mode
            data = {"model": model, "state": FORMATS["github"]}
            with patch.object(g, "_scan_text", side_effect=RuntimeError(SECRET)):
                await self.guard.async_pre_call_hook(None, None, data, "decisions")
            self.assertEqual(data["state"], FORMATS["github"])

    async def test_judge_scheduling_and_reporting_failures_keep_redaction(self):
        judge = Mock(passed=0)
        judge.lookup.return_value = None
        judge.schedule.side_effect = RuntimeError("fixture")
        self.guard._judge = judge
        data = {"model": "cloud/general", "input": ASSIGN + '"' + SECRET + '"'}
        with patch.object(self.guard, "add_standard_logging_guardrail_information_to_request_data", side_effect=RuntimeError("fixture")):
            await self.guard.async_pre_call_hook(None, None, data, "completion")
        self.assertNotIn(SECRET, json.dumps(data))

    async def test_direct_apply_mutates_caller_texts(self):
        texts = [FORMATS["github"]]
        await self.guard.apply_guardrail({"texts": texts}, {"model": "cloud/general"}, "request")
        self.assertNotIn(SECRET, json.dumps(texts))

    async def test_notices_and_headers_remain_idempotent(self):
        data = {"model": "cloud/general", "messages": [{"role": "user", "content": FORMATS["github"]}]}
        await self.guard.async_pre_call_hook(None, None, data, "completion")
        await self.guard.async_pre_call_deployment_hook(data, "completion")
        headers = await self.guard.async_post_call_response_headers_hook(data, None, None)
        self.assertEqual(headers["X-LiteLLM-Secrets-Guardrail"], "redacted")
        response = {"choices": [{"message": {"content": "answer"}}]}
        await self.guard.async_post_call_success_hook(data, None, response)
        await self.guard.async_post_call_success_hook(data, None, response)
        self.assertEqual(response["choices"][0]["message"]["content"].count("Notice:"), 1)

    async def test_responses_and_streaming_notices(self):
        data = {"model": "cloud/general", "input": FORMATS["github"]}
        await self.guard.async_pre_call_hook(None, None, data, "responses")
        response = {"output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "answer"}]}]}
        await self.guard.async_post_call_success_hook(data, None, response)
        self.assertIn("Notice:", response["output"][0]["content"][0]["text"])

        async def chunks():
            for text in ("", "first", "second"):
                yield ModelResponseStream(choices=[StreamingChoices(delta=Delta(content=text))])

        output = [chunk async for chunk in self.guard.async_post_call_streaming_iterator_hook(None, chunks(), data)]
        content = "".join(chunk.choices[0].delta.content for chunk in output)
        self.assertEqual(content.count("Notice:"), 1)
        self.assertTrue(content.endswith("firstsecond"))

    async def test_logs_and_metrics_do_not_contain_content(self):
        data = {"model": "cloud/general", "input": FORMATS["github"]}
        with self.assertLogs(g._AUDIT_LOGGER, level="INFO") as logs:
            await self.guard.async_pre_call_hook(None, None, data, "completion")
        self.assertNotIn(SECRET, " ".join(logs.output))
        metrics = generate_latest(REGISTRY).decode()
        self.assertIn("litellm_secrets_scan_failures_total", metrics)
        self.assertIn("litellm_secrets_judge_queued", metrics)
        self.assertNotIn(SECRET, metrics)
        self.assertNotIn(OPAQUE, metrics)
        self.assertNotIn(g._span_digest(OPAQUE), metrics)


if __name__ == "__main__":
    unittest.main(verbosity=2)
