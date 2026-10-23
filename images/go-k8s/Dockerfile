# syntax=docker/dockerfile:1.7
#
# Go + Kubernetes sub-sandbox, built ON TOP of the sandbox image.
# "sandbox-base" comes from docker compose (additional_contexts: service:sandbox).
# Standalone: docker build --build-context sandbox-base=docker-image://ai-sandbox:latest images/go-k8s
#
# Versions: "latest" is resolved at build time; for reproducible builds pin
# versions via --build-arg (e.g. GO_VERSION=1.26.2).

FROM sandbox-base

ARG TARGETARCH
ARG GO_VERSION=latest
ARG KUBECTL_VERSION=latest
ARG HELM_VERSION=latest

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Prints the tag of the latest GitHub release (no API rate limit)
RUN printf '%s\n' '#!/bin/sh' \
      'curl -fsSLI -o /dev/null -w "%{url_effective}" "https://github.com/$1/releases/latest" | sed "s#.*/tag/##"' \
      > /usr/local/bin/gh-latest-tag && chmod +x /usr/local/bin/gh-latest-tag

# --- Go ---------------------------------------------------------------------
RUN v="${GO_VERSION}"; [ "$v" = latest ] && v="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//')"; \
    curl -fsSL "https://go.dev/dl/go${v}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xz \
 && /usr/local/go/bin/go version

ENV GOROOT=/usr/local/go \
    GOPATH=/home/dev/go \
    PATH=/home/dev/go/bin:/usr/local/go/bin:${PATH}

# --- Kubernetes CLIs (binaries) -----------------------------------------------
RUN v="${KUBECTL_VERSION}"; [ "$v" = latest ] && v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${v}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod 0755 /usr/local/bin/kubectl && kubectl version --client

RUN v="${HELM_VERSION}"; [ "$v" = latest ] && v="$(gh-latest-tag helm/helm)"; \
    curl -fsSL "https://get.helm.sh/helm-${v}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin --strip-components=1 "linux-${TARGETARCH}/helm" \
 && helm version

RUN curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin k9s \
 && curl -fsSLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
 && chmod 0755 /usr/local/bin/yq /usr/local/bin/k9s

# --- Go tools + K8s tools via go install---------------------------------
RUN export GOPATH=/tmp/gopath GOBIN=/usr/local/bin GOCACHE=/tmp/gocache \
 && go install golang.org/x/tools/gopls@latest \
 && go install golang.org/x/tools/cmd/goimports@latest \
 && go install github.com/go-delve/delve/cmd/dlv@latest \
 && go install honnef.co/go/tools/cmd/staticcheck@latest \
 && go install golang.org/x/vuln/cmd/govulncheck@latest \
 && go install gotest.tools/gotestsum@latest \
 && go install mvdan.cc/gofumpt@latest \
 && go install sigs.k8s.io/kustomize/kustomize/v5@latest \
 && go install github.com/ahmetb/kubectx/cmd/kubectx@latest \
 && go install github.com/ahmetb/kubectx/cmd/kubens@latest \
 && go install github.com/stern/stern@latest \
 && go install github.com/yannh/kubeconform/cmd/kubeconform@latest \
 && go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest \
 && rm -rf /tmp/gopath /tmp/gocache

RUN curl -fsSL https://golangci-lint.run/install.sh | sh -s -- -b /usr/local/bin \
 && golangci-lint --version

USER dev
WORKDIR /workspace
