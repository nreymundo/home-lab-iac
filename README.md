# Provisioning Proxmox VMs with Terraform and Ansible

( I suck at titles, right? )

This is an attempt at writing proper Infrastructure-as-Code for some of the services I want to run in my home lab. It is also a way to kick myself into action and finally learn some Ansible. 

There's really not much at the moment. Mainly a collection of Ansible roles (some created by me, some imported) and enough of a Terraform structure to be able to spin things up quickly on my Proxmox nodes. To do that I'm using [this Proxmox provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs) for Terraform. 

The `VMs` folder contains a template for quick copy/pasting when creating a new one and a `wireguard` one that installs all the neecessary software, creates a new set of private/public keys on the spot and sets the new VM to be able to forward internet traffic. It does not set up any peers and that has to be done manually afterwards. 