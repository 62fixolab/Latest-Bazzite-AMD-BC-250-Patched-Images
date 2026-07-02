# Bazzite Channel Packages

This repository publishes separate packages for each supported Bazzite update channel. The stable packages are recommended for daily use. Testing and unstable are available for people who deliberately want to test upstream Bazzite channels on BC-250 hardware.

> [!IMPORTANT]
> These are OCI images, not ISOs. Install them with `rpm-ostree rebase`, then reboot.

> [!WARNING]
> Bazzite does not support rebasing between different desktop environments. Stay on Deck, GNOME, or KDE when switching channels.

## Which channel should I use?

| Channel | Use it when | Risk |
| --- | --- | --- |
| `stable` | You want the recommended image for daily use | Lowest |
| `testing` | You want to preview the next Bazzite stable build | Medium |
| `unstable` | You are intentionally testing Bazzite development images | Highest |

> [!TIP]
> If you are unsure, use `stable`.

## Package naming

Normal packages:

| Variant | Stable | Testing | Unstable |
| --- | --- | --- | --- |
| Deck | `bazzite-bc250-patched-deck` | `bazzite-bc250-patched-deck-testing` | `bazzite-bc250-patched-deck-unstable` |
| GNOME | `bazzite-bc250-patched-gnome` | `bazzite-bc250-patched-gnome-testing` | `bazzite-bc250-patched-gnome-unstable` |
| KDE | `bazzite-bc250-patched-kde` | `bazzite-bc250-patched-kde-testing` | `bazzite-bc250-patched-kde-unstable` |

Experimental 40CU packages:

| Variant | Stable | Testing | Unstable |
| --- | --- | --- | --- |
| Deck 40CU | `bazzite-bc250-patched-deck-40cu` | `bazzite-bc250-patched-deck-40cu-testing` | `bazzite-bc250-patched-deck-40cu-unstable` |
| GNOME 40CU | `bazzite-bc250-patched-gnome-40cu` | `bazzite-bc250-patched-gnome-40cu-testing` | `bazzite-bc250-patched-gnome-40cu-unstable` |
| KDE 40CU | `bazzite-bc250-patched-kde-40cu` | `bazzite-bc250-patched-kde-40cu-testing` | `bazzite-bc250-patched-kde-40cu-unstable` |

## Recommended stable images

Deck / Game Mode:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
systemctl reboot
```

GNOME:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome:latest
systemctl reboot
```

KDE:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde:latest
systemctl reboot
```

## Testing images

Deck / Game Mode:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-testing:latest
systemctl reboot
```

GNOME:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome-testing:latest
systemctl reboot
```

KDE:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde-testing:latest
systemctl reboot
```

## Unstable images

Deck / Game Mode:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-unstable:latest
systemctl reboot
```

GNOME:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-gnome-unstable:latest
systemctl reboot
```

KDE:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-kde-unstable:latest
systemctl reboot
```

## Experimental 40CU images

The 40CU images include optional runtime tooling. They do not force extra CUs on boot.

> [!CAUTION]
> 32CU/40CU is silicon lottery. Read the full [40CU guide](40cu.md) before saving any boot profile.

Stable Deck 40CU:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu:latest
systemctl reboot
```

Testing Deck 40CU:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu-testing:latest
systemctl reboot
```

Unstable Deck 40CU:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck-40cu-unstable:latest
systemctl reboot
```

Replace `deck` with `gnome` or `kde` to install the matching desktop variant.

## Check your current image

```bash
rpm-ostree status
```

The current deployment should show something like:

```text
ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
```

## Move back to stable

Use the stable package for your current desktop environment:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/62fixolab/bazzite-bc250-patched-deck:latest
systemctl reboot
```

Replace `deck` with `gnome` or `kde` if needed.

