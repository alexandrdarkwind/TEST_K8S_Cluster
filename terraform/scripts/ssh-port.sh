#!/bin/bash
set -eu
SSH_PORT=${SSH_PORT:-}

echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
systemctl restart sshd

mkdir -p /local/certs
