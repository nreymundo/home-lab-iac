# Kubernetes GitOps

This folder is managed with Flux. Charts, configs, and other installs are defined in Git
and continuously reconciled to the cluster in a GitOps workflow.

If the cluster needs to be recreated from scratch, bootstrap Flux manually using the Flux CLI
to re-establish the GitOps sync.
