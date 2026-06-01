# 🎉 Sponsors

## Printer Tools App
[![Banner - Printer Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-printer-tools.png)](https://printertools.app)

## Scooter Tools App
[![Banner - Scooter Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-scooter-tools.png)](https://scootertools.app)

## AdMate App
[![Banner - AdMate App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-admate.png)](https://admate.dev)

# bazzite-bc250-patched

[![bluebuild build badge](https://github.com/62fixolab/bazzite-bc250-patched/actions/workflows/build.yml/badge.svg)](https://github.com/62fixolab/bazzite-bc250-patched/actions/workflows/build.yml)

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
| Deck | `ghcr.io/ublue-os/bazzite-deck:stable` | `ghcr.io/62fixolab/bazzite-bc250-deck-patched:latest` |
| GNOME | `ghcr.io/ublue-os/bazzite-gnome:stable` | `ghcr.io/62fixolab/bazzite-bc250-gnome-patched:latest` |
| KDE | `ghcr.io/ublue-os/bazzite:stable` | `ghcr.io/62fixolab/bazzite-bc250-kde-patched:latest` |

All images are built unsigned, so installation uses `ostree-unverified-registry`.

## What changed from the original images

| Area | vietsman images | This repository |
| --- | --- | --- |
| Repository layout | One repo per image | One repo with three BlueBuild recipes |
| Base | Older pinned Bazzite/Fedora 42 base | Current Bazzite stable base |
| Kernel patching | `vietsman/patched-kernel-bc250` COPR | Current Bazzite kernel; no old kernel COPR |
| Governor | `oberon-governor` | `cyan-skillfish-governor-smu` |
| `655%` GPU usage bug | Not handled by Oberon | Fixed by the SMU governor's `gpu_metrics` bind-mount patch |
| Install ref | Signed `ghcr.io/vietsman/...` images | Unsigned `ghcr.io/62fixolab/...` images |

## Installation

If you previously enabled the old `vietsman/patched-kernel-bc250` COPR, disable it before rebasing. The repo only publishes old Fedora metadata and can make `rpm-ostree rebase` fail with a `404`:

```bash
sudo mkdir -p /etc/yum.repos.d.disabled
sudo mv /etc/yum.repos.d/*vietsman*patched-kernel-bc250*.repo /etc/yum.repos.d.disabled/
```

Choose the image you want:

```bash
# Deck
rpm-ostree rebase ostree-unverified-registry:ghcr.io/62fixolab/bazzite-bc250-deck-patched:latest

# GNOME
rpm-ostree rebase ostree-unverified-registry:ghcr.io/62fixolab/bazzite-bc250-gnome-patched:latest

# KDE
rpm-ostree rebase ostree-unverified-registry:ghcr.io/62fixolab/bazzite-bc250-kde-patched:latest
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

## Updates

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
- [`filippor/cyan-skillfish-governor`](https://github.com/filippor/cyan-skillfish-governor)
- [`elektricM/amd-bc250-docs`](https://github.com/elektricM/amd-bc250-docs)
