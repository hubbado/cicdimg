#!/usr/bin/env bash

set -e

get_kustomize() {
  curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases \
    | grep browser_download_url \
    | grep -E "linux.*amd" \
    | cut -d '"' -f 4 \
    | grep /kustomize/v \
    | sort | tail -n 1 \
    | xargs -n 1 curl -o kustomize-dl.tgz -L
    tar -xzf kustomize-dl.tgz -C /bin && \
    chmod +x /bin/kustomize
}
