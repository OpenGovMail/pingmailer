FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
EXPOSE 8891

# non root opendkim user
RUN groupadd -r opendkim && useradd -r -g opendkim -s /usr/sbin/nologin opendkim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    opendkim \
    opendkim-tools \
    openssl \
    ca-certificates \
    curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install yq for YAML parsing
RUN curl -L -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq

# Directories opendkim writes to at runtime. /etc/dkimkeys is also the PVC
# mountpoint; pre-creating it here is harmless and keeps non-PVC runs working.
RUN mkdir -p /etc/opendkim /var/run/opendkim /etc/dkimkeys

COPY ./entrypoint.sh /entrypoint.sh

# ---------------------------------------------------------------------------
# OpenShift compatibility: the platform runs the container as an ARBITRARY,
# non-root UID, but always with GID 0 (the root group). So:
#   * group-own everything by GID 0 and make writable dirs group-writable, and
#   * make the entrypoint world-executable (0755) so any UID can exec it
#     (the upstream image used 0750, which only UID 999 could exec -> the
#     "exec /entrypoint.sh: Permission denied" CrashLoopBackOff on OpenShift).
# This keeps the image runnable both as the opendkim user (Docker/compose)
# and as an arbitrary UID (OpenShift restricted-v2 SCC).
# ---------------------------------------------------------------------------
RUN chown -R opendkim:0 /etc/opendkim /var/run/opendkim /etc/dkimkeys /entrypoint.sh && \
    chmod -R g+rwX /etc/opendkim /var/run/opendkim /etc/dkimkeys && \
    chmod 0755 /entrypoint.sh

USER opendkim
ENTRYPOINT ["/entrypoint.sh"]
