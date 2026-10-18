"""Observe likely secrets in provider-bound LiteLLM request content."""

from __future__ import annotations

import hashlib
import json
import logging
import math
import os
import re
import time
from collections import Counter
from collections.abc import Iterable
from typing import Any
from urllib.parse import urlsplit

from litellm.integrations.custom_guardrail import CustomGuardrail
from litellm.proxy.common_utils.callback_utils import (
    add_guardrail_to_applied_guardrails_header,
)


logger = logging.getLogger("LiteLLM Proxy")
_SOPS_CIPHERTEXT = re.compile(r"ENC\[AES256_GCM,[^\]\r\n]*\]")
_CANDIDATE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_./+=-]{14,}[A-Za-z0-9+/=]")
_ASSIGNMENT = re.compile(
    r"(?i)(?<![A-Za-z0-9_])(?P<key>[A-Za-z_][A-Za-z0-9_-]*)"
    r"\s*(?:=|:)\s*(?P<value>\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,}\]]+)"
)
_ENV_NAME_SEGMENTS = {
    "ACCESS",
    "CRED",
    "CREDENTIAL",
    "CREDENTIALS",
    "KEY",
    "PASSWD",
    "PASSWORD",
    "PAT",
    "SECRET",
    "TOKEN",
}
_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("anthropic", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{16,}\b")),
    ("openrouter", re.compile(r"\bsk-or-v1-[A-Za-z0-9_-]{16,}\b")),
    ("openai", re.compile(r"\bsk-(?!or-v1-)(?:proj-)?[A-Za-z0-9_-]{20,}\b")),
    ("bearer_token", re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]{16,}={0,2}")),
    ("github", re.compile(r"\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{16,}\b")),
    ("aws", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("google", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("slack", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{16,}\b")),
    ("gitlab", re.compile(r"\bglpat-[A-Za-z0-9_-]{16,}\b")),
    ("groq", re.compile(r"\bgsk_[A-Za-z0-9_-]{16,}\b")),
    ("sendgrid", re.compile(r"\bSG\.[\w-]{16,}\.[\w-]{16,}\b")),
    ("stripe", re.compile(r"\b(?:sk_live_|rk_live_)[A-Za-z0-9]{16,}\b")),
    (
        "jwt",
        re.compile(r"\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"),
    ),
    ("telegram", re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{35}\b")),
    ("age_private_key", re.compile(r"\bAGE-SECRET-KEY-1[0-9A-Za-z]{58}\b")),
    (
        "private_key_block",
        re.compile(
            r"-----BEGIN (?P<label>(?:(?:RSA|EC|DSA|OPENSSH|PGP|ENCRYPTED) )?"
            r"PRIVATE KEY(?: BLOCK)?)-----[\s\S]*?-----END (?P=label)-----"
        ),
    ),
    (
        "credential_url",
        re.compile(
            r"\b(?:postgres(?:ql)?|redis|https?|mysql|mariadb|mongodb(?:\+srv)?|amqps?|ftp)"
            r"://[^\s/@:]*:[^\s/@]+@"
        ),
    ),
)
_CONTENT_ROOTS = (
    "messages",
    "input",
    "instructions",
    "tools",
    "state",
    "questions",
    "query",
    "instruction",
    "documents",
    "prompt",
    "negative_prompt",
)
_NON_TEXT_KEYS = {
    "audio",
    "call_id",
    "data",
    "file_id",
    "id",
    "image",
    "image_url",
    "role",
    "type",
    "video",
}
_LOCAL_MODEL_PREFIXES = ("local/", "hosted_vllm/")


def _safe_log(level: int, message: str, *args: Any) -> None:
    try:
        logger.log(level, message, *args)
    except Exception:
        pass


def _load_fingerprints(raw: str | None) -> dict[str, bytes]:
    if not raw:
        return {}
    try:
        decoded = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        _safe_log(logging.WARNING, "Secrets observer fingerprint configuration is invalid; tier disabled")
        return {}
    if not isinstance(decoded, dict):
        _safe_log(logging.WARNING, "Secrets observer fingerprint configuration is invalid; tier disabled")
        return {}

    fingerprints: dict[str, bytes] = {}
    for label, value in decoded.items():
        if (
            isinstance(label, str)
            and re.fullmatch(r"[A-Za-z0-9_-]{1,64}", label)
            and isinstance(value, str)
            and re.fullmatch(r"[0-9a-fA-F]{64}", value)
        ):
            fingerprints[label] = bytes.fromhex(value)
    if len(fingerprints) != len(decoded):
        _safe_log(logging.WARNING, "Secrets observer fingerprint entries are invalid; invalid entries disabled")
    return fingerprints


def _text_leaves(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from _text_leaves(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            if isinstance(key, str) and key.lower() not in _NON_TEXT_KEYS:
                yield from _text_leaves(item)


def _entropy(value: str) -> float:
    if not value:
        return 0.0
    counts = Counter(value)
    return -sum((count / len(value)) * math.log2(count / len(value)) for count in counts.values())


def _sensitive_assignment_name(name: str) -> bool:
    segments = set(re.split(r"[_-]+", name.upper()))
    return bool(segments & _ENV_NAME_SEGMENTS)


def _candidate_fingerprint_matches(text: str, fingerprints: dict[str, bytes]):
    if not fingerprints:
        return
    for match in _CANDIDATE.finditer(text):
        token = match.group()
        char_classes = (
            any(char.islower() for char in token),
            any(char.isupper() for char in token),
            any(char.isdigit() for char in token),
            any(char in "_./+=-" for char in token),
        )
        if sum(char_classes) < 2:
            continue
        candidates = [(token, match.start(), match.end())]
        for separator in ("=", ":"):
            offset = 0
            for part in token.split(separator):
                start = token.find(part, offset)
                if part:
                    candidates.append((part, match.start() + start, match.start() + start + len(part)))
                    offset = start + len(part) + 1
        for candidate, start, end in candidates:
            digest = hashlib.sha256(candidate.encode("utf-8")).digest()
            for label, expected in fingerprints.items():
                if digest == expected:
                    yield (start, end, f"fingerprint:{label}", 100)


def _scan_text(text: str, fingerprints: dict[str, bytes]) -> list[tuple[int, int, str, int]]:
    ciphertext = list(_SOPS_CIPHERTEXT.finditer(text))
    if ciphertext:
        masked = list(text)
        for match in ciphertext:
            masked[match.start() : match.end()] = " " * (match.end() - match.start())
        scan_text = "".join(masked)
    else:
        scan_text = text
    matches: list[tuple[int, int, str, int]] = []

    for label, pattern in _PATTERNS:
        matches.extend((m.start(), m.end(), label, 80) for m in pattern.finditer(scan_text))
    matches.extend(_candidate_fingerprint_matches(scan_text, fingerprints))

    for assignment in _ASSIGNMENT.finditer(scan_text):
        name = assignment.group("key")
        value = assignment.group("value").strip("\"'")
        if _sensitive_assignment_name(name) and len(value) >= 16 and _entropy(value) >= 3.0:
            matches.append((assignment.start("value"), assignment.end("value"), "sensitive_assignment", 60))

    if not matches:
        return []
    matches.sort(key=lambda item: (item[0], -item[3], item[1], item[2]))
    merged: list[tuple[int, int, str, int]] = []
    for start, end, label, priority in matches:
        if merged and start < merged[-1][1]:
            old_start, old_end, old_label, old_priority = merged[-1]
            if priority > old_priority:
                merged[-1] = (old_start, max(old_end, end), label, priority)
            else:
                merged[-1] = (old_start, max(old_end, end), old_label, old_priority)
        else:
            merged.append((start, end, label, priority))
    return merged


def _is_local_destination(data: dict[str, Any]) -> bool:
    api_base = data.get("api_base")
    if isinstance(api_base, str):
        try:
            hostname = (urlsplit(api_base).hostname or "").lower()
            return hostname in {"localhost", "127.0.0.1", "::1"} or hostname.endswith(
                ".svc.cluster.local"
            )
        except ValueError:
            return False

    model = data.get("model")
    return isinstance(model, str) and model.lower().startswith(_LOCAL_MODEL_PREFIXES)


class SecretsObserverGuardrail(CustomGuardrail):
    """Report likely secrets while preserving the complete request unchanged."""

    use_native_lifecycle_hooks = True
    records_own_guardrail_information = True

    def __init__(self, **kwargs: Any):
        super().__init__(**kwargs)
        self._fingerprints = _load_fingerprints(os.getenv("GUARDRAIL_SECRETS_FINGERPRINTS"))
        self._observe_only_setting = os.getenv("GUARDRAIL_SECRETS_DRY_RUN", "")
        if self._observe_only_setting != "1":
            _safe_log(logging.ERROR, "Secrets observer requires GUARDRAIL_SECRETS_DRY_RUN=1; enforcement is unavailable")
        _safe_log(
            logging.INFO,
            "Secrets observer started in observe-only mode; detectors=%d fingerprint_count=%d",
            len(_PATTERNS) + 2,
            len(self._fingerprints),
        )

    def _observe(self, data: dict[str, Any], stage: str) -> dict[str, Any]:
        if not isinstance(data, dict):
            return data
        started = time.perf_counter()
        outcome = "scanned"
        counts: Counter[str] = Counter()
        try:
            if _is_local_destination(data):
                outcome = "local_skip"
            else:
                for root in _CONTENT_ROOTS:
                    if root not in data:
                        continue
                    for text in _text_leaves(data[root]):
                        counts.update(label for _, _, label, _ in _scan_text(text, self._fingerprints))
        except Exception as exc:  # fail open; do not expose exception or request values
            outcome = "scan_error"
            _safe_log(logging.WARNING, "Secrets observer scan failed; category=%s", type(exc).__name__)

        elapsed_ms = round((time.perf_counter() - started) * 1000, 3)
        if counts:
            _safe_log(
                logging.WARNING,
                "Secrets observer detected likely credentials; stage=%s detectors=%s counts=%s",
                stage,
                ",".join(sorted(counts)),
                dict(sorted(counts.items())),
            )

        audit = {
            "mode": "observe_only",
            "stage": stage,
            "outcome": outcome,
            "detector_counts": dict(sorted(counts.items())),
            "duration_ms": elapsed_ms,
        }
        try:
            self.add_standard_logging_guardrail_information_to_request_data(
                guardrail_json_response=audit,
                request_data=data,
                guardrail_status="success",
            )
            if outcome == "scanned":
                add_guardrail_to_applied_guardrails_header(
                    request_data=data,
                    guardrail_name=self.guardrail_name,
                )
        except Exception as exc:  # reporting failure must not change request handling
            _safe_log(logging.WARNING, "Secrets observer audit reporting failed; category=%s", type(exc).__name__)
        return data

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        return self._observe(data, "ingress")

    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        return self._observe(kwargs, "deployment")

    async def apply_guardrail(self, inputs, request_data, input_type, logging_obj=None):
        self._observe(request_data, f"apply_guardrail:{input_type}")
        return inputs
