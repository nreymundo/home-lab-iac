# Kubernetes GitOps

This folder is managed with Flux. Charts, configs, and other installs are defined in Git
and continuously reconciled to the cluster in a GitOps workflow.

If the cluster needs to be recreated from scratch, bootstrap Flux manually using the Flux CLI to re-establish the GitOps sync. For example:

    flux bootstrap github \
      --owner=nreymundo \
      --repository=home-lab-iac \
      --branch=master \
      --path=./kubernetes/clusters/homelab \
      --private-key-file=<path-to-your-ssh-key>

For more information, see the [Flux bootstrap documentation](https://fluxcd.io/flux/cmd/flux_bootstrap_github/).
