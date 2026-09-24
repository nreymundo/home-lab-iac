# OmniRoute Ansible role

This role deploys OmniRoute and Redis with Docker Compose and reconciles the
gateway's supported management APIs from Git. It does not migrate Kubernetes
clients or remove LiteLLM.

## Desired-state schema

`templates/bootstrap-config.json.j2` renders these sections:

- `settings`, `cacheSettings`, `compressionSettings`, and `comboDefaults`
- API-key provider connections plus required native OAuth providers
- one OpenAI-compatible provider node and its connection
- explicitly managed provider-model metadata
- combos and model-combo mappings
- Settings aliases that remain explicitly managed
- API keys and an explicit keys-to-remove list

Pricing sync is enabled for this VM in group vars. OmniRoute refreshes the public
LiteLLM pricing catalog at startup and daily thereafter; user price overrides
take precedence over synced entries.

The installation-specific providers, metadata, public combos, and workload key
policies are in `ansible/inventories/group_vars/omniroute_vms.yml`. Role
defaults contain the common safety policy. Objects are resolved by stable
identity and ambiguous duplicates stop reconciliation. Objects absent from the
declaration are not pruned.

Provider-model token limits and embedding dimensions are create-only in the
reviewed OmniRoute API. For a managed row with drift in those fields, the role
removes and recreates only that exact metadata overlay with
`resetOverride=true`; it never clears a provider catalog. Mutable metadata is
updated with `PUT` and all managed fields are read back.

The deployed image must support the APIs used by the reconciler. The current
image remains pinned for its Authentik fixes; source review alone does not prove
that every API behavior is present in that image. In particular, verify native
Codex, authenticated `llama-cpp` embeddings, remote provider-node audio/rerank,
and provider-model readback before accepting deployment.

## Idempotency and credentials

New API keys are created with the create schema, and their one-time raw values
are atomically saved to `/etc/omniroute/bootstrap-api-keys.json` with mode
`0600` before update-only permissions are patched. A failed permissions patch
therefore leaves a recoverable key; rerunning Ansible reuses its object and
converges the policy. Existing keys are not regenerated.

Native Codex OAuth enrollment is owned by OmniRoute. Ansible reports a warning
when the `codex` connection is absent and never invents OAuth data, copies a
LiteLLM token file, or overwrites refresh state.

Settings comparisons cover only declared fields. Provider-specific updates
merge with the observed object so OAuth/runtime fields not owned by Ansible are
preserved. Catalog import changes count as reconciliation changes, while
telemetry and timestamps are ignored.

## Validation

Run from the repository root:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --project-dir ansible \
  ansible/playbooks/omniroute.yml ansible/roles/containers/omniroute/
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ansible/inventories/omniroute.yml \
  ansible/playbooks/omniroute.yml --syntax-check
```

The role validates Compose with `docker compose ... config --quiet`, compiles
the rendered Python, and parses the rendered JSON before reconciliation. These
checks do not print expanded secret-bearing files. Ansible check mode renders
and compares ordinary files but intentionally skips Compose validation,
service changes, health checks, and management API mutations; it does not prove
remote convergence.

## Deployment order

A production run is a separate authorized operation:

1. Confirm the selected image and its management API contracts in a disposable
   or current authenticated session.
2. Enroll the native Codex connection in OmniRoute if it is not already
   enrolled. Do not place OAuth tokens in Ansible.
3. Run the playbook:

   ```bash
   ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
     -i ansible/inventories/omniroute.yml \
     ansible/playbooks/omniroute.yml
   ```

4. Run it a second time. It must preserve object IDs and raw keys and report no
   managed drift except a real upstream catalog availability change.
5. Copy only the required one-time workload key values into each workload's
   existing secret owner through the repository's SOPS process. Phase 1 does
   not change client secret references.

## Explicit smoke tests

Use the operator key only for controlled probes. Record the image digest,
endpoint, model, result, and limitation without recording bearer values or
private content.

- Verify Authentik login, disabled password login, and management-key access to
  every managed settings endpoint.
- Verify missing/invalid API keys fail, workload keys list only intended
  catalog entries, allowed routes work, and direct disallowed routes fail.
- Exercise local chat and vision, Codex chat and Responses streaming/non-
  streaming/tool flow, GLM reasoning/tool flow, and structured output without
  LiteLLM-only request fields.
- Verify scalar and batched embeddings return ordered 2560-value vectors and
  compare a small existing retrieval sample through both gateways.
- Exercise native OpenRouter and local rerank, both STT routes, TTS with a valid
  existing voice, and both image workflows.
- Confirm cold local targets receive their configured timeout and that requests
  go directly from OmniRoute to upstream providers without a LiteLLM hop.

Do not make live inference an unconditional Ansible action. It can spend cloud
quota and repeatedly load local models.

## Later phases

Client cutovers are separate changes. Keep LiteLLM and existing client secrets
in place, migrate one workload at a time to
`http://omniroute.external-proxy.svc.cluster.local:20128/v1`, and retain each
old URL/key/model tuple as rollback. Inventory Frigate, Mailflow, Paperless-AI,
n8n workflow credentials, Open WebUI saved chats, and other LiteLLM traffic
before declaring migration complete. Remove LiteLLM only after attributable
traffic is zero and every replacement behavior has runtime evidence.
