# Unraid Agent Rules

Read [the repository-wide rules](../AGENTS.md) first. These rules apply throughout `unraid/`.

## Source of Truth

- [`plugins.yaml`](plugins.yaml) declares user-installed plugins, reconciled by [`scripts/plugins.sh`](scripts/plugins.sh). An apply can remove user-installed plugins absent from the manifest.
- [`config.yaml`](config.yaml) declares managed host files, including Compose Manager project files, reconciled by [`scripts/configure.sh`](scripts/configure.sh).
- [`stacks.yaml`](stacks.yaml) records the Compose project inventory; stack definitions live in [`apps/`](apps/). Update the inventory and managed-file mappings when adding or removing a project.
- Use the scripts' `check` mode to inspect drift without modifying the host. `apply` changes the host. See the [Unraid contributor workflow](../CONTRIBUTING.md#unraid) for prerequisites and examples.

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
- Prepare and validate the Compose definition first. Let Compose Manager pull the image during deployment; do not pull it manually during preparation.
- Reuse managed-file deployment and Compose Manager. Do not add a separate deployment framework for a container.
- Every Unraid application needs a working icon from Community Applications or the publisher.
- Set the container's `net.unraid.docker.icon` label in its Compose file and the project's `icon_url` file in `config.yaml`. Compose Manager does not fall back to the container label for the stack icon.
- Verify both icons before considering deployment complete.

## Verification

- Use the selected image's actual configuration paths, not assumptions from a different image or the LXC.
- For `junkerderprovinz/garage`, check the daemon with `docker exec garage garage -c /config/garage.toml status`.
- Verify readiness in the rendered web UI. Use landmarks from that UI rather than assuming a label or treating a briefly blank frame as failure.
- Compose Manager stores `autostart` as the literal `true` without a newline. Use `content: "true"` in `config.yaml`, not a newline-terminated source file.
- Once the requested container and endpoints are verified, finish the scoped checks and report the result.
