#!/bin/bash -e

# Customizes an L4T rootfs for use as a MergeTB testbed image.
# Runs inside a chroot of /build/Linux_for_Tegra/rootfs (proc/sys/dev pre-mounted).

echo 'nameserver 8.8.8.8' > /etc/resolv.conf

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ethtool \
    tcpdump \
    openssh-server \
    systemd-resolved \
    ca-certificates \
    gdisk \
    cloud-guest-utils \
    e2fsprogs

# Journald: persistent, capped
cat > /etc/systemd/journald.conf << 'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=100M
EOF
mkdir -p /var/log/journal

# Reduce systemd manager log noise
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/01-loglevel.conf << 'EOF'
[Manager]
LogLevel=info
EOF

# Quiet KERN_WARNING and below from the console. The specific motivation is
# the NVMe uuid_show "providing old NGUID" warning fired by Crucial P310
# (and other consumer NVMe SSDs that don't expose a UUID NID descriptor —
# `nvme id-ns-descs` shows only EUI64) every time udev re-evaluates the
# block device: one warning per partition per partprobe-style event, so
# ~10 visible warnings per resize/stamp/uevent on a 16-partition Jetson.
# The device can't be given a UUID (controller doesn't support NS
# Management) so the kernel branch is steady-state for our hardware.
# Demoting console_loglevel to 4 keeps EMERG/ALERT/CRIT/ERR visible on
# the console; KERN_WARNING and below stay in dmesg/journal for debug.
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/01-quiet-console.conf << 'EOF'
# console_loglevel default_message_loglevel minimum_console_loglevel default_console_loglevel
kernel.printk = 4 4 1 7
EOF

# SSH: skip reverse DNS
echo "UseDNS no" >> /etc/ssh/sshd_config

# Regenerate machine-id on first boot
cat > /etc/systemd/system/machine-id-init.service << 'EOF'
[Unit]
Description=Initialize machine id

[Service]
Type=oneshot
ExecStart=/bin/systemd-machine-id-setup

[Install]
WantedBy=multi-user.target
EOF

# foundryc service
cat > /lib/systemd/system/foundryc.service << 'EOF'
[Unit]
Description=Foundry client
Documentation=https://gitlab.com/mergetb/tech/foundry

[Service]
ExecStart=/usr/local/bin/foundryc
Type=simple
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# node_exporter service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# fstab: rootfs by PARTUUID (set by create-merge-jetson-image.sh post-processing)
cat > /etc/fstab << 'EOF'
PARTUUID=a0000000-0000-0000-0000-00000000000a / ext4 defaults,noatime 0 1
EOF

# Authorize testbed SSH key for the test user
mkdir -p /home/test/.ssh
chmod 700 /home/test/.ssh
cat > /home/test/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB9HQ/r3cMtGTJfOKRklWR32Y6TG43E8OIav4yYEeXSA test@cloud-init.mergetb
EOF
chmod 600 /home/test/.ssh/authorized_keys
chown -R test:test /home/test/.ssh

# foundryc binary (arm64) pinned to v1.1.7
curl -fL "https://gitlab.com/api/v4/projects/11436163/jobs/artifacts/v1.1.7/raw/build/foundryc-arm64?job=make" \
    -o /usr/local/bin/foundryc
chmod 755 /usr/local/bin/foundryc

# node_exporter (arm64)
NODE_EXPORTER_VERSION="1.8.2"
cd /tmp
curl -fL -O "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64.tar.gz"
cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64/node_exporter" /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
useradd -r -s /sbin/nologin node_exporter || true
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-arm64"*

systemctl enable machine-id-init.service
systemctl enable foundryc.service
systemctl enable node_exporter.service
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable resizerootfs.service
# Jetson Orin debug UART
systemctl enable serial-getty@ttyTCU0.service || true

rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id

# Resolve via systemd-resolved at runtime
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

apt-get clean
rm -rf /var/lib/apt/lists/*
