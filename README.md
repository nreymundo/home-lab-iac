# Home Lab / Servers - IaC

This is like my 5th attempt at trying to bring some order to the chaotic mess that is my home lab.

I started with docker compose in a Raspberry Pi, then moved to Unraid and a _lot_ of click ops, eventually I moved to Proxmox with still a lot of click ops and _some_ scripting. Now I'm trying to do it the proper professional way (You know, what I actually do for a living?) because really, who needs hobbies when you can keep cosplaying as a devops after you are done playing one at work?.

This is also an excuse for me to play around with AI assisted coding for something more specific and long term than MVPs, quick scripts or fixes to already existing code.

All the other `.md` files in this repository are either fully written by LLMs or at least have a lot of AI assistance. This one you are reading now is and will be fully written by yours truly (I'll leave it up to you to decide whether that's a good or a bad thing). The code itself, whether written by LLMs, by me or a mix of both is audited and ran locally to validate.


## TL;DR of what I'm trying to accomplish with this.

* Ansible to provision and configure systems. Mainly VMs, Proxmox hosts and other servers, single board computers and things like that. It also provisions my k3s cluster.
* Packer creates base images that I then upload to Proxmox so I can spin up VMs based on them.
* Terraform to create the VMs that I then use for my k3s node. Will eventually add my Cloudflare settings here.
* The Kubernetes folder uses Flux for GitOps and Renovate to keep things up to date.
* Bunch of pre-commit hooks to try not to push _that_ much broken crap.


I'm following a lot of good practices but this will _definitely_ be more of a bazaar than a cathedral.
