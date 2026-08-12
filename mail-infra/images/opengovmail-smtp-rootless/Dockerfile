# =============================================================================
# opengovmail-smtp (rootless / patched Postfix) for OpenShift restricted-v2.
#
# WHY: OpenShift policy here forbids running as root, but stock Postfix's
# `postfix`, `master`, and `postsuper` binaries hard-abort unless getuid()==0
# (verified in Postfix 3.7 source: postfix.c, master.c, postsuper.c). We
# rebuild Debian's exact Postfix package with those THREE checks neutralized
# so the binaries run as an arbitrary non-root UID. getuid() itself is left
# honest, so master.c's `set_ugid(getuid(), getgid())` keeps the real UID and
# Postfix runs single-UID (no privilege separation, no setuid attempts).
#
# Everything else (config, sqlite/TLS/pcre maps, dynamicmaps) comes from the
# unmodified Debian package build, so module parity with the stock image holds.
# =============================================================================

# ----------------------------------------------------------------------------
# Stage 1 — rebuild Postfix from Debian source with the 3 root checks removed
# ----------------------------------------------------------------------------
FROM debian:bookworm AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Enable deb-src so `apt-get source` works (bookworm uses the deb822 format).
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends dpkg-dev devscripts && \
    apt-get build-dep -y postfix

WORKDIR /build
RUN apt-get source postfix

# Neutralize the three getuid() superuser guards. getuid() is left intact
# everywhere else (notably master.c's set_ugid call).
RUN set -eux; \
    src="$(find . -maxdepth 1 -type d -name 'postfix-*')"; \
    cd "$src"; \
    # --- (1) Root-requirement CHECKS: neutralize the getuid()==0 guards ---
    # master.c : if (getuid() != 0) msg_fatal("the master command is reserved...")
    sed -i 's/if (getuid() != 0)/if (0)/' src/master/master.c; \
    # postfix.c : if (getuid() != 0) { ... msg_fatal("the postfix command is reserved...") }
    sed -i 's/if (getuid() != 0)/if (0)/' src/postfix/postfix.c; \
    # postsuper.c : if (getuid()) msg_fatal("use of this command is reserved...")
    sed -i 's/if (getuid())/if (0)/' src/postsuper/postsuper.c; \
    grep -q 'if (0)' src/master/master.c; \
    grep -q 'if (0)' src/postfix/postfix.c; \
    grep -q 'if (0)' src/postsuper/postsuper.c; \
    # --- (2) Privilege-SWITCHING: set_eugid()/set_ugid() begin with seteuid(0)
    # to regain root before switching users. A non-root process can't do that
    # and aborts. We run single-UID (== mail_owner), so no switch is needed:
    # make both no-op when the real UID is already non-root. ---
    # Insert an early-return guard just before each function's existing
    # `if (geteuid() != 0)` line (unique per file, indented with tabs). This
    # makes the function a no-op when the real UID is non-root, BEFORE any
    # seteuid/setgid/setuid is attempted.
    for f in set_eugid set_ugid; do \
        sed -i 's@^\([[:space:]]*\)if (geteuid() != 0)@\1if (getuid() != 0)\n\1    return;\n\1if (geteuid() != 0)@' "src/util/$f.c"; \
        grep -q 'if (getuid() != 0)' "src/util/$f.c"; \
    done; \
    # --- (3) Daemon privilege-drop: chroot_uid() does a direct setgid/setuid to
    # the mail user when spawning each daemon. Guard both with getuid()==0 so a
    # non-root single-UID run skips them (chroot itself is untouched; root_dir is
    # null because every master.cf service has chroot=n). ---
    sed -i 's/if (user_name != 0)/if (user_name != 0 \&\& getuid() == 0)/' src/util/chroot_uid.c; \
    test "$(grep -c 'getuid() == 0' src/util/chroot_uid.c)" = "2"; \
    dpkg-buildpackage -us -uc -b

# ----------------------------------------------------------------------------
# Stage 2 — slim runtime, mirrors the stock opengovmail-smtp image
# ----------------------------------------------------------------------------
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=builder /build/postfix_*.deb /build/postfix-sqlite_*.deb /tmp/debs/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        wget \
        sqlite3 \
        libsqlite3-0 \
        mailutils \
        iputils-ping \
        /tmp/debs/postfix_*.deb \
        /tmp/debs/postfix-sqlite_*.deb && \
    if ! grep -q "^sqlite" /etc/postfix/dynamicmaps.cf; then \
        echo "sqlite    postfix-sqlite.so    dict_sqlite_open" >> /etc/postfix/dynamicmaps.cf; \
    fi && \
    wget -O /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq && \
    rm -rf /tmp/debs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/data /etc/postfix/sqlite /var/spool/postfix /var/lib/postfix

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# OpenShift arbitrary-UID support: the pod runs as a random non-root UID with
# GID 0. Group-own everything Postfix reads/writes by GID 0 with group perms
# mirroring owner, and make /etc/passwd + /etc/group writable so the entrypoint
# can register the runtime UID as Postfix's mail_owner.
RUN chgrp -R 0 /etc/postfix /var/spool/postfix /var/lib/postfix /app /etc/passwd /etc/group && \
    chmod -R g=u /etc/postfix /var/spool/postfix /var/lib/postfix /app && \
    chmod g=u /etc/passwd /etc/group && \
    touch /etc/mailname && chgrp 0 /etc/mailname && chmod g=u /etc/mailname

WORKDIR /app
ENTRYPOINT ["/entrypoint.sh"]
