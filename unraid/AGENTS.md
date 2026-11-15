# Unraid Agent Rules

Read the repo root `AGENTS.md` first. These rules apply to everything under `unraid/`.

## Image Updates

- Image updates belong to Unraid and Compose Manager, not Renovate or repository version bumps.
- Use publisher-supported moving image tags. Do not pin release versions or image digests unless the user explicitly requests it.
- Do not invent a moving tag or silently switch image publishers. If the chosen publisher has no suitable moving tag, explain that constraint before proceeding.
- Do not change the existing Unraid update workflow as part of deploying a container.
- Garage uses `junkerderprovinz/garage:latest`, the Unraid Community Applications image.

## Scope

- Do only the requested work. Container deployment does not authorize data migration, IP changes, or changes to the existing service.
- Do not expand the task into unrelated investigations or present an isolated observation as a confirmed blocker.

## Deployment Workflow

- Check the Unraid Community Applications template before choosing an upstream image or declaring that no rolling image exists.
- Prepare and validate the Compose definition first. Let Compose Manager pull the image during deployment; do not manually pull images as preparation.
- Reuse the existing managed-file deployment and native Compose Manager. Do not build another deployment framework for one container.
- Every Unraid application must have a working icon, using the Community Applications or publisher icon.
- Configure both the container's `net.unraid.docker.icon` label and Compose Manager's per-project `icon_url` metadata file. The stack icon does not fall back to the container label.
- Verify both icon paths before considering deployment complete; a correct container label alone is insufficient.

## Verification

- Use the selected image's actual configuration paths, not assumptions from a different image or the LXC.
- For `junkerderprovinz/garage`, check the daemon with `docker exec garage garage -c /config/garage.toml status`.
- Observe the rendered web UI and use its actual landmarks for readiness. Do not wait for an assumed label or treat an initial blank frame as a failure.
- Compose Manager stores `autostart` as literal `true` without a newline. Manage it with `content: "true"` in `config.yaml`, not a newline-terminated source file.
- Once the requested container and endpoints are verified, finish the scoped checks and report. Do not expand into unrelated audits.
