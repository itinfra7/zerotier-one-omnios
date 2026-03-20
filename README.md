# zerotier-one-omnios

ZeroTier One 1.16.1 release assets, SMF service files, and installer for OmniOS r151054 LTS.

## Keywords

Keywords: `#omnios #zerotier #illumos #solaris #smf #etherstub #vnic #libdlpi #vpn #networking`

## Overview

This repository provides a reproducible build, installation, and operation path for ZeroTier One 1.16.1 on OmniOS Community Edition v11 r151054 LTS.

The installer supports both English and `한국어` prompts.

## Technical Design

This OmniOS adaptation uses `etherstub + vnic + libdlpi` instead of a generic TUN/TAP device model.

The source patch adds SunOS-aware build flags, routing adjustments, DLPI and VNIC integration, and supporting filesystem behavior required for stable OmniOS operation.

SMF is used for service lifecycle management so startup, shutdown, restart, and cleanup follow native OmniOS administration patterns.

## Target Profile

- Upstream version: ZeroTier One 1.16.1
- Upstream commit: `d9a7f62a5ca04f832d1025bcc7c48f9e8d65e3a6`
- Operating system: OmniOS Community Edition v11 r151054 LTS
- Networking model: `etherstub + vnic + libdlpi`
- Service manager: SMF

## Included Files

- `install_zerotier_one_omnios.sh` downloads the latest release assets, checks out the pinned upstream commit, applies the OmniOS source patch, builds ZeroTier One 1.16.1, installs the binaries, registers the SMF service, and optionally enables IP forwarding.
- `omnios-zerotier-one.patch` contains the OmniOS-specific source changes required to build and run ZeroTier One on OmniOS.
- `zerotier-one-smf` is the SMF method script used to start, stop, and clean up the ZeroTier One service.
- `zerotier-one.xml` is the SMF manifest that registers the `network/zerotier-one` service.

## Quick Start

Open a root shell before running the installer.

The commands below are intended to be run as `root`.

```sh
wget https://github.com/itinfra7/zerotier-one-omnios/releases/latest/download/install_zerotier_one_omnios.sh
chmod +x install_zerotier_one_omnios.sh
./install_zerotier_one_omnios.sh
```

## Workflow

1. Install the required OmniOS packages.
2. Stop any existing `zerotier-one` service instance.
3. Clone the upstream ZeroTierOne repository and check out the pinned commit.
4. Download and apply the OmniOS source patch.
5. Build the `one` target and install the binaries into `/opt/zerotier-one/bin`.
6. Install the SMF method script and manifest.
7. Import and start `network/zerotier-one`.
8. Verify `svcs -xv zerotier-one` and `zerotier-cli info`.
9. Optionally enable IPv4 and IPv6 forwarding.

## Release Assets

The latest release publishes the following assets:

- `install_zerotier_one_omnios.sh`
- `omnios-zerotier-one.patch`
- `zerotier-one-smf`
- `zerotier-one.xml`

## Credits

[ZeroTier, Inc.](https://www.zerotier.com/) and the [ZeroTierOne](https://github.com/zerotier/ZeroTierOne) project provide the upstream source code and versioning.

[OmniOS Community Edition](https://omnios.org/) provides the target operating system validated by this repository.

[itinfra7](https://github.com/itinfra7) and [ourdare.com](https://www.ourdare.com/) refer to the same author and are credited for the OmniOS adaptation workflow, patch authoring, SMF assets, installer packaging, and supporting technical write-up behind this repository.
