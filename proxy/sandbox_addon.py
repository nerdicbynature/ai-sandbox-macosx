"""mitmproxy addon for the AI sandbox.

1. Exports the public CA certificate to /ca-public (mounted read-only into the sandbox).
2. Writes a compact access log to stdout (`docker compose logs -f proxy`),
   including upstream errors.
3. Optional host allowlist via ALLOWED_HOSTS (comma-separated,
   "*.example.com" also matches subdomains). Empty = everything allowed.
4. Optional: saves all flows to /flows/flows.mitm when MITM_SAVE_FLOWS=1.
5. Optional: hosts matching MITM_IGNORE_HOSTS (comma-separated regexes) are not
   decrypted but passed through as plain TLS, e.g. Kubernetes APIs that use
   client certificates, or services with certificate pinning.
"""

import os
import shutil
from pathlib import Path

from mitmproxy import ctx, http
from mitmproxy.certs import CertStore

CA_PUBLIC = Path("/ca-public/mitmproxy-ca-cert.pem")


def _split(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def _allowed(host: str, allowlist: list[str]) -> bool:
    if not allowlist:
        return True
    host = host.lower().rstrip(".")
    for pattern in allowlist:
        if pattern.startswith("*."):
            if host.endswith(pattern[1:]) or host == pattern[2:]:
                return True
        elif host == pattern:
            return True
    return False


class SandboxAddon:
    def __init__(self) -> None:
        self.allowlist = [h.lower() for h in _split(os.environ.get("ALLOWED_HOSTS", ""))]

    def running(self) -> None:
        # mitmproxy may write its CA lazily; make sure it exists before exporting.
        confdir = Path(ctx.options.confdir).expanduser()
        CertStore.from_store(confdir, "mitmproxy", ctx.options.key_size)
        tmp = CA_PUBLIC.with_suffix(".tmp")
        shutil.copyfile(confdir / "mitmproxy-ca-cert.pem", tmp)
        tmp.replace(CA_PUBLIC)
        ctx.log.info(f"Exported CA certificate to {CA_PUBLIC}")

        if os.environ.get("MITM_SAVE_FLOWS") == "1":
            ctx.options.update(save_stream_file="+/flows/flows.mitm")
            ctx.log.info("Saving flows to /flows/flows.mitm")

        ignore = _split(os.environ.get("MITM_IGNORE_HOSTS", ""))
        if ignore:
            ctx.options.update(ignore_hosts=ignore)
            ctx.log.info(f"TLS passthrough for: {', '.join(ignore)}")

        if self.allowlist:
            ctx.log.info(f"Allowlist active: {', '.join(self.allowlist)}")

    def _block(self, flow: http.HTTPFlow, host: str) -> None:
        flow.response = http.Response.make(
            403,
            f"Blocked by ai-sandbox proxy: {host} is not in ALLOWED_HOSTS\n",
            {"Content-Type": "text/plain"},
        )
        print(f"[BLOCK] {flow.request.method} {host}", flush=True)

    def http_connect(self, flow: http.HTTPFlow) -> None:
        if not _allowed(flow.request.host, self.allowlist):
            self._block(flow, flow.request.host)

    def request(self, flow: http.HTTPFlow) -> None:
        if flow.response is None and not _allowed(flow.request.pretty_host, self.allowlist):
            self._block(flow, flow.request.pretty_host)

    def response(self, flow: http.HTTPFlow) -> None:
        req, res = flow.request, flow.response
        size = len(res.raw_content or b"") if res else 0
        status = res.status_code if res else "-"
        print(f"[{status}] {req.method} {req.pretty_url} ({size} B)", flush=True)

    def error(self, flow: http.HTTPFlow) -> None:
        print(f"[ERROR] {flow.request.method} {flow.request.pretty_url}: {flow.error}", flush=True)


addons = [SandboxAddon()]
