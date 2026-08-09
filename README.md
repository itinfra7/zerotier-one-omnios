# zerotier-one-omnios

ZeroTier One 1.16.2 for OmniOS r151054 LTS.

This port integrates ZeroTier One with the illumos networking stack using `etherstub`, VNIC, libdlpi, and SMF. It supports new installations and in-place upgrades from the previous 1.16.1 OmniOS release.

## Compatibility

- ZeroTier One: `1.16.2`
- Upstream tag: `1.16.2`
- Upstream commit: `fc5c3ec22090b5b2a0f274e863651fe9ca489bf4`
- Operating system: OmniOS r151054 LTS
- Compiler: GCC 14
- Service manager: SMF

The installer verifies the exact upstream commit before applying the OmniOS patch and building the binary.

## Technical Design

OmniOS does not use the Linux TUN/TAP implementation expected by the standard ZeroTier build. This port provides a native virtual Ethernet path composed of:

- One temporary `etherstub` for each joined ZeroTier network
- A visible VNIC used by the OmniOS IP stack
- A backend VNIC used by ZeroTier One to inject Ethernet frames
- Separate libdlpi handles for receiving and transmitting raw frames
- Managed IPv4 and IPv6 addresses configured on the visible VNIC
- Native SMF lifecycle management

Generated link names use stable prefixes derived from the ZeroTier network ID:

- `zt...`: visible VNIC
- `zb...`: backend VNIC
- `zs...`: etherstub

The OmniOS data path uses an MTU of 1280 to avoid fragmentation and transport stalls across routed or encapsulated links.

## Reliability Fixes

The OmniOS DLPI receive path includes additional lifecycle and recovery handling:

- Checks the result of `select()` instead of continuing after descriptor errors
- Handles interrupted system calls without terminating the receive path
- Reopens the DLPI receive handle after descriptor or receive failures
- Prevents a permanent receive-thread exit after non-timeout libdlpi errors
- Uses one receive thread per DLPI stream while retaining concurrent ZeroTier core packet processing
- Joins receive threads before closing DLPI handles and shutdown pipes
- Closes partially initialized handles when setup fails
- Restarts ZeroTier when the OmniOS physical network service restarts
- Restricts process lifecycle signals to the exact managed daemon command line
- Treats an empty pre-install backup as valid during a clean first installation

These changes prevent a failed DLPI descriptor from leaving SMF in an apparently healthy state while the virtual Ethernet path is stalled or consuming a CPU core.

## Requirements

- OmniOS r151054 LTS
- Root access
- Internet access to GitHub and configured OmniOS package publishers
- Authorization from the controller for newly joined private ZeroTier networks

The installer obtains the required Git, GNU Make, and GCC 14 packages through OmniOS IPS.

## Install

```sh
wget https://github.com/itinfra7/zerotier-one-omnios/releases/latest/download/install_zerotier_one_omnios.sh
chmod +x install_zerotier_one_omnios.sh
./install_zerotier_one_omnios.sh
```

For unattended installation without enabling IP forwarding:

```sh
./install_zerotier_one_omnios.sh --yes --no-forwarding
```

To enable IPv4 and IPv6 forwarding during unattended installation:

```sh
./install_zerotier_one_omnios.sh --yes --enable-forwarding
```

## Upgrade

Run the same installer to upgrade an existing 1.16.1 OmniOS installation.

The upgrade preserves:

- `identity.public` and the root-only `identity.secret`
- Joined networks and network-specific local configuration
- Moons and planet configuration
- Local ZeroTier configuration
- Existing controller authorization and node identity

The source is built before the running service is stopped. The service interruption is limited to replacing the validated build and restarting SMF.

Before replacement, the installer stores the existing binary, SMF method, and SMF manifest under:

```text
/var/lib/zerotier-one/install-backups/YYYYMMDD-HHMMSS/
```

Backup directories are root-only and do not contain the ZeroTier secret identity.

If service validation, version validation, manifest import, or identity preservation fails after replacement, the installer automatically restores the previous installation files and restarts the previous service.

## Local Assets

For development or pre-release validation, provide a directory containing the matching patch, SMF method, and SMF manifest:

```sh
./install_zerotier_one_omnios.sh \
  --yes \
  --no-forwarding \
  --asset-dir /path/to/release-assets
```

All supplied assets must belong to the same release.

## Verify

```sh
zerotier-one -v
zerotier-cli status
zerotier-cli listnetworks
svcs -xv zerotier-one
dladm show-link
ipadm show-addr
```

The expected binary version is:

```text
1.16.2
```

A joined and authorized network should report `OK`, have a `zt...` device, and show its assigned addresses. Immediately after a restart, `zerotier-cli status` may briefly report `OFFLINE` while planet connectivity is re-established; network, link, and address state should be evaluated together.

## Service Management

```sh
svcadm restart zerotier-one
svcadm disable zerotier-one
svcadm enable zerotier-one
```

The service FMRI is:

```text
svc:/network/zerotier-one:default
```

SMF logs are available at:

```text
/var/svc/log/network-zerotier-one:default.log
```

## Troubleshooting

Inspect the complete service state and recent method output:

```sh
svcs -xv zerotier-one
tail -n 100 /var/svc/log/network-zerotier-one:default.log
```

Confirm that the process, virtual links, addresses, and network membership agree:

```sh
pgrep -lf zerotier-one
dladm show-etherstub
dladm show-vnic
ipadm show-addr
zerotier-cli status
zerotier-cli listnetworks
zerotier-cli peers
```

If a private network reports `ACCESS_DENIED`, authorize the node in its ZeroTier controller. If a network reports `PORT_ERROR` or its `zt...` link is absent, restart the SMF service and inspect the SMF log for DLPI or VNIC errors.

The installer is safe to run again after a failed pre-install build or dependency check. It treats the normal OmniOS IPS "no changes required" result as success.

## Credits

- [ZeroTier, Inc.](https://www.zerotier.com/) and the [ZeroTierOne](https://github.com/zerotier/ZeroTierOne) project
- [OmniOS Community Edition](https://omnios.org/)
- [itinfra7](https://github.com/itinfra7)
