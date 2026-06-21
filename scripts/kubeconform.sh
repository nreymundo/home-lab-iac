#!/usr/bin/env bash
set -euo pipefail

readonly KUBERNETES_ROOT="kubernetes"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

command_exists git || { echo "ERROR: git is required." >&2; exit 1; }
command_exists kubectl || { echo "ERROR: kubectl is required." >&2; exit 1; }
command_exists kubeconform || { echo "ERROR: kubeconform is required." >&2; exit 1; }

if [[ ! -d "$KUBERNETES_ROOT" ]]; then
  echo "ERROR: run this script from the repository root." >&2
  exit 1
fi

tmp_manifest="$(mktemp --suffix=.yaml)"
trap 'rm -f "$tmp_manifest"' EXIT

mapfile -t kustomizations < <(git ls-files "$KUBERNETES_ROOT/**/kustomization.yaml" | sort)

if [[ ${#kustomizations[@]} -eq 0 ]]; then
  echo "No Kubernetes kustomizations found."
  exit 0
fi

for kustomization in "${kustomizations[@]}"; do
  dir="${kustomization%/*}"
  echo "Building $dir"
  kubectl kustomize "$dir" >>"$tmp_manifest"
  printf '\n---\n' >>"$tmp_manifest"
done

kubeconform \
  -ignore-missing-schemas \
  -summary \
  "$tmp_manifest"
