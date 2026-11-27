# Home Lab / Servers - IaC

This is like my 5th attempt at trying to bring some order to the chaotic mess that is my home lab.

I started with docker compose in a Raspberry Pi, then moved to Unraid and a _lot_ of click ops, eventually I moved to Proxmox with still a lot of click ops and _some_ scripting. Now I'm trying to do it the proper professional way (You know, what I actually do for a living?) because really, who needs hobbies when you can keep cosplaying as a devops after you are done playing one at work?.

This is also an excuse for me to play around with AI assisted coding for something more specific and long term than MVPs, quick scripts or fixes to already existing code.

All the other `.md` files in this repository are either fully written by LLMs or at least have a lot of AI assistance. This one you are reading now is and will be fully written by yours truly (I'll leave it up to you to decide whether that's a good or a bad thing). The code itself, whether written by LLMs, by me or a mix of both is audited and ran locally to validate.


## TL;DR of what I'm trying to accomplish with this.

Almost everything starts with [Packer](packer/) baking base VM templates (Ubuntu and Fedora for now) that get uploaded to Proxmox. [Terraform](terraform/README.md) clones those or other ready-made templates into the VMs and LXC containers that run my infrastructure, plus some cloud infrastructure (I may eventually add my Cloudflare settings here), and it generates the Ansible inventories. [Ansible](ansible/README.md) then provisions and configures systems: mainly VMs, Proxmox hosts and other servers, single board computers and things like that. It also provisions my k3s cluster. From there [Kubernetes](kubernetes/README.md) takes over: Flux does GitOps reconciliation and Renovate keeps charts and images from going stale. A bunch of pre-commit hooks do their best to keep me from pushing too much broken stuff.

I'm following a lot of good practices but this will _definitely_ be more of a bazaar than a cathedral.


| Layer | What lives there |
| --- | --- |
| [packer/](packer/) | Base VM image templates uploaded to Proxmox |
| [terraform/](terraform/README.md) | Reusable modules plus concrete VM, LXC, and cloud uses |
| [ansible/](ansible/README.md) | Roles and playbooks that configure everything above |
| [kubernetes/](kubernetes/README.md) | Flux-managed desired state for the cluster |
| [unraid/](unraid/AGENTS.md) | Unraid host settings, plugins, and Compose stacks; VM definitions stay in Terraform |
| [docs/](docs/README.md) | Decision record, runbooks, and agent workflow notes |


## Some practices that I actually like how they turned out

* **One source of truth for node topology.** Terraform generates the Ansible inventory for the K3s nodes (`terraform/instances/vm/k3s_nodes/` renders `ansible/inventories/k3s-nodes.yml`), so stuff is defined once instead of maintained in multiple places.
* **Registry peer sharing.** Every k3s node runs the embedded registry and serves its cached images to peer nodes over TCP `5001`, and any cache miss falls back to a direct upstream pull. I used `Harbor` for a while but the overhead and complexity it added was just not worth it for a small cluster.
* **SOPS for secrets and checks to ensure I don't push anything wrong.** Ansible, Packer, and Terraform retrieve secrets at runtime through read-only secret-helper flows; Kubernetes secrets are SOPS-encrypted `*.sops.yaml` files in Git; pre-commit hooks block key material and plaintext Secrets before being comitted.
* **Path-filtered validation.** CI selects checks by path. Root documentation and `docs/` changes don't trigger infrastructure jobs on their own, but Markdown edits inside an infrastructure directory can.


## Credits / Attribution

Here's a list of other projects, tools and code I'm using as inspiration or implementing here. In no particular order, and please let me know if I forget anything.

1. [bjw-s-labs' helm-charts](https://github.com/bjw-s-labs/helm-charts).
1. [kyuz0's strix halo toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes).
1. [mostlygeek's llama-swap](https://github.com/mostlygeek/llama-swap).
