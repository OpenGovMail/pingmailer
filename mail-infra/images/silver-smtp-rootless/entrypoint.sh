#!/bin/bash
set -e

CONFIG_FILE="/etc/postfix/silver.yaml"

# --- domain from silver.yaml -------------------------------------------------
MAIL_DOMAIN=$(awk '/^[[:space:]]*-[[:space:]]*domain:/ {sub(/^[[:space:]]*-[[:space:]]*domain:[[:space:]]*/, ""); print; exit}' "$CONFIG_FILE")
if [ -z "$MAIL_DOMAIN" ] || [ "$MAIL_DOMAIN" = "null" ]; then
    echo "⚠️  Could not extract domain from $CONFIG_FILE; using example.org"
    MAIL_DOMAIN="example.org"
fi
export MAIL_DOMAIN
MAIL_HOSTNAME=${MAIL_HOSTNAME:-mail.$MAIL_DOMAIN}
echo "Using domain: $MAIL_DOMAIN"
echo "$MAIL_DOMAIN" > /etc/mailname 2>/dev/null || true

# --- single-UID rootless setup ----------------------------------------------
# OpenShift runs us as a random non-root UID (GID 0) with no /etc/passwd entry.
# Postfix's mail_owner must resolve to a real user whose UID == our UID, and
# whose primary group has no OTHER members (Postfix rejects shared groups).
# We register both in the (group-writable) /etc/passwd + /etc/group.
UID0="$(id -u)"
OWNER_GID=$((UID0 % 60000 + 2000))   # a deterministic, almost-certainly-unique gid
if ! getent group "$OWNER_GID" >/dev/null 2>&1; then
    echo "postfixown:x:${OWNER_GID}:" >> /etc/group
fi
if ! getent passwd "$UID0" >/dev/null 2>&1; then
    echo "postfixown:x:${UID0}:${OWNER_GID}:Postfix owner:/var/spool/postfix:/usr/sbin/nologin" >> /etc/passwd
fi
RUN_USER="$(getent passwd "$UID0" | cut -d: -f1)"
echo "Running as uid=$UID0 user=$RUN_USER gid=$(id -g) groups=$(id -G)"

# mail_owner = our UID (its private group has no other members, which Postfix
# requires). setgid_group = the package's dedicated `postdrop` group: Postfix
# rejects a privileged (low) GID like root/0 here. The setgid maildrop/postdrop
# path is unused (mail arrives via smtpd on the network), so we don't need to
# actually belong to it — it only has to pass Postfix's startup validation.
postconf -e "myhostname = ${MAIL_HOSTNAME}"
postconf -e "mail_owner = ${RUN_USER}"
postconf -e "setgid_group = postdrop"
postconf -e "queue_directory = /var/spool/postfix"
postconf -e "data_directory = /var/lib/postfix"

# Recreate the queue tree (the PVC mounts empty over /var/spool/postfix).
for d in active bounce corrupt defer deferred flush hold incoming saved trace \
         private public maildrop pid; do
    mkdir -p "/var/spool/postfix/$d"
done

# set-permissions now works: chown targets are us / a group we're in. Errors on
# the setgid postdrop/postqueue binaries (need real root) are non-fatal — the
# maildrop/local-submission path is unused; mail arrives via smtpd on :25.
postfix set-permissions 2>&1 || true
postfix check 2>&1 || true

echo "=== Starting Postfix (foreground, rootless single-UID, no chroot) ==="
exec postfix start-fg
