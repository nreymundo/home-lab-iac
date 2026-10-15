"""Provider-node reconciliation preserves independent endpoint identities."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "roles/containers/omniroute/files/bootstrap_omniroute.py"
SPEC = importlib.util.spec_from_file_location("omniroute_bootstrap", HELPER)
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)


class ProviderNodeReconciliationTests(unittest.TestCase):
    def reconcile(self, image_enabled):
        config = {
            "apiKeysOutputFile": "/unused",
            "managementKeyName": "bootstrap",
            "providerNode": {"ref": "providerNode", "name": "llama-swap", "enabled": True},
            "providerNodes": [{"ref": "comfyui", "name": "comfyui", "enabled": image_enabled}],
            "providerModels": [
                {"providerRef": "providerNode", "modelId": "chat"},
                {"providerRef": "comfyui", "modelId": "image"},
            ],
        }
        patches = {}
        for name in (
            "ensure_oidc_settings", "ensure_general_settings", "ensure_endpoint_settings",
            "ensure_combo_defaults", "ensure_model_aliases", "remove_api_keys",
        ):
            patches[name] = lambda *args, **kwargs: False
        patches["load_stored_key"] = lambda *args: "test-token"
        with patch.multiple(bootstrap, **patches), patch.object(
            bootstrap, "ensure_provider_node",
            side_effect=lambda client, spec, actions: ("node-" + spec["name"], False),
        ) as nodes, patch.object(
            bootstrap, "ensure_node_connection", return_value=("connection", False),
        ), patch.object(bootstrap, "sync_models", return_value=False), patch.object(
            bootstrap, "ensure_provider_model", return_value=False,
        ) as metadata:
            warnings = []
            self.assertFalse(bootstrap.reconcile(config, object(), [], warnings))
            return nodes, metadata, warnings

    def test_multiple_nodes_resolve_metadata_to_their_own_ids(self):
        nodes, metadata, warnings = self.reconcile(True)
        self.assertEqual(nodes.call_count, 2)
        self.assertEqual(metadata.call_count, 2)
        self.assertEqual(metadata.call_args.args[2], {
            "providerNode": "node-llama-swap", "comfyui": "node-comfyui",
        })
        self.assertEqual(warnings, [])

    def test_disabled_image_node_does_not_skip_llama_swap_metadata(self):
        nodes, metadata, warnings = self.reconcile(False)
        self.assertEqual(nodes.call_count, 1)
        self.assertEqual(metadata.call_count, 1)
        self.assertEqual(metadata.call_args.args[1]["modelId"], "chat")
        self.assertTrue(any("comfyui" in warning for warning in warnings))


if __name__ == "__main__":
    unittest.main()
