#!/bin/bash
# Freqtrade NFI droplet bootstrap — runs as root via SSH
set -euxo pipefail

### 1. Swap (1 GB) ###
if ! swapon --show | grep -q swapfile; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
fi

### 2. Base packages ###
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  fail2ban unattended-upgrades apt-listchanges curl ca-certificates \
  git rsync ufw logrotate jq

### 3. Firewall (UFW) ###
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 8989/tcp comment 'Freqtrade API/UI'
ufw --force enable

### 4. Unattended upgrades ###
cat > /etc/apt/apt.conf.d/50unattended-upgrades.local <<'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
  "${distro_id}ESMApps:${distro_codename}-apps-security";
  "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

### 5. journald cap ###
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
MaxRetentionSec=7day
EOF
systemctl restart systemd-journald

### 6. freqtrade user ###
if ! id -u freqtrade >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G docker freqtrade
  mkdir -p /home/freqtrade/.ssh
  cp /root/.ssh/authorized_keys /home/freqtrade/.ssh/authorized_keys
  chown -R freqtrade:freqtrade /home/freqtrade/.ssh
  chmod 700 /home/freqtrade/.ssh
  chmod 600 /home/freqtrade/.ssh/authorized_keys
fi

### 7. Clone repo ###
sudo -u freqtrade -H bash <<'BASH'
set -eux
cd /home/freqtrade
if [ ! -d freqtrade-nfi ]; then
  git clone --depth 50 https://github.com/iterativv/NostalgiaForInfinity.git freqtrade-nfi
fi
BASH

### 8. logrotate for freqtrade logs ###
cat > /etc/logrotate.d/freqtrade <<'EOF'
/home/freqtrade/freqtrade-nfi/user_data/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 100M
    su freqtrade freqtrade
}
EOF

### 9. Weekly docker prune cron ###
cat > /etc/cron.d/docker-prune <<'EOF'
30 3 * * 0 root /usr/bin/docker system prune -af --filter "until=168h" --volumes >/var/log/docker-prune.log 2>&1
EOF
chmod 644 /etc/cron.d/docker-prune

### 10. fail2ban — defaults are fine for SSH ###
systemctl enable --now fail2ban

### 11. systemd unit for freqtrade docker compose ###
cat > /etc/systemd/system/freqtrade.service <<'EOF'
[Unit]
Description=Freqtrade NFI (docker compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=freqtrade
WorkingDirectory=/home/freqtrade/freqtrade-nfi
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable freqtrade.service

echo "BOOTSTRAP DONE"
