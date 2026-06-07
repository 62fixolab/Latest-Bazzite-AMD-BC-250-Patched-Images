# 🎉 Sponsors

## Printer Tools App
[![Banner - Printer Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-printer-tools.png)](https://printertools.app)

## Scooter Tools App
[![Banner - Scooter Tools App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-scooter-tools.png)](https://scootertools.app)

## AdMate App
[![Banner - AdMate App](https://github.com/62fixolab/62fixolab/raw/master/assets/banner-admate.png)](https://admate.dev)

## Table of Contents

- [Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE](#bazzite-amd-bc-250-patched-images-for-deck-gnome-and-kde)
  - [TL;DR](#tldr)
  - [Origin](#origin)
  - [Images](#images)
  - [Experimental 40CU images](#experimental-40cu-images)
    - [Install a 40CU image](#install-a-40cu-image)
    - [Testing order](#testing-order)
    - [Interpreting status](#interpreting-status)
    - [Conservative modes](#conservative-modes)
    - [40CU commands](#40cu-commands)
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
  - [Updating 40CU vendor sources](#updating-40cu-vendor-sources)
  - [References](#references)

# Bazzite AMD BC-250 Patched Images for Deck, GNOME, and KDE

[![Build Bazzite BC-250](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml/badge.svg)](https://github.com/62fixolab/Latest-Bazzite-AMD-BC-250-Patched-Images/actions/workflows/build.yml)

Bazzite images for AMD BC-250 boards. This repository builds Deck, GNOME, and KDE variants from the current official Bazzite stable base and adds `cyan-skillfish-governor-smu` for BC-250 GPU frequency scaling and the `655%` GPU usage telemetry fix.

> [!NOTE]
> The `40cu` branch also builds separate experimental `-40cu` images. They include runtime 40CU unlock tooling, but they do not enable 40CU automatically at boot.

## TL;DR

> [!TIP]
> Use the normal images if you only want current Bazzite stable for BC-250 with the modern SMU governor and the `655%` GPU usage fix.

> [!IMPORTANT]
> Use the `-40cu` images only if you want to test the experimental runtime CU unlock. The `-40cu` images only include the tooling; they boot like normal Bazzite until you explicitly enable extra CUs.

> [!CAUTION]
> 40CU is not guaranteed on every BC-250. The tooling can apply the register changes and persist them across reboot, but the extra CUs may still be unstable on some boards. If games crash, show artifacts, or fail to launch at 32CU/40CU but work again at 24CU, that usually points to silicon quality on that specific board, not a broken image.

> [!NOTE]
> The 40CU behavior is based on the original BC-250 40 CU re-enablement report and whitepaper from [`duggasco/bc250-40cu-unlock`](https://github.com/duggasco/bc250-40cu-unlock). This image packages the tooling and safe commands around that work; it does not claim the register research as original to this repository.

| Goal | Image to use | What happens |
| --- | --- | --- |
| Stable BC-250 Bazzite | `bazzite-bc250-patched-deck`, `gnome`, or `kde` | Current Bazzite stable + `cyan-skillfish-governor-smu` |
| Test 40CU manually | `bazzite-bc250-patched-deck-40cu`, `gnome-40cu`, or `kde-40cu` | Same base, plus optional 40CU runtime tools |
| Try a safer unlock | Any `-40cu` image + custom WGP layout | Lets you test fewer extra WGPs, such as 32CU |
| Keep 40CU after reboot | Any `-40cu` image + `ujust bc250-cu-save-boot` | Reapplies the saved WGP table on boot |
| Back out safely | `ujust bc250-cu-restore-24`, `ujust bc250-cu-disable-boot`, or `rpm-ostree rollback` | Returns to factory 24CU dispatch or previous deployment |

Deck example:

```bash
# Install the experimental 40CU Deck image
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest
systemctl reboot
```

> [!NOTE]
> If `latest` is not available yet on an experimental branch build, use the branch tag shown in GitHub Packages, for example `:br-40cu-43`.

After reboot:

```bash
# Check current state
ujust bc250-cu-status

# Preview 40CU writes without applying them
ujust bc250-cu-dry-run-40

# Enable 40CU until the next reboot
ujust bc250-cu-enable-40

# Optional conservative governor profile for 40CU testing
ujust bc250-cu-sweet-spot
```

> [!WARNING]
> Only persist 40CU after you have tested that your board is stable.

```bash
ujust bc250-cu-save-boot
```

> [!TIP]
> Keep these rollback commands nearby while testing experimental CU layouts.

```bash
# Return to factory 24CU dispatch live
ujust bc250-cu-restore-24

# Remove saved 40CU boot restore
ujust bc250-cu-disable-boot

# Return to the normal Deck image
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
systemctl reboot
```

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

> [!IMPORTANT]
> All images are signed with cosign and include the signing policy needed for `ostree-image-signed`.

You can verify a published image with the public key in this repository:

```bash
cosign verify --key cosign.pub ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

## Experimental 40CU images

The `-40cu` images are separate from the stable images above:

| Variant | Base image | Published image |
| --- | --- | --- |
| Deck 40CU | `ghcr.io/ublue-os/bazzite-deck:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest` |
| GNOME 40CU | `ghcr.io/ublue-os/bazzite-gnome:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-gnome-40cu:latest` |
| KDE 40CU | `ghcr.io/ublue-os/bazzite:stable` | `ghcr.io/62fixolab/bazzite-bc250-patched-kde-40cu:latest` |

> [!NOTE]
> The workflow also keeps branch/version tags such as `br-40cu-43` or `br-40cu-44` for traceability, but `latest` is the intended install tag.

These images include:

- `bc250-cu-live-manager` for runtime WGP/CU dispatch control through UMR.
- The original 40CU technical report, whitepaper, patch, and scripts from [`duggasco/bc250-40cu-unlock`](https://github.com/duggasco/bc250-40cu-unlock).
- Short `ujust` commands for testing, applying, persisting, and reverting the 40CU setup.
- A conservative governor helper for the documented 1500 MHz / 900 mV 40CU sweet spot.

> [!IMPORTANT]
> These images intentionally do not include an always-on patched `amdgpu` module. The runtime route is easier to update with upstream changes and avoids tying the image to a specific Bazzite kernel build.

What this image can validate:

- The current Bazzite base boots on the BC-250.
- `cyan-skillfish-governor-smu` runs and fixes the `655%` GPU usage telemetry issue.
- `umr` and the BC-250 live manager are available out of the box.
- Runtime WGP dispatch can be changed to 32CU/40CU.
- A chosen WGP table can be saved and replayed automatically at boot.
- Factory 24CU dispatch can be restored if the board is unstable.

What it cannot guarantee:

- That every disabled WGP/CU on every BC-250 is healthy.
- That 40CU will be stable in games on every board.
- That 32CU will be stable if the specific extra WGPs on your board are marginal.
- That lower clocks or voltage tuning can fix genuinely defective CUs.

> [!CAUTION]
> In practice, treat this as a silicon-lottery feature. A board that works perfectly at stock 24CU but crashes at 32CU/40CU is still behaving normally for this experiment.

### Install a 40CU image

```bash
# Deck 40CU
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest

# GNOME 40CU
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome-40cu:latest

# KDE 40CU
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde-40cu:latest

systemctl reboot
```

### Testing order

> [!IMPORTANT]
> Start with temporary live changes. Only save a boot table after the board survives real game or benchmark testing.

```bash
# 1. Confirm the image and tools
rpm-ostree status
command -v bc250-cu-live-manager
command -v umr
systemctl status cyan-skillfish-governor-smu --no-pager

# 2. Check the current factory/runtime state
ujust bc250-cu-status
ujust bc250-cu-dry-run-40

# 3. Apply the conservative governor profile
ujust bc250-cu-sweet-spot

# 4. Test full 40CU only until reboot
ujust bc250-cu-enable-40
ujust bc250-cu-status
```

> [!TIP]
> If the system is unstable, return to factory dispatch before testing a different CU layout.

```bash
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
```

> [!WARNING]
> Only after extended testing should you make the current table survive reboot.

```bash
ujust bc250-cu-save-boot
systemctl reboot
ujust bc250-cu-status
systemctl status bc250-cu-live-manager.service --no-pager
```

### Interpreting status

> [!NOTE]
> `ujust bc250-cu-status` can show two different truths:

```text
SPI total   : 40/40 CUs
Driver lock : 24/40 CUs active
```

`Driver lock` is what the `amdgpu` driver saw when it initialized. With the runtime path, the driver can still report the factory 24CU topology.

`SPI total` is the live dispatch table that this tool writes through UMR. This is the useful value when testing runtime 32CU/40CU dispatch.

> [!IMPORTANT]
> For a saved boot profile, also check that the service is enabled and the boot table is in sync:

```text
Service   : enabled
Boot sync : current table saved
Boot table: SE0.SH0=0x1f SE0.SH1=0x1f SE1.SH0=0x1f SE1.SH1=0x1f
```

That means the service is installed and the current WGP table is the one that will be replayed at boot.

### Conservative modes

> [!TIP]
> The first conservative step is lowering the governor target before testing extra CUs.

```bash
ujust bc250-cu-sweet-spot
```

> [!CAUTION]
> This writes a 1500 MHz / 900 mV profile based on the upstream 40CU report. It reduces power and heat, but it cannot fix defective CUs.

> [!TIP]
> If full 40CU is unstable, try a 32CU layout by enabling only one extra WGP per shader row.

```bash
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
sudo bc250-cu-live-manager enable-wgp 0.0.3 0.1.3 1.0.3 1.1.3
ujust bc250-cu-status
```

Expected result:

```text
SPI total : 32/40 CUs
```

> [!CAUTION]
> If 32CU is also unstable, stay on factory 24CU.

```bash
ujust bc250-cu-disable-boot
ujust bc250-cu-restore-24
```

> [!NOTE]
> That does not mean the image failed. It means your board likely cannot run those extra WGPs reliably.

### 40CU commands

```bash
# Show current BC-250 CU/WGP state
ujust bc250-cu-status

# Open the interactive manager
ujust bc250-cu-menu

# Preview the 40CU register writes without applying them
ujust bc250-cu-dry-run-40

# Apply full 40CU dispatch until reboot
ujust bc250-cu-enable-40

# Save the current table and enable boot restore
ujust bc250-cu-save-boot

# Restore factory 24CU dispatch live
ujust bc250-cu-restore-24

# Remove the boot restore service and saved table
ujust bc250-cu-disable-boot

# Apply the conservative 1500 MHz / 900 mV governor profile
ujust bc250-cu-sweet-spot

# Restore the previous governor config backed up by the helper
ujust bc250-cu-governor-restore
```

> [!WARNING]
> The upstream health checker is included as documentation/tooling, but it is not wired into `ujust` and is not run automatically. It can reboot repeatedly and has already caused black-screen recovery situations for some users.

> [!CAUTION]
> If a saved 40CU boot table causes trouble, boot a previous deployment or recovery shell and run:

```bash
sudo systemctl disable --now bc250-cu-live-manager.service
sudo rm -f /etc/bc250-cu-live-manager.conf
```

## What changed from the original images

| Area | vietsman images | This repository |
| --- | --- | --- |
| Project shape | Three separate repositories | One maintained repository building Deck, GNOME, and KDE |
| Bazzite base | Older pinned Bazzite/Fedora 42 base | Current official Bazzite `stable` base |
| Update model | Weekly rebuilds from the old pinned base | Daily digest check; rebuilds only when Bazzite `stable` changes |
| Kernel approach | Old `vietsman/patched-kernel-bc250` COPR | Current Bazzite kernel; no old BC-250 kernel COPR required |
| Governor | `oberon-governor` | Newer `cyan-skillfish-governor-smu` |
| GPU frequency scaling | Provided by Oberon + patched kernel stack | Provided by the SMU governor on current Bazzite |
| `655%` GPU usage bug | Not handled by Oberon | Fixed by the SMU governor's `gpu_metrics` bind-mount patch |
| Image signing | Signed `ghcr.io/vietsman/...` images | Signed `ghcr.io/62fixolab/...` images with this repo's `cosign.pub` |
| Install ref | `ostree-image-signed:docker://ghcr.io/vietsman/...` | `ostree-image-signed:docker://ghcr.io/62fixolab/...` |
| 40CU unlock | Not included in the old image set | Separate `-40cu` images with optional runtime tooling |
| Main benefit | Original BC-250 patched image set | Same idea, but current Bazzite, newer governor, automatic stable tracking, and signed images |

## Before you install

> [!IMPORTANT]
> These images assume a BC-250 setup that is already healthy on stock Bazzite:

- Modified BIOS flashed, with P3.00 recommended by the community documentation.
- VRAM allocation set to 512 MB dynamic.
- IOMMU disabled in BIOS.
- Adequate cooling and airflow, especially over the rear VRAM chips.
- A PSU with enough 12 V headroom for gaming loads.
- Ethernet available during setup if you rely on USB Wi-Fi adapters.

> [!NOTE]
> Unlike older Fedora installs, Bazzite should boot on the BC-250 without `nomodeset`.

## Installation

> [!WARNING]
> If you previously enabled the old `vietsman/patched-kernel-bc250` COPR, disable it before rebasing. The repo only publishes old Fedora metadata and can make `rpm-ostree rebase` fail with a `404`.

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

> [!TIP]
> The BC-250 GPU may appear as `card1` instead of `card0`, depending on the boot and display setup. Check both paths when verifying the frequency table:

```bash
cat /sys/class/drm/card0/device/pp_dpm_sclk
cat /sys/class/drm/card1/device/pp_dpm_sclk
```

> [!NOTE]
> MangoHud/radeontop should show normal GPU usage values instead of `655%`.

## Known BC-250 notes

### Sunshine

> [!TIP]
> If Sunshine stops working after rebasing, reinstall its Bazzite integration:

```bash
ujust setup-sunshine
```

> [!WARNING]
> On newer Bazzite/Sunshine builds, the BC-250 can crash Sunshine with `status=139`/SIGSEGV when hardware encoding falls back through unsupported encoder paths such as Vulkan. If Sunshine crashes on startup, force software encoding first to confirm the service is otherwise healthy:

```bash
systemctl --user stop homebrew.sunshine.service
mkdir -p ~/.config/sunshine
sed -i '/^encoder *=/d;/^capture *=/d' ~/.config/sunshine/sunshine.conf 2>/dev/null || true
printf '\nencoder = software\ncapture = kms\n' >> ~/.config/sunshine/sunshine.conf
systemctl --user restart homebrew.sunshine.service
journalctl --user -u homebrew.sunshine.service -b -f
```

> [!IMPORTANT]
> Then open the Sunshine UI at `https://localhost:47990` or `https://<host-ip>:47990`. This is safer than Vulkan on current BC-250 setups, but it uses CPU encoding; start with conservative Moonlight settings such as 1080p, 30 FPS, and 10-20 Mbps. VAAPI is the preferred long-term hardware encoder to retest after Sunshine, Mesa, or Bazzite updates.

### Deck UI micro-stutter

> [!TIP]
> On some BC-250 Deck UI setups, Bazzite's Handheld Daemon can restart repeatedly because expected handheld hardware is not present. If you see consistent micro-stutters, disable and mask it:

```bash
sudo systemctl disable --now hhd
sudo systemctl mask hhd
```

### Temperature sensors

> [!NOTE]
> For read-only hardware monitoring:

```bash
echo 'nct6683' | sudo tee /etc/modules-load.d/nct6683.conf
echo 'options nct6683 force=true' | sudo tee /etc/modprobe.d/sensors.conf
systemctl reboot
```

> [!TIP]
> For PWM fan control, use the `nct6687` module and follow the BC-250 sensor documentation.

### GPU card naming

> [!TIP]
> The BC-250 GPU can appear as `card0` or `card1`. If a command fails with `No such file or directory`, try the other card path before assuming the governor is broken.

### Power and thermals

> [!CAUTION]
> Higher GPU clocks increase power draw and heat. If your board is unstable, lower the maximum frequency or raise conservative voltage points in:

```text
/etc/cyan-skillfish-governor-smu/config.toml
```

Then restart the service:

```bash
sudo systemctl restart cyan-skillfish-governor-smu
```

## Updates

> [!NOTE]
> Images are checked daily against the current official Bazzite `stable` base digests. If Deck, GNOME, or KDE stable changes, GitHub Actions rebuilds and publishes the three patched images automatically.

> [!IMPORTANT]
> On the `40cu` branch, the workflow builds the separate `-40cu` packages instead of the normal packages. This keeps experimental 40CU publishing isolated from the main images.

For normal system updates after rebasing to one of these images:

```bash
ujust update
```

> [!TIP]
> If an update breaks something:

```bash
rpm-ostree rollback
systemctl reboot
```

## Updating 40CU vendor sources

The 40CU branch keeps upstream tooling in `vendor/` and copies the runtime files into `files/system/usr/share/bc250-40cu/vendor/` for the image build.

To refresh both copies from upstream:

```bash
scripts/update-40cu-vendors.sh
```

> [!IMPORTANT]
> Review the diff before building. Local wrappers live outside `vendor/`, so upstream updates can be applied without rewriting the image integration.

## References

- [Bazzite updates, rollbacks, and rebasing](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/)
- [Bazzite ujust commands](https://docs.bazzite.gg/Installing_and_Managing_Software/ujust/)
- [Bazzite Sunshine documentation](https://docs.bazzite.gg/Advanced/sunshine/)
- [`filippor/cyan-skillfish-governor`](https://github.com/filippor/cyan-skillfish-governor)
- [`duggasco/bc250-40cu-unlock`](https://github.com/duggasco/bc250-40cu-unlock)
- [`duggasco/bc250-40cu-unlock` technical report](https://github.com/duggasco/bc250-40cu-unlock/blob/main/docs/technical-report.md)
- [`duggasco/bc250-40cu-unlock` whitepaper](https://github.com/duggasco/bc250-40cu-unlock/blob/main/docs/whitepaper-cu-unlock.pdf)
- [`WinnieLV/bc250-cu-live-manager`](https://github.com/WinnieLV/bc250-cu-live-manager)
- [`elektricM/amd-bc250-docs`](https://github.com/elektricM/amd-bc250-docs)
