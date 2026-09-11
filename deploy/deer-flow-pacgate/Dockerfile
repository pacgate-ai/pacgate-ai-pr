# Deer-flow wrapper image for Pacgate-ai
# Layers the pacgate_deerflow_adapter on top of deer-flow's published backend image.
# Never forks deer-flow source — the adapter is pip-installed on top.

FROM ghcr.io/bytedance/deer-flow-backend@sha256:e7c503a803c99a039e08da61359932877a9e0d0196799429698244117338af13

# Copy the adapter package
COPY pacgate-adapters/python/pacgate_deerflow_adapter /app/adapters/pacgate_deerflow_adapter

# Install the adapter package globally and also expose the copied source tree on
# PYTHONPATH, because DeerFlow itself runs from /app/backend via `uv run --no-sync`.
RUN pip install --no-cache-dir /app/adapters/pacgate_deerflow_adapter

# Pacgate: bake the document-conversion CLI so the agent's sandbox bash tool can
# convert generated markdown to docx/pdf/html/txt (the MD->docx/pdf direction).
# pandoc is the office-cli (MD->docx/html/txt); weasyprint is its PDF engine
# (MD->pdf). Both land in /usr/bin, which is on the agent's bash PATH and in the
# sandbox system-path allowlist, so the agent can call them directly. markitdown
# (PDF/DOCX/PPTX/XLSX -> MD) is already in the image venv at
# /app/backend/.venv/bin and is reachable via the pacgate_convert_document MCP
# tool. apt-get update is required because the base image's package lists are
# not refreshed at build time.
RUN apt-get update && apt-get install -y --no-install-recommends pandoc weasyprint \
    && rm -rf /var/lib/apt/lists/*

# Pacgate: expose markitdown on the agent's PATH. markitdown lives in the image
# venv (/app/backend/.venv/bin) which is NOT on the agent's bash PATH and whose
# absolute path is blocked by the sandbox path-validation allowlist. Symlinking
# it into /usr/local/bin (on PATH + in the allowlist) lets the agent run
# `markitdown <file>` directly for PDF/DOCX/PPTX/XLSX -> MD on demand.
RUN ln -sf /app/backend/.venv/bin/markitdown /usr/local/bin/markitdown

# Ship a minimal startup-safe DeerFlow config. This keeps the wrapper bootable
# on a clean machine; runtime env can still override the memory backend inputs.
COPY deploy/deer-flow-pacgate/config.yaml /app/backend/config.yaml

# The adapter package is installed here and enabled via config.yaml. For actual
# Pacgate-backed memory, pass PACGATE_API_EMAIL/PASSWORD or PACGATE_JWT_TOKEN
# plus PACGATE_MATTER_ID at runtime.
ENV DEER_FLOW_CONFIG_PATH=/app/backend/config.yaml
ENV PYTHONPATH=/app/adapters:/app/backend
ENV PACGATE_API_URL=http://pacgate-api:8080
ENV PACGATE_TENANT_ID=default-firm

# Keep deer-flow's original startup command unchanged
CMD ["sh", "-c", "cd backend && uv run --no-sync uvicorn app.gateway.app:app --host 0.0.0.0 --port 8001"]