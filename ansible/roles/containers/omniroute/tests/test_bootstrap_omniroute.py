import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROLE = Path(__file__).resolve().parents[1]
SCRIPT = ROLE / "templates" / "bootstrap_omniroute.py.j2"
loader = importlib.machinery.SourceFileLoader("bootstrap_omniroute", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
bootstrap = importlib.util.module_from_spec(spec)
loader.exec_module(bootstrap)


class ProviderClient:
    def __init__(self):
        self.connection = {
            "id": "connection-1",
            "provider": "llama-cpp",
            "name": "llama-swap embeddings",
            "apiKey": "secret****alue",
            "providerSpecificData": {"oauthState": "preserve", "baseUrl": "http://old/v1"},
        }
        self.puts = []

    def get(self, path):
        self.assert_path(path, "/api/providers")
        return {"connections": [self.connection]}

    def put(self, path, body):
        self.puts.append((path, body))
        self.connection.update(body)

    @staticmethod
    def assert_path(actual, expected):
        if actual != expected:
            raise AssertionError((actual, expected))


class ComboClient:
    def __init__(self, combos):
        self.combos = combos
        self.puts = []
        self.posts = []

    def get(self, path):
        if path.startswith("/api/combos?"):
            return {"combos": self.combos, "total": len(self.combos)}
        raise AssertionError(path)

    def put(self, path, body):
        self.puts.append((path, body))

    def post(self, path, body):
        self.posts.append((path, body))
        return {"id": "new-combo"}


class KeyClient:
    def __init__(self, fail_patch=False, ignore_patch=False):
        self.key = None
        self.fail_patch = fail_patch
        self.ignore_patch = ignore_patch
        self.events = []

    def get(self, path):
        if path.startswith("/api/keys?"):
            keys = [] if self.key is None else [{"id": self.key["id"], "name": self.key["name"]}]
            return {"keys": keys, "total": len(keys)}
        if path.startswith("/api/keys/"):
            return dict(self.key)
        raise AssertionError(path)

    def post(self, path, body):
        self.events.append("post")
        self.key = {
            "id": "key-1",
            "name": body["name"],
            "modelAccessMode": body.get("modelAccessMode", "all"),
            "allowedModels": body.get("allowedModels", []),
            "allowedCombos": body.get("allowedCombos", []),
            "scopes": body.get("scopes", []),
            "compressionEnabled": True,
            "allowAutoCombos": True,
            "cacheDefaultMode": "legacy",
            "catalogScope": "all",
        }
        return {"id": "key-1", "name": body["name"], "key": "raw-secret-value"}

    def patch(self, path, body):
        self.events.append("patch")
        if self.fail_patch:
            raise bootstrap.BootstrapError("PATCH /api/keys/key-1 failed with HTTP 500")
        if not self.ignore_patch:
            self.key.update(body)


class AliasClient:
    def __init__(self):
        self.aliases = {"local-stt-large": "old", "unmanaged": "keep"}
        self.deleted = []

    def get(self, path):
        return {"custom": dict(self.aliases)}

    def delete(self, path, body=None, allow_missing=False):
        self.deleted.append(body["from"])
        self.aliases.pop(body["from"], None)


class MetadataClient:
    def __init__(self):
        self.model = {
            "id": "qwen3-embedding-4b",
            "apiFormat": "embeddings",
            "supportedEndpoints": ["embeddings"],
            "inputTokenLimit": 8192,
            "dimensions": 1024,
        }
        self.deleted = []
        self.posts = []

    def get(self, path):
        return {"models": [self.model] if self.model else []}

    def delete(self, path, body=None, allow_missing=False):
        self.deleted.append(path)
        self.model = None

    def post(self, path, body):
        self.posts.append(body)
        self.model = {
            "id": body["modelId"],
            "apiFormat": body["apiFormat"],
            "supportedEndpoints": body["supportedEndpoints"],
            "inputTokenLimit": body["max_input_tokens"],
            "dimensions": body["dimensions"],
        }
        return {"model": self.model}

    def put(self, path, body):
        self.model.update(body)


class SettingsClient:
    def __init__(self):
        self.state = {}
        self.patch_count = 0

    def get(self, path):
        return dict(self.state)

    def patch(self, path, body):
        self.patch_count += 1
        self.state.update(body)


class PaginationClient:
    def get(self, path):
        if "offset=0" in path:
            return {"keys": [{"id": str(index), "name": "key-%d" % index} for index in range(200)], "total": 201}
        if "offset=200" in path:
            return {"keys": [{"id": "duplicate", "name": "key-0"}], "total": 201}
        raise AssertionError(path)


class BootstrapTests(unittest.TestCase):
    def test_general_settings_create_then_second_run_is_noop(self):
        client = SettingsClient()
        desired = {"autoRoutingEnabled": False, "hideAutoCombos": True}
        self.assertTrue(bootstrap.ensure_general_settings(client, desired, []))
        self.assertFalse(bootstrap.ensure_general_settings(client, desired, []))
        self.assertEqual(client.patch_count, 1)

    def test_provider_base_url_updates_while_masked_key_matches(self):
        client = ProviderClient()
        spec = {
            "providerId": "llama-cpp",
            "name": "llama-swap embeddings",
            "apiKey": "secret-middle-value",
            "providerSpecificData": {"baseUrl": "http://new/v1"},
        }
        connection_id, changed = bootstrap.ensure_provider_connection(client, spec, [])
        self.assertTrue(changed)
        self.assertEqual(connection_id, "connection-1")
        payload = client.puts[0][1]
        self.assertNotIn("apiKey", payload)
        self.assertEqual(payload["providerSpecificData"]["oauthState"], "preserve")
        self.assertEqual(payload["providerSpecificData"]["baseUrl"], "http://new/v1")

    def test_normalized_combo_steps_are_equal(self):
        desired = ["llamaswap/qwen3.8-27b"]
        observed = [
            {
                "id": "generated",
                "kind": "model",
                "providerId": "llamaswap",
                "model": "qwen3.8-27b",
                "connectionId": "generated",
                "weight": 0,
            }
        ]
        self.assertTrue(bootstrap.combo_models_equal(observed, desired))
        reordered = list(reversed(observed + [{"providerId": "x", "model": "y"}]))
        self.assertFalse(bootstrap.combo_models_equal(reordered, desired))
        self.assertFalse(bootstrap.combo_models_equal(observed, ["llamaswap/other"]))

    def test_combo_api_defaults_do_not_cause_perpetual_update(self):
        client = ComboClient(
            [
                {
                    "id": "combo-1",
                    "name": "local/chat",
                    "models": [
                        {
                            "id": "generated",
                            "kind": "model",
                            "providerId": "llamaswap",
                            "model": "qwen3.8-27b",
                            "weight": 0,
                        }
                    ],
                    "strategy": "priority",
                    "config": {"targetTimeoutMs": 600000, "trackMetrics": True},
                    "isActive": True,
                    "isHidden": False,
                }
            ]
        )
        spec = {
            "name": "local/chat",
            "models": ["llamaswap/qwen3.8-27b"],
            "strategy": "priority",
            "config": {"targetTimeoutMs": 600000},
            "isActive": True,
            "isHidden": False,
        }
        combo_id, changed = bootstrap.ensure_combo(client, spec, [])
        self.assertEqual(combo_id, "combo-1")
        self.assertFalse(changed)
        self.assertEqual(client.puts, [])

    def test_new_key_is_stored_before_patch_failure_and_rerun_reuses_it(self):
        spec = {
            "name": "workload",
            "modelAccessMode": "restricted",
            "allowedModels": [],
            "allowedCombos": ["local/chat"],
            "scopes": [],
            "allowAutoCombos": False,
            "compressionEnabled": False,
            "cacheDefaultMode": "bypass",
            "catalogScope": "combos",
        }
        with tempfile.TemporaryDirectory() as directory:
            output = str(Path(directory) / "keys.json")
            client = KeyClient(fail_patch=True)
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.ensure_api_key(client, spec, output, [])
            self.assertEqual(bootstrap.load_stored_key(output, "workload"), "raw-secret-value")
            client.fail_patch = False
            self.assertTrue(bootstrap.ensure_api_key(client, spec, output, []))
            self.assertEqual(client.events.count("post"), 1)
            self.assertFalse(bootstrap.ensure_api_key(client, spec, output, []))

    def test_ignored_advanced_key_field_is_an_error(self):
        spec = {"name": "workload", "allowAutoCombos": False}
        with tempfile.TemporaryDirectory() as directory:
            client = KeyClient(ignore_patch=True)
            with self.assertRaisesRegex(bootstrap.BootstrapError, "ignored managed fields"):
                bootstrap.ensure_api_key(client, spec, str(Path(directory) / "keys.json"), [])

    def test_only_explicit_alias_is_removed(self):
        client = AliasClient()
        actions = []
        self.assertTrue(bootstrap.remove_model_aliases(client, ["local-stt-large", "missing"], actions))
        self.assertEqual(client.deleted, ["local-stt-large"])
        self.assertEqual(client.aliases, {"unmanaged": "keep"})

    def test_create_only_metadata_drift_recreates_exact_row(self):
        client = MetadataClient()
        spec = {
            "providerRef": "llama-cpp",
            "modelId": "qwen3-embedding-4b",
            "apiFormat": "embeddings",
            "supportedEndpoints": ["embeddings"],
            "max_input_tokens": 16384,
            "dimensions": 2560,
            "recreateForCreateOnlyChanges": True,
        }
        self.assertTrue(bootstrap.ensure_provider_model(client, spec, {}, []))
        self.assertEqual(len(client.deleted), 1)
        self.assertNotIn("all=true", client.deleted[0])
        self.assertIn("resetOverride=true", client.deleted[0])
        self.assertEqual(client.model["dimensions"], 2560)

    def test_create_only_metadata_drift_without_opt_in_fails(self):
        client = MetadataClient()
        spec = {
            "providerRef": "llama-cpp",
            "modelId": "qwen3-embedding-4b",
            "dimensions": 2560,
        }
        with self.assertRaisesRegex(bootstrap.BootstrapError, "create-only drift"):
            bootstrap.ensure_provider_model(client, spec, {}, [])

    def test_pagination_exposes_duplicate_names(self):
        items = bootstrap.paginated_items(PaginationClient(), "/api/keys", "keys")
        self.assertEqual(len(items), 201)
        with self.assertRaisesRegex(bootstrap.BootstrapError, "ambiguous"):
            bootstrap.find_unique(items, lambda item: item["name"] == "key-0", "API key key-0")

    def test_catalog_import_reports_real_changes_only(self):
        class SyncClient:
            def __init__(self, changes):
                self.changes = changes

            def post(self, path):
                return {
                    "availableModelsCount": 2,
                    "modelChanges": self.changes,
                }

        self.assertTrue(
            bootstrap.sync_models(
                SyncClient({"added": ["new"], "removed": [], "updated": []}),
                "connection",
                "provider",
                [],
            )
        )
        self.assertFalse(
            bootstrap.sync_models(
                SyncClient({"added": [], "removed": [], "updated": []}),
                "connection",
                "provider",
                [],
            )
        )

    def test_partial_key_failure_error_does_not_include_raw_key(self):
        spec = {"name": "workload", "allowAutoCombos": False}
        with tempfile.TemporaryDirectory() as directory:
            client = KeyClient(fail_patch=True)
            try:
                bootstrap.ensure_api_key(
                    client,
                    spec,
                    str(Path(directory) / "keys.json"),
                    [],
                )
            except bootstrap.BootstrapError as error:
                self.assertNotIn("raw-secret-value", str(error))
            else:
                self.fail("expected update failure")

    def test_both_lan_flags_reach_compose_environment(self):
        env_text = (ROLE / "templates" / "omniroute.env.j2").read_text(encoding="utf-8")
        compose_text = (ROLE / "templates" / "docker-compose.yml.j2").read_text(encoding="utf-8")
        for name in ("AUDIO_REMOTE_PROVIDER_NODES", "RERANK_REMOTE_PROVIDER_NODES"):
            self.assertIn(name, env_text)
            self.assertIn('%s: "${%s}"' % (name, name), compose_text)

    def test_duplicate_combo_is_rejected_without_creation(self):
        client = ComboClient([
            {"id": "1", "name": "local/chat", "models": []},
            {"id": "2", "name": "local/chat", "models": []},
        ])
        with self.assertRaisesRegex(bootstrap.BootstrapError, "ambiguous"):
            bootstrap.ensure_combo(client, {"name": "local/chat", "models": ["llamaswap/model"]}, [])
        self.assertEqual(client.posts, [])


if __name__ == "__main__":
    unittest.main()
