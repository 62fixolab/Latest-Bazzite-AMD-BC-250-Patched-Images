# 🎉 Sponsors

## Printer Tools App
[![Banner - Printer Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-printer-tools.png)](https://printertools.app)

## Scooter Tools App
[![Banner - Scooter Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-scooter-tools.png)](https://scootertools.app)

## AdMate App
[![Banner - AdMate App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-admate.png)](https://admate.dev)

## Table of Contents

- [Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE](#bazzite-amd-bc-250-patched-images-for-deck-gnome-and-kde)
  - [Origin](#origin)
  - [Images](#images)
  - [What changed from the original images](#what-changed-from-the-original-images)
  - [Before you install](#before-you-install)
  - [Installation](#installation)
  - [Post-install checks](#post-install-checks)
  - [Known BC-250 notes](#known-bc-250-notes)
    - [Sunshine](#sunshine)
    - [Deck UI micro-stutter](#deck-ui-micro-stutter)
    - [Temperature sensors](#temperature-sensors)
    - [GPU card naming](#gpu-card-naming)
    - [Power and thermals](#power-and-thermals)
  - [Updates](#updates)
  - [References](#references)

# Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE

[![Build Bazzite BC-250](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml/badge.svg)](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml)

Bazzite images for AMD BC-250 boards. This repository builds Deck, GNOME, and KDE variants from the current official Bazzite stable base and adds `cyan-skillfish-governor-smu` for BC-250 GPU frequency scaling and the `655%` GPU usage telemetry fix.

## Origin

This project is a consolidated continuation of the three original BC-250 patched image repositories by vietsman:

- [`vietsman/bazzite-deck-patched`](https://github.com/vietsman/bazzite-deck-patched)
- [`vietsman/bazzite-gnome-patched`](https://github.com/vietsman/bazzite-gnome-patched)
- [`vietsman/bazzite-kde-patched`](https://github.com/vietsman/bazzite-kde-patched)

Those images used Bazzite/Fedora 42, the old `vietsman/patched-kernel-bc250` COPR, and `oberon-governor`. This repository keeps the same three-image idea, but moves to the current Bazzite stable base and uses `cyan-skillfish-governor-smu`, which also fixes the BC-250 `gpu_metrics` bug that can make MangoHud/radeontop report `655%` GPU usage.

## Images

| Variant | Base image | Published image |
| --- | --- | --- |
| Deck | `ghcr.io/ublue-os/bazzite-deck:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest` |
| GNOME | `ghcr.io/ublue-os/bazzite-gnome:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-gnome:latest` |
| KDE | `ghcr.io/ublue-os/bazzite:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-kde:latest` |

All images are signed with cosign and include the signing policy needed for `ostree-image-signed`.

You can verify a published image with the public key in this repository:

```bash
cosign verify --key cosign.pub ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

## What changed from the original images

| Area | vietsman images | This repository |
| --- | --- | --- |
| Repository layout | One repo per image | One repo with three BlueBuild recipes |
| Base | Older pinned Bazzite/Fedora 42 base | Current Bazzite stable base |
| Kernel patching | `vietsman/patched-kernel-bc250` COPR | Current Bazzite kernel; no old kernel COPR |
| Governor | `oberon-governor` | `cyan-skillfish-governor-smu` |
| `655%` GPU usage bug | Not handled by Oberon | Fixed by the SMU governor's `gpu_metrics` bind-mount patch |
| Install ref | Signed `ghcr.io/vietsman/...` images | Signed `ghcr.io/62fixolab/...` images |

## Before you install

These images assume a BC-250 setup that is already healthy on stock Bazzite:

- Modified BIOS flashed, with P3.00 recommended by the community documentation.
- VRAM allocation set to 512 MB dynamic.
- IOMMU disabled in BIOS.
- Adequate cooling and airflow, especially over the rear VRAM chips.
- A PSU with enough 12 V headroom for gaming loads.
- Ethernet available during setup if you rely on USB Wi-Fi adapters.

Unlike older Fedora installs, Bazzite should boot on the BC-250 without `nomodeset`.

## Installation

If you previously enabled the old `vietsman/patched-kernel-bc250` COPR, disable it before rebasing. The repo only publishes old Fedora metadata and can make `rpm-ostree rebase` fail with a `404`:

```bash
sudo mkdir -p /etc/yum.repos.d.disabled
sudo mv /etc/yum.repos.d/*vietsman*patched-kernel-bc250*.repo /etc/yum.repos.d.disabled/
```

Choose the image you want:

```bash
# Deck
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest

# GNOME
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome:latest

# KDE
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde:latest
```

Then reboot:

```bash
systemctl reboot
```

## Post-install checks

Verify the active deployment and governor:

```bash
rpm-ostree status
systemctl status cyan-skillfish-governor-smu
```

Check that the GPU metrics fix is active:

```bash
journalctl -u cyan-skillfish-governor-smu -b --no-pager | grep -i "metrics"
```

The BC-250 GPU may appear as `card1` instead of `card0`, depending on the boot and display setup. Check both paths when verifying the frequency table:

```bash
cat /sys/class/drm/card0/device/pp_dpm_sclk
cat /sys/class/drm/card1/device/pp_dpm_sclk
```

MangoHud/radeontop should show normal GPU usage values instead of `655%`.

## Known BC-250 notes

### Sunshine

If Sunshine stops working after rebasing, reinstall its Bazzite integration:

```bash
ujust setup-sunshine
```

On newer Bazzite/Sunshine builds, the BC-250 can crash Sunshine with `status=139`/SIGSEGV when hardware encoding falls back through unsupported encoder paths such as Vulkan. If Sunshine crashes on startup, force software encoding first to confirm the service is otherwise healthy:

```bash
systemctl --user stop homebrew.sunshine.service
mkdir -p ~/.config/sunshine
sed -i '/^encoder *=/d;/^capture *=/d' ~/.config/sunshine/sunshine.conf 2>/dev/null || true
printf '\nencoder = software\ncapture = kms\n' >> ~/.config/sunshine/sunshine.conf
systemctl --user restart homebrew.sunshine.service
journalctl --user -u homebrew.sunshine.service -b -f
```

Then open the Sunshine UI at `https://localhost:47990` or `https://<host-ip>:47990`. This is safer than Vulkan on current BC-250 setups, but it uses CPU encoding; start with conservative Moonlight settings such as 1080p, 30 FPS, and 10-20 Mbps. VAAPI is the preferred long-term hardware encoder to retest after Sunshine, Mesa, or Bazzite updates.

### Deck UI micro-stutter

On some BC-250 Deck UI setups, Bazzite's Handheld Daemon can restart repeatedly because expected handheld hardware is not present. If you see consistent micro-stutters, disable and mask it:

```bash
sudo systemctl disable --now hhd
sudo systemctl mask hhd
```

### Temperature sensors

For read-only hardware monitoring:

```bash
echo 'nct6683' | sudo tee /etc/modules-load.d/nct6683.conf
echo 'options nct6683 force=true' | sudo tee /etc/modprobe.d/sensors.conf
systemctl reboot
```

For PWM fan control, use the `nct6687` module and follow the BC-250 sensor documentation.

### GPU card naming

The BC-250 GPU can appear as `card0` or `card1`. If a command fails with `No such file or directory`, try the other card path before assuming the governor is broken.

### Power and thermals

Higher GPU clocks increase power draw and heat. If your board is unstable, lower the maximum frequency or raise conservative voltage points in:

```text
/etc/cyan-skillfish-governor-smu/config.toml
```

Then restart the service:

```bash
sudo systemctl restart cyan-skillfish-governor-smu
```

## Updates

Images are checked daily against the current official Bazzite `stable` base digests. If Deck, GNOME, or KDE stable changes, GitHub Actions rebuilds and publishes the three patched images automatically.

For normal system updates after rebasing to one of these images:

```bash
ujust update
```

If an update breaks something:

```bash
rpm-ostree rollback
systemctl reboot
```

## References

- [Bazzite updates, rollbacks, and rebasing](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/)
- [Bazzite ujust commands](https://docs.bazzite.gg/Installing_and_Managing_Software/ujust/)
- [Bazzite Sunshine documentation](https://docs.bazzite.gg/Advanced/sunshine/)
- [`filippor/cyan-skillfish-governor`](https://github.com/filippor/cyan-skillfish-governor)
- [`elektricM/amd-bc250-docs`](https://github.com/elektricM/amd-bc250-docs)
