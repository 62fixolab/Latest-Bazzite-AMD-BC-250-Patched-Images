# 🎉 Sponsors

## Printer Tools App
[![Banner - Printer Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-printer-tools.png)](https://printertools.app)

## Scooter Tools App
[![Banner - Scooter Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-scooter-tools.png)](https://scootertools.app)

## AdMate App
[![Banner - AdMate App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-admate.png)](https://admate.dev)

## Table of Contents

- [Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE](#bazzite-amd-bc-250-patched-images-for-deck-gnome-and-kde)
  - [What is this?](#what-is-this)
  - [Which image should I use?](#which-image-should-i-use)
  - [Install](#install)
  - [After install](#after-install)
  - [Experimental 40CU images](#experimental-40cu-images)
  - [Common fixes](#common-fixes)
  - [Updates and rollback](#updates-and-rollback)
  - [What changed from vietsman](#what-changed-from-vietsman)
  - [References](#references)

# Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE

[![Build Bazzite BC-250](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml/badge.svg)](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml)

## What is this?

Current Bazzite images for AMD BC-250 boards. This is not a Bazzite fork; it is current official Bazzite `stable` plus BC-250-specific setup.

They use the official Bazzite `stable` base and add the BC-250 pieces most users need:

- `cyan-skillfish-governor-smu` for GPU frequency scaling.
- The MangoHud/radeontop `655%` GPU usage fix.
- Signed OSTree images for `ostree-image-signed` rebases.
- Deck, GNOME, and KDE variants.

> [!TIP]
> If you only want a working BC-250 gaming setup, use the normal image for your desktop. You do not need the experimental `-40cu` image.

## Which image should I use?

| You want | Use this |
| --- | --- |
| Steam Deck style / Game Mode | `bazzite-bc250-patched-deck` |
| GNOME desktop | `bazzite-bc250-patched-gnome` |
| KDE desktop | `bazzite-bc250-patched-kde` |
| Experimental CU unlock testing | One of the `-40cu` images |

Published images:

| Variant | Image |
| --- | --- |
| Deck | `ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest` |
| GNOME | `ghcr.io/62fixolab/bazzite-bc250-patched-gnome:latest` |
| KDE | `ghcr.io/62fixolab/bazzite-bc250-patched-kde:latest` |

> [!IMPORTANT]
> The normal images are the recommended choice. The `-40cu` images are for testing only and do not guarantee that your board will be stable with extra CUs enabled.

## Install

> [!IMPORTANT]
> This assumes your BC-250 already works on stock Bazzite. Recommended baseline: modified BIOS, 512 MB dynamic VRAM, IOMMU disabled, enough cooling, and a PSU with enough 12 V headroom.

If you used the old vietsman patched kernel COPR before, disable it first:

```bash
sudo mkdir -p /etc/yum.repos.d.disabled
sudo mv /etc/yum.repos.d/*vietsman*patched-kernel-bc250*.repo /etc/yum.repos.d.disabled/ 2>/dev/null || true
```

Then rebase to the image you want:

```bash
# Deck
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest

# GNOME
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome:latest

# KDE
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde:latest

systemctl reboot
```

> [!NOTE]
> The images are signed with cosign and include the signing policy needed for `ostree-image-signed`.

## After install

Check that you are on the expected image:

```bash
rpm-ostree status
```

Check the governor:

```bash
systemctl status cyan-skillfish-governor-smu --no-pager
```

Check the GPU frequency table:

```bash
for f in /sys/class/drm/card*/device/pp_dpm_sclk; do echo "$f"; cat "$f"; done
```

> [!TIP]
> The BC-250 GPU can appear as `card0` or `card1`. Checking both avoids a lot of confusion.

MangoHud/radeontop should now show normal GPU usage instead of `655%`.

## Experimental 40CU images

The `40cu` branch builds separate experimental images:

| Variant | Image |
| --- | --- |
| Deck 40CU | `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest` |
| GNOME 40CU | `ghcr.io/62fixolab/bazzite-bc250-patched-gnome-40cu:latest` |
| KDE 40CU | `ghcr.io/62fixolab/bazzite-bc250-patched-kde-40cu:latest` |

These images include runtime tooling from the original [`duggasco/bc250-40cu-unlock`](https://github.com/duggasco/bc250-40cu-unlock) research and [`WinnieLV/bc250-cu-live-manager`](https://github.com/WinnieLV/bc250-cu-live-manager).

> [!CAUTION]
> 32CU/40CU is silicon lottery. The tooling can work perfectly and your specific board can still be unstable with extra CUs enabled. If games fail at 32CU/40CU but work again at 24CU, use 24CU.

Quick test flow:

```bash
ujust bc250-cu-status
ujust bc250-cu-dry-run-40
ujust bc250-cu-sweet-spot
ujust bc250-cu-enable-40
ujust bc250-cu-status
```

Rollback to factory 24CU:

```bash
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
```

> [!WARNING]
> Do not run `ujust bc250-cu-save-boot` until you have tested games or benchmarks and confirmed that your board is stable.

Full 40CU instructions live here: [docs/40cu.md](docs/40cu.md).

## Common fixes

### Old COPR causes 404 during rebase

Disable the old patched-kernel repo:

```bash
sudo mkdir -p /etc/yum.repos.d.disabled
sudo mv /etc/yum.repos.d/*vietsman*patched-kernel-bc250*.repo /etc/yum.repos.d.disabled/ 2>/dev/null || true
```

### Deck UI micro-stutter

If the Handheld Daemon restarts repeatedly on Deck UI:

```bash
sudo systemctl disable --now hhd
sudo systemctl mask hhd
```

### Sunshine crashes

First reinstall the Bazzite integration:

```bash
ujust setup-sunshine
```

If Sunshine crashes with `status=139`/SIGSEGV, test software encoding:

```bash
systemctl --user stop homebrew.sunshine.service
mkdir -p ~/.config/sunshine
sed -i '/^encoder *=/d;/^capture *=/d' ~/.config/sunshine/sunshine.conf 2>/dev/null || true
printf '\nencoder = software\ncapture = kms\n' >> ~/.config/sunshine/sunshine.conf
systemctl --user restart homebrew.sunshine.service
journalctl --user -u homebrew.sunshine.service -b -f
```

Then open `https://localhost:47990` or `https://<host-ip>:47990`.

### Temperature sensors

For read-only monitoring:

```bash
echo 'nct6683' | sudo tee /etc/modules-load.d/nct6683.conf
echo 'options nct6683 force=true' | sudo tee /etc/modprobe.d/sensors.conf
systemctl reboot
```

## Updates and rollback

Images are checked daily against official Bazzite `stable` base digests. If Bazzite stable changes, GitHub Actions rebuilds the patched images.

Update normally:

```bash
ujust update
```

Rollback if something breaks:

```bash
rpm-ostree rollback
systemctl reboot
```

## What changed from vietsman

This repository continues the idea from:

- [`vietsman/bazzite-deck-patched`](https://github.com/vietsman/bazzite-deck-patched)
- [`vietsman/bazzite-gnome-patched`](https://github.com/vietsman/bazzite-gnome-patched)
- [`vietsman/bazzite-kde-patched`](https://github.com/vietsman/bazzite-kde-patched)

| Area | Original vietsman images | This repo |
| --- | --- | --- |
| Bazzite base | Older Fedora/Bazzite 42 base | Current Bazzite `stable` |
| Repositories | Three separate repos | One repo for Deck, GNOME, and KDE |
| Governor | `oberon-governor` | `cyan-skillfish-governor-smu` |
| Old patched kernel COPR | Required | Removed |
| GPU usage `655%` bug | Not fixed | Fixed |
| Rebuilds | Weekly | Only when Bazzite stable changes |
| Signing | vietsman signed images | This repo's signed images |
| Experimental 40CU | Not included | Separate `-40cu` images |

## References

- [Bazzite updates, rollbacks, and rebasing](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/)
- [Bazzite ujust commands](https://docs.bazzite.gg/Installing_and_Managing_Software/ujust/)
- [Bazzite Sunshine documentation](https://docs.bazzite.gg/Advanced/sunshine/)
- [`filippor/cyan-skillfish-governor`](https://github.com/filippor/cyan-skillfish-governor)
- [`duggasco/bc250-40cu-unlock`](https://github.com/duggasco/bc250-40cu-unlock)
- [`WinnieLV/bc250-cu-live-manager`](https://github.com/WinnieLV/bc250-cu-live-manager)
- [`elektricM/amd-bc250-docs`](https://github.com/elektricM/amd-bc250-docs)
