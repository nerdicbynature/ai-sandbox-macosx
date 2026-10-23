# MITM proxy for the sandbox. The only container with internet access.
ARG MITMPROXY_IMAGE=mitmproxy/mitmproxy:12
FROM ${MITMPROXY_IMAGE}

# /ca-public holds ONLY the public CA certificate (no private key) and is
# mounted read-only into the sandbox.
RUN install -d -o mitmproxy -g mitmproxy /ca-public /flows /addons
COPY --chown=mitmproxy:mitmproxy sandbox_addon.py /addons/sandbox_addon.py

# Start directly as the unprivileged user (bypassing the gosu entrypoint),
# so the container can run without any capabilities.
USER mitmproxy
ENV HOME=/home/mitmproxy
WORKDIR /home/mitmproxy

EXPOSE 8080 8081
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=12 \
  CMD test -s /ca-public/mitmproxy-ca-cert.pem

ENTRYPOINT ["mitmweb"]
CMD ["--mode", "regular@8080", "--web-host", "0.0.0.0", "--web-port", "8081", \
     "--no-web-open-browser", "-s", "/addons/sandbox_addon.py"]
