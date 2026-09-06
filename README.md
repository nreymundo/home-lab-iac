# Home Lab / Servers - IaC

This is like my 5th attempt at trying to bring some order to the chaotic mess that is my home lab.

I started with docker compose in a Raspberry Pi, then moved to Unraid and a _lot_ of click ops, eventually I moved to Proxmox with still a lot of click ops and _some_ scripting. Now I'm trying to do it the proper professional way (You know, what I actually do for a living?) because really, who needs hobbies when you can keep cosplaying as a devops after you are done playing one at work?.

This is also an excuse for me to play around with AI assisted coding for something more specific and long term than MVPs, quick scripts or fixes to already existing code.

All the other `.md` files in this repository are either fully written by LLMs or at least have a lot of AI assistance. This one you are reading now is and will be fully written by yours truly (I'll leave it up to you to decide whether that's a good or a bad thing). The code itself, whether written by LLMs, by me or a mix of both is audited and ran locally to validate.


## TL;DR of what I'm trying to accomplish with this.

Everything starts with [Packer](packer/) baking base VM templates (Ubuntu, Fedora) that get uploaded to Proxmox. [Terraform](terraform/README.md) clones those templates into the VMs and LXC containers that run my infrastructure, plus some cloud infrastructure (I may eventually add my Cloudflare settings here), and it generates the Ansible inventory for the K3s fleet. [Ansible](ansible/README.md) then provisions and configures systems: mainly VMs, Proxmox hosts and other servers, single board computers and things like that. It also provisions my k3s cluster. From there [Kubernetes](kubernetes/README.md) takes over: Flux does GitOps reconciliation and Renovate keeps charts and images from going stale. A bunch of pre-commit hooks try not to push _that_ much broken crap.

I'm following a lot of good practices but this will _definitely_ be more of a bazaar than a cathedral.


## The map

| Layer | What lives there |
| --- | --- |
| [packer/](packer/) | Base VM image templates uploaded to Proxmox |
| [terraform/](terraform/README.md) | Reusable modules plus concrete VM, LXC, and cloud roots |
| [ansible/](ansible/README.md) | Roles and thin playbooks that configure everything above |
| [kubernetes/](kubernetes/README.md) | Flux-managed desired state for the cluster |
| [docs/](docs/README.md) | Decision record, runbooks, and agent workflow notes |


## Practices I'm weirdly proud of

* **One source of truth for node topology.** Terraform generates the Ansible inventory for the K3s nodes (`terraform/instances/vm/k3s_nodes/` renders `ansible/inventories/k3s-nodes.yml`), so the fleet is defined once instead of maintained in two places.
* **Registry peer sharing with an upstream escape hatch.** Every K3s node runs the embedded registry and serves its cached images to peer nodes over TCP `5001`, and any cache miss falls through to a direct upstream pull. The knobs live in `ansible/roles/k3s/defaults/main.yml`.
* **Layered secrets with guardrails to match.** Ansible, Packer, and Terraform pull secrets at runtime through a read-only 1Password CLI service account; Kubernetes secrets are SOPS-encrypted `*.sops.yaml` files in Git; pre-commit hooks block key material and plaintext Secrets before they ever reach a commit.
* **Path-filtered validation.** CI only runs the hard-failing jobs that match what actually changed (kubeconform, Checkov, Trivy), so a docs tweak doesn't spin up the whole gauntlet.


## Reading map

| Doc | What it's for |
| --- | --- |
| [docs/decisions-and-tradeoffs.md](docs/decisions-and-tradeoffs.md) | Durable control and automation decisions, and the trade-offs behind them |
| [docs/kubernetes-bootstrap.md](docs/kubernetes-bootstrap.md) | Bootstrap and restore runbook for the Flux-managed cluster |
| [SECURITY.md](SECURITY.md) | Security practices, secrets handling, and network posture |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, validation commands, and conventions |
| [AGENTS.md](AGENTS.md) with [docs/opencode.md](docs/opencode.md) | How AI agents are expected to behave in this repo |


## Credits / Attribution

Here's a list of other projects, tools and code I'm using as inspiration or implementing here. In no particular order, and please let me know if I forget anything.

1. [bjw-s-labs' helm-charts](https://github.com/bjw-s-labs/helm-charts).
1. [kyuz0's strix halo toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes).
1. [mostlygeek's llama-swap](https://github.com/mostlygeek/llama-swap).
