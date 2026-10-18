"""Redact detected secrets from provider-bound requests and report safely."""

from __future__ import annotations

import hashlib
import json
import logging
import math
import os
import re
import time
import uuid
from collections import Counter
from collections.abc import Iterable
from contextvars import ContextVar
from typing import Any
from urllib.parse import urlsplit

from litellm.integrations.custom_guardrail import CustomGuardrail
from litellm.proxy.common_utils.callback_utils import (
    add_guardrail_to_applied_guardrails_header,
)


_AUDIT_LOGGER = logging.getLogger("LiteLLM Proxy.secrets_observer")
_AUDIT_LOGGER.setLevel(logging.INFO)
_CALL_STATE: ContextVar[dict[str, bool] | None] = ContextVar("secrets_guardrail_call_state", default=None)
_CALL_STATES: dict[str, dict[str, bool]] = {}
_REDACTION_NOTICE = (
    "[Security notice: LiteLLM detected and redacted sensitive credential-like content "
    "from this request before sending it to the model. Do not infer, reconstruct, or ask "
    "for the redacted value. Continue using the remaining request content.]"
)
_SOPS_CIPHERTEXT = re.compile(r"ENC\[AES256_GCM,[^\]\r\n]*\]")
_CANDIDATE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_./+=-]{14,}[A-Za-z0-9+/=]")
_ASSIGNMENT = re.compile(
    r"(?i)(?<![A-Za-z0-9_])(?=(?P<key>\"[A-Za-z_][A-Za-z0-9_-]*\"|[A-Za-z_][A-Za-z0-9_-]*)"
    r"\s*(?:=|:)\s*(?P<value>\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,}\]]+))"
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
    "file_id",
    "id",
    "image",
    "image_url",
    "role",
    "type",
    "video",
}
_BINARY_OBJECT_TYPES = {
    "audio",
    "base64",
    "file",
    "image",
    "input_audio",
    "input_file",
    "input_image",
    "video",
}
_LOCAL_MODEL_PREFIXES = ("local/", "hosted_vllm/")


def _request_call_state(data: Any = None) -> dict[str, bool] | None:
    state = _CALL_STATE.get()
    call_id = data.get("litellm_call_id") if isinstance(data, dict) else None
    if isinstance(call_id, str):
        state = _CALL_STATES.get(call_id, state)
    return state


def _safe_log(level: int, message: str, *args: Any) -> None:
    try:
        _AUDIT_LOGGER.log(level, message, *args)
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


def _text_leaves(value: Any, binary_context: bool = False) -> Iterable[str]:
    if isinstance(value, str):
        if not binary_context:
            yield value
    elif isinstance(value, list):
        for item in value:
            yield from _text_leaves(item, binary_context)
    elif isinstance(value, dict):
        binary_object = binary_context or str(value.get("type", "")).lower() in _BINARY_OBJECT_TYPES
        for key, item in value.items():
            if not isinstance(key, str):
                continue
            normalized_key = key.lower()
            if normalized_key in _NON_TEXT_KEYS:
                continue
            yield from _text_leaves(item, binary_object)


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
        name = assignment.group("key").strip("\"'")
        value = assignment.group("value").strip("\"'")
        if _sensitive_assignment_name(name) and len(value) >= 16 and _entropy(value) >= 3.0:
            value_start, value_end = assignment.span("value")
            if scan_text[value_start:value_end][:1] in {"\"", "'"}:
                value_start += 1
                value_end -= 1
            matches.append((value_start, value_end, "sensitive_assignment", 60))

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


def _redact_text(text: str, fingerprints: dict[str, bytes]) -> tuple[str, Counter[str]]:
    matches = _scan_text(text, fingerprints)
    counts: Counter[str] = Counter()
    if not matches:
        return text, counts
    pieces: list[str] = []
    cursor = 0
    for start, end, label, _ in matches:
        pieces.extend((text[cursor:start], "[REDACTED: sensitive value]"))
        cursor = end
        counts[label] += 1
    pieces.append(text[cursor:])
    return "".join(pieces), counts


def _redact_value(value: Any, fingerprints: dict[str, bytes], binary_context: bool = False):
    counts: Counter[str] = Counter()
    if isinstance(value, str):
        if binary_context:
            return value, counts
        redacted, counts = _redact_text(value, fingerprints)
        return redacted, counts
    if isinstance(value, list):
        result = []
        for item in value:
            redacted, found = _redact_value(item, fingerprints, binary_context)
            result.append(redacted)
            counts.update(found)
        return result, counts
    if isinstance(value, dict):
        binary = binary_context or str(value.get("type", "")).lower() in _BINARY_OBJECT_TYPES
        result = {}
        for key, item in value.items():
            if not isinstance(key, str) or key.lower() in _NON_TEXT_KEYS:
                result[key] = item
                continue
            redacted, found = _redact_value(item, fingerprints, binary)
            result[key] = redacted
            counts.update(found)
        return result, counts
    return value, counts


def _is_local_destination(data: dict[str, Any]) -> bool:
    def endpoint(value: str) -> tuple[str, str, int | None] | None:
        try:
            parsed = urlsplit(value)
            if not parsed.hostname:
                return None
            return parsed.scheme.lower(), parsed.hostname.lower(), parsed.port
        except ValueError:
            return None

    api_base = data.get("api_base")
    if isinstance(api_base, str):
        destination = endpoint(api_base)
        if destination is None:
            return False
        _, hostname, _ = destination
        if hostname in {"localhost", "127.0.0.1", "::1"} or hostname.endswith(
            ".svc.cluster.local"
        ):
            return True

        configured_bases = (
            os.getenv("LITELLM_CREDENTIAL_LLAMA_SWAP_API_BASE"),
            os.getenv("VLLM_API_BASE"),
        )
        return any(
            configured_endpoint is not None and destination == configured_endpoint
            for configured_endpoint in (endpoint(base) for base in configured_bases if base)
        )

    model = data.get("model")
    return isinstance(model, str) and model.lower().startswith(_LOCAL_MODEL_PREFIXES)


def _add_model_notice(data: dict[str, Any], call_type: str | None) -> None:
    if call_type not in {
        "completion",
        "acompletion",
        "text_completion",
        "atext_completion",
        "responses",
        "aresponses",
    }:
        return
    state = _request_call_state(data)
    if state is not None and state.get("model_notice_added"):
        return
    messages = data.get("messages")
    if isinstance(messages, list):
        messages.insert(0, {"role": "system", "content": _REDACTION_NOTICE})
        if state is not None:
            state["model_notice_added"] = True
        return
    inputs = data.get("input")
    if isinstance(inputs, list):
        inputs.insert(
            0,
            {
                "type": "message",
                "role": "system",
                "content": [{"type": "input_text", "text": _REDACTION_NOTICE}],
            },
        )
        if state is not None:
            state["model_notice_added"] = True
        return
    for key in ("instructions", "instruction", "prompt", "input"):
        value = data.get(key)
        if isinstance(value, str):
            data[key] = f"{_REDACTION_NOTICE}\n\n{value}"
            if state is not None:
                state["model_notice_added"] = True
            return


def _was_redacted(data: Any = None) -> bool:
    state = _request_call_state(data)
    if state and state.get("redacted"):
        return True
    if isinstance(data, dict) and any(
        _REDACTION_NOTICE in text
        for root in _CONTENT_ROOTS
        for text in _text_leaves(data.get(root))
    ):
        return True
    pending = [data]
    seen: set[int] = set()
    while pending:
        value = pending.pop()
        if id(value) in seen:
            continue
        seen.add(id(value))
        if isinstance(value, dict):
            records = value.get("standard_logging_guardrail_information")
            if isinstance(records, list) and any(
                isinstance(record, dict)
                and isinstance(record.get("guardrail_response"), dict)
                and record["guardrail_response"].get("outcome") == "redacted"
                for record in records
            ):
                return True
            pending.extend(
                child
                for key, child in value.items()
                if key in {"litellm_params", "proxy_server_request", "body", "litellm_metadata", "metadata"}
                and isinstance(child, (dict, list))
            )
        elif isinstance(value, list):
            pending.extend(child for child in value if isinstance(child, (dict, list)))
    return False


def _prepend_assistant_notice(message: dict[str, Any], notice: str) -> None:
    content = message.get("content")
    if isinstance(content, str):
        if not content.startswith(notice):
            message["content"] = f"{notice}\n\n{content}"
    elif isinstance(content, list):
        if not any(
            isinstance(item, dict)
            and isinstance(item.get("text"), str)
            and item["text"].startswith(notice)
            for item in content
        ):
            message["content"] = [{"type": "text", "text": notice}, *content]
    elif content is None:
        message["content"] = notice


def _prepend_responses_notice(response: Any, notice: str) -> None:
    output = response.get("output") if isinstance(response, dict) else response.output
    if not isinstance(output, list):
        return
    for item in output:
        item_type = item.get("type") if isinstance(item, dict) else getattr(item, "type", None)
        if item_type != "message":
            continue
        content = item.get("content") if isinstance(item, dict) else getattr(item, "content", None)
        if not isinstance(content, list):
            continue
        for block in content:
            block_type = block.get("type") if isinstance(block, dict) else getattr(block, "type", None)
            text = block.get("text") if isinstance(block, dict) else getattr(block, "text", None)
            if block_type == "output_text" and isinstance(text, str):
                if isinstance(block, dict):
                    if not text.startswith(notice):
                        block["text"] = f"{notice}\n\n{text}"
                else:
                    if not text.startswith(notice):
                        block.text = f"{notice}\n\n{text}"
                return
        if not any(
            (block.get("type") if isinstance(block, dict) else getattr(block, "type", None)) == "output_text"
            and (block.get("text") if isinstance(block, dict) else getattr(block, "text", None)) == notice
            for block in content
        ):
            content.insert(0, {"type": "output_text", "text": notice})
        return
    if not any(
        isinstance(item, dict)
        and item.get("type") == "message"
        and any(
            isinstance(block, dict) and block.get("type") == "output_text" and block.get("text") == notice
            for block in item.get("content", [])
        )
        for item in output
    ):
        output.append(
            {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": notice}]}
        )


class SecretsObserverGuardrail(CustomGuardrail):
    """Redact detector matches and continue with sanitized request content."""

    use_native_lifecycle_hooks = True
    records_own_guardrail_information = True

    def __init__(self, **kwargs: Any):
        super().__init__(**kwargs)
        self._fingerprints = _load_fingerprints(os.getenv("GUARDRAIL_SECRETS_FINGERPRINTS"))
        self._mode = os.getenv("GUARDRAIL_SECRETS_MODE", "observe").lower()
        if self._mode not in {"redact", "observe", "off"}:
            raise ValueError("GUARDRAIL_SECRETS_MODE must be redact, observe, or off")
        _safe_log(
            logging.INFO,
            "Secrets observer started; mode=%s detectors=%d fingerprint_count=%d",
            self._mode,
            len(_PATTERNS) + 2,
            len(self._fingerprints),
        )

    def _process(
        self,
        data: dict[str, Any],
        stage: str,
        extra_content: Any = None,
        call_type: str | None = None,
    ) -> dict[str, Any]:
        if not isinstance(data, dict):
            return data
        if self._mode == "off":
            return data
        started = time.perf_counter()
        outcome = "scanned"
        counts: Counter[str] = Counter()
        redacted = False
        call_id = data.get("litellm_call_id")
        if not isinstance(call_id, str) or not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", call_id):
            call_id = f"sg-{uuid.uuid4().hex}"
            data["litellm_call_id"] = call_id
        state = _request_call_state(data)
        if state is None:
            state = {"redacted": False, "model_notice_added": False}
            _CALL_STATE.set(state)
        _CALL_STATES[call_id] = state
        if len(_CALL_STATES) > 4096:
            _CALL_STATES.pop(next(iter(_CALL_STATES)))
        try:
            if _is_local_destination(data):
                outcome = "local_skip"
            elif self._mode == "redact":
                for root in _CONTENT_ROOTS:
                    if root in data:
                        data[root], found = _redact_value(data[root], self._fingerprints)
                        counts.update(found)
                if isinstance(extra_content, list):
                    clean_extra, found = _redact_value(extra_content, self._fingerprints)
                    counts.update(found)
                    if found:
                        extra_content[:] = clean_extra
                        extra_content.insert(0, _REDACTION_NOTICE)
                redacted = bool(counts)
                if redacted:
                    _add_model_notice(data, call_type)
            else:
                for root in _CONTENT_ROOTS:
                    if root in data:
                        counts.update(label for text in _text_leaves(data[root]) for _, _, label, _ in _scan_text(text, self._fingerprints))
                counts.update(label for text in _text_leaves(extra_content) for _, _, label, _ in _scan_text(text, self._fingerprints))
        except Exception as exc:  # fail open; do not expose exception or request values
            outcome = "scan_error"
            _safe_log(logging.WARNING, "Secrets observer scan failed; category=%s", type(exc).__name__)

        fingerprint_findings = sorted(label for label in counts if label.startswith("fingerprint:"))
        heuristic_findings = sorted(label for label in counts if not label.startswith("fingerprint:"))
        if redacted:
            outcome = "redacted"
            state["redacted"] = True
        elif counts and outcome == "scanned":
            outcome = "warning"

        elapsed_ms = round((time.perf_counter() - started) * 1000, 3)
        correlation_id = call_id
        audit = {
            "mode": self._mode,
            "stage": stage,
            "outcome": outcome,
            "detector_counts": [
                {"detector": label.encode("utf-8").hex(), "count": count}
                for label, count in sorted(counts.items())
            ],
            "duration_ms": elapsed_ms,
            "correlation_id": correlation_id,
        }
        if heuristic_findings:
            audit["warning"] = "possible_credential_may_be_example"
        if fingerprint_findings:
            audit["fingerprint_categories"] = [label.encode("utf-8").hex() for label in fingerprint_findings]
        _safe_log(
            logging.WARNING if counts or outcome == "scan_error" else logging.INFO,
            "Secrets observer audit %s",
            json.dumps(audit, sort_keys=True, separators=(",", ":")),
        )
        try:
            self.add_standard_logging_guardrail_information_to_request_data(
                guardrail_json_response=audit,
                request_data=data,
                guardrail_status="success",
                duration=elapsed_ms / 1000,
            )
            if outcome not in {"local_skip", "scan_error"}:
                add_guardrail_to_applied_guardrails_header(
                    request_data=data,
                    guardrail_name=self.guardrail_name,
                )
        except Exception as exc:  # reporting failure must not change request handling
            _safe_log(logging.WARNING, "Secrets observer audit reporting failed; category=%s", type(exc).__name__)
        return data

    async def async_post_call_response_headers_hook(
        self,
        data,
        user_api_key_dict,
        response,
        request_headers=None,
        litellm_call_info=None,
    ):
        """Expose redaction status without copying request content into headers."""
        if not _was_redacted(data):
            return {}
        return {
            "X-LiteLLM-Secrets-Guardrail": "redacted",
        }

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        state = {"redacted": False, "model_notice_added": False}
        _CALL_STATE.set(state)
        call_id = data.get("litellm_call_id") if isinstance(data, dict) else None
        if isinstance(call_id, str):
            _CALL_STATES[call_id] = state
        return self._process(data, "ingress", call_type=call_type)

    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        return self._process(kwargs, "deployment", call_type=call_type)

    async def apply_guardrail(self, inputs, request_data, input_type, logging_obj=None):
        texts = inputs.get("texts") if isinstance(inputs, dict) else None
        data = request_data if isinstance(request_data, dict) else {}
        self._process(data, f"apply_guardrail:{input_type}", extra_content=texts)
        return inputs

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        if not _was_redacted(data):
            return response
        notice = "Notice: sensitive credential-like content was redacted before processing."
        try:
            if isinstance(response, dict):
                choices = response.get("choices")
                if isinstance(choices, list) and choices:
                    choice = choices[0]
                    message = choice.get("message") if isinstance(choice, dict) else None
                    if isinstance(message, dict):
                        _prepend_assistant_notice(message, notice)
                    elif isinstance(choice, dict) and isinstance(choice.get("text"), str):
                        if not choice["text"].startswith(notice):
                            choice["text"] = f"{notice}\n\n{choice['text']}"
                elif "output" in response:
                    _prepend_responses_notice(response, notice)
                return response
            if hasattr(response, "output"):
                _prepend_responses_notice(response, notice)
                return response
            choice = response.choices[0]
            if hasattr(choice, "message"):
                message = choice.message
                content = message.content
                if isinstance(content, str):
                    if not content.startswith(notice):
                        message.content = f"{notice}\n\n{content}"
                elif isinstance(content, list):
                    if not any(
                        isinstance(item, dict)
                        and isinstance(item.get("text"), str)
                        and item["text"].startswith(notice)
                        for item in content
                    ):
                        message.content = [{"type": "text", "text": notice}, *content]
                elif content is None:
                    message.content = notice
            elif hasattr(choice, "text"):
                text = choice.text
                if isinstance(text, str) and not text.startswith(notice):
                    choice.text = f"{notice}\n\n{text}"
        except (AttributeError, IndexError, KeyError, TypeError):
            pass
        return response

    async def async_post_call_streaming_iterator_hook(self, user_api_key_dict, response, request_data):
        if not _was_redacted(request_data):
            async for chunk in response:
                yield chunk
            return
        notice_pending = True
        async for chunk in response:
            if notice_pending:
                try:
                    delta = chunk.choices[0].delta
                    content = delta.content
                    notice = "Notice: sensitive credential-like content was redacted before processing."
                    if isinstance(content, str) and content.startswith(notice):
                        notice_pending = False
                    elif content or getattr(delta, "tool_calls", None):
                        delta.content = f"{notice}\n\n{content or ''}"
                        notice_pending = False
                except (AttributeError, IndexError, TypeError):
                    pass
            yield chunk


def install_proxy_response_hooks() -> None:
    """Carry redaction status to endpoints bypassing normal callback headers."""
    from litellm.proxy.common_request_processing import ProxyBaseLLMRequestProcessing
    from litellm.responses.streaming_iterator import BaseResponsesAPIStreamingIterator

    original_headers = ProxyBaseLLMRequestProcessing.get_custom_headers
    if not getattr(original_headers, "secrets_guardrail_header_patch", False):
        def get_custom_headers(*args: Any, **kwargs: Any):
            headers = original_headers(*args, **kwargs)
            if _was_redacted(kwargs.get("request_data")):
                headers["X-LiteLLM-Secrets-Guardrail"] = "redacted"
            return headers

        get_custom_headers.secrets_guardrail_header_patch = True
        ProxyBaseLLMRequestProcessing.get_custom_headers = staticmethod(get_custom_headers)

    original_process_chunk = BaseResponsesAPIStreamingIterator._process_chunk
    if getattr(original_process_chunk, "secrets_guardrail_stream_patch", False):
        return

    def process_chunk(self, chunk: str):
        result = original_process_chunk(self, chunk)
        request_data = getattr(self, "request_data", None)
        if not (_was_redacted(request_data) or _was_redacted(getattr(self, "litellm_metadata", None))) or result is None:
            return result
        notice = "Notice: sensitive credential-like content was redacted before processing."
        event_type = getattr(result, "type", None)
        event_type = getattr(event_type, "value", event_type)
        state = getattr(self, "_secrets_guardrail_state", None)
        if state is None:
            state = {"responses_stream_notice_added": False}
            self._secrets_guardrail_state = state
        if event_type == "response.output_text.delta" and not state.get("responses_stream_notice_added"):
            delta = getattr(result, "delta", None)
            if isinstance(delta, str) and not delta.startswith(notice):
                state["responses_stream_notice_added"] = True
                return result.model_copy(update={"delta": f"{notice}\n\n{delta}"})
            state["responses_stream_notice_added"] = True
        elif event_type in {"response.completed", "response.incomplete"}:
            response = getattr(result, "response", None)
            if response is not None:
                _prepend_responses_notice(response, notice)
        return result

    process_chunk.secrets_guardrail_stream_patch = True
    BaseResponsesAPIStreamingIterator._process_chunk = process_chunk
