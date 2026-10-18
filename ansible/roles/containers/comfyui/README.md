# ComfyUI on the LLM LXC

The role builds ComfyUI 0.40.0 on a digest-pinned Strix Halo ROCm image and adds
[ComfyUI-Roundabout](https://github.com/0c0/ComfyUI-Roundabout) at a pinned commit.
The selected ROCm PyTorch wheels are constrained during the build. Rebuilding or
recreating the container preserves models, inputs, outputs, and user state.

The build replaces the base image's July ROCm 7.15 wheels with a matched,
pinned ROCm 10.1/PyTorch package set. The old runtime burns a CPU core after
even a one-element GPU operation while the GPU is idle, increasing package
power. See the [upstream idle-spin report](https://github.com/ROCm/rocm-systems/issues/12674).
Validate runtime updates with a GPU operation followed by an idle CPU/power
measurement, as well as image generation; startup health alone misses this fault.

Clients use the existing **LiteLLM HTTPS endpoint**, with their LiteLLM API key:

```text
https://litellm.lan.${CLUSTER_DOMAIN}/v1
model: local/image
```

LiteLLM routes generation and editing to
`http://comfyui.external-proxy.svc.cluster.local:8188/v1` through the existing
ComfyUI Service and Endpoints. Its `local/image` model declaration lives in
`kubernetes/apps/apps/ai/litellm/configmap.yaml`. The same deployment ID is used
for the persistent live model registered through LiteLLM's model-management API,
so loading the Git declaration does not add a second deployment. Responses
default to `b64_json`, keeping backend image URLs out of normal client responses.
The `hosted_vllm` provider supplies generic OpenAI-compatible image handling
without the `openai` provider's GPT Image parameter restrictions.

For example, with `LITELLM_BASE_URL` set to that URL and `LITELLM_API_KEY` set to
an existing LiteLLM client key:

```bash
curl --fail "$LITELLM_BASE_URL/images/generations" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"local/image","prompt":"A red ceramic teapot on a wooden table","size":"1024x1024","response_format":"b64_json"}'
curl --fail "$LITELLM_BASE_URL/images/edits" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -F model=local/image -F 'prompt=Change the teapot to blue' \
  -F image=@/path/to/teapot.png -F response_format=b64_json
```

The UI remains on port 8188. Roundabout runs inside ComfyUI; its additional
loopback listener at `http://127.0.0.1:10050/v1` is for node-local diagnostics.
Client calls go through LiteLLM. The old `comfyui-openai-api` systemd service is
stopped and removed by the role. MCP is disabled.

The build applies `files/roundabout-multipart-refs.patch`: the pinned gateway
otherwise drops multipart image bytes for reference-only workflows such as
Qwen 2.1. It also accepts the `image[]` multipart field emitted by LiteLLM.
The patch feeds all uploaded images into its existing reference-slot
path, retaining the gateway's slot-count validation and upload handling.

Only `qwen-image-2.1-turbo` is registered, with aliases `qwen-image` and
`qwen-image-edit`. Both generation and editing use the same BF16 diffusion model,
Qwen3-VL encoder, and Qwen Image 2.1 VAE. The API workflow derives from
Roundabout commit `d148fd09e2f2048c839083b395e1929ad528644d`'s unified Qwen graph,
with BF16 weights, ten reference slots, and the official Turbo sampler schedule:

```text
1.0, 0.978453, 0.95418, 0.926626, 0.89508, 0.845148, 0.704534, 0.414568, 0
```

The two UI workflows are adapted from the official Comfy-Org
`image_qwen_image_2_1_turbo_t2i.json` and
`image_qwen_image_2_1_turbo_image_edit.json` templates. Prompt refinement is off;
the optional prompt-enhancement checkpoints are not required or downloaded.
API edits preserve the first image's aspect ratio at a 1024x1024 pixel budget.
The API uses CFG 1, so negative prompting is not exposed. Step count and schedule
are fixed together for Turbo; do not apply the previous Lightning LoRAs.

Workflows are provisioned and maintained manually on the LXC, outside Git:

- UI: `/opt/ai/containers/comfyui/user/default/workflows/`
- API: `/opt/ai/containers/comfyui/workflows/api/qwen-image-2.1-turbo.json`

Ansible configures the container, workflow directory mount, and API model mapping;
it does not install, replace, or remove workflow JSON. Provision these files on
a fresh node before starting the image API.

## Model provisioning

Automatic downloads are disabled by default. Set
`comfyui_model_downloads_enabled: true` to opt in, or download directly on the
node using the revision and file list in `defaults/main.yml`:

```bash
docker exec comfyui hf download Comfy-Org/Qwen-Image-2.1 \
  diffusion_models/qwen_image_2.1_turbo_bf16.safetensors \
  text_encoders/qwen3vl_8b_bf16.safetensors \
  vae/qwen_image_2.1_vae_bf16.safetensors \
  --revision a8342359c61979b06a8dafb1a47991fe1f30e994 \
  --local-dir /root/comfy-models
```

The three files occupy about 32.4 GB under `/opt/ai/models/comfyui`. The role
neither seeds the toolbox's old workflows nor downloads old model profiles.
Existing obsolete files are removed manually after replacement validation;
inputs and outputs are not part of model/workflow cleanup.

## Deploy and validate

From the repository root:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --project-dir ansible ansible/roles/containers/comfyui
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/llm_lxc.yml --syntax-check
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/llm_lxc.yml --tags comfyui --limit ct-llm
```

The role rebuilds when its Dockerfile or gateway patch changes, or the local image is absent.
`comfyui_force_rebuild: true` requests a rebuild. Update the image tag alongside
pinned source revisions to make the resulting artifact distinguishable.

On the LXC:

```bash
curl --fail http://127.0.0.1:10050/v1/models
curl --fail http://127.0.0.1:10050/v1/images/generations \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen-image-2.1-turbo","prompt":"A red ceramic teapot on a wooden table","size":"1024x1024","seed":42,"response_format":"b64_json"}'
curl --fail http://127.0.0.1:10050/v1/images/edits \
  -F model=qwen-image-2.1-turbo -F 'prompt=Change the teapot to blue' \
  -F image=@/path/to/generated.png -F response_format=b64_json
```

Validate both output content and image dimensions, then compare container ID
and GPU allocation before and after the idle timer. The timer remains enabled:
it checks roughly every minute and restarts the container after 300 seconds
since the last successful generation, only when running and pending queues are
empty. Its history clears on restart, preventing repeated idle restarts until
another successful generation. Startup health and model registration alone do
not establish successful model inference or memory release.
