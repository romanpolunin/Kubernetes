set -ex

# Disable non-essential services to minimize resource usage
echo "Disabling non-essential services..."

# Disable snapd services (often resource-intensive)
sudo systemctl disable --now snapd.service snapd.socket snapd.seeded.service || true
sudo systemctl mask snapd.service || true

# Disable cloud-init services (not needed after initial setup)
sudo systemctl disable --now cloud-config.service cloud-final.service cloud-init-local.service || true

# Disable other common resource-consuming services
sudo systemctl disable --now ModemManager.service || true
sudo systemctl disable --now packagekit.service || true
sudo systemctl disable --now apt-daily.service apt-daily.timer || true
sudo systemctl disable --now apt-daily-upgrade.service apt-daily-upgrade.timer || true
sudo systemctl disable --now unattended-upgrades.service || true

# Disable timesyncd (if you're using other time synchronization)
# systemctl disable --now systemd-timesyncd.service || true

# Reduce journald resource usage
sudo sed -i '/^\[Journal\]/,/^$/ {
  s/^#\{0,1\}Storage=.*/Storage=volatile/
  s/^#\{0,1\}RuntimeMaxUse=.*/RuntimeMaxUse=64M/
  s/^#\{0,1\}SystemMaxUse=.*/SystemMaxUse=64M/
}' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

echo 'Done disabling non-essential services'