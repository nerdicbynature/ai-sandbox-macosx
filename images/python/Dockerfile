# syntax=docker/dockerfile:1.7
#
# Python sub-sandbox, built ON TOP of the sandbox image.
# "sandbox-base" comes from docker compose (additional_contexts: service:sandbox).

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM sandbox-base

ARG PYTHON_VERSION=3.13

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3-dev python3-venv python3-pip pipx \
      libffi-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
      libsqlite3-dev liblzma-dev libxml2-dev libxslt1-dev \
 && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

# Install the Python interpreter and CLI tools system-wide (root-owned)
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_LINK_MODE=copy

RUN uv python install "${PYTHON_VERSION}" \
 && for t in ruff mypy pyright pytest ipython pre-commit poetry nox tox; do \
      uv tool install --python "${PYTHON_VERSION}" "$t"; \
    done \
 && chmod -R a+rX /opt/uv \
 && rm -rf /root/.cache

# Runtime: caches and additional interpreters go to the home volume
# (more Python versions: UV_PYTHON_INSTALL_DIR=~/.local/share/uv/python uv python install 3.12)
ENV UV_CACHE_DIR=/home/dev/.cache/uv \
    UV_PYTHON_PREFERENCE=managed \
    UV_PYTHON=${PYTHON_VERSION} \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

USER dev
WORKDIR /workspace
