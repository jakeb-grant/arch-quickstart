# User installs

Tools installed for one user by a script, outside pacman and the AUR — a
shell's own installer, a release binary, a toolchain manager. Each is a
directory here, run in name order by `user-installs-setup` as the new user,
after the AUR packages and before the dotfiles are applied.

```
<name>/
  install   run as the user, in ~; installs or updates the tool
  fetch     optional; run in CI for the offline ISO, bundles what install needs
```

## `install`

Runs as the target user (never root) in the installed system, with `HOME`
set and the working directory `~`. It must be safe to run again: running it
again is how a user updates or retries (`user-installs-setup <name>`).

`PAYLOAD` is the path to this tool's bundled payload when the ISO carries
one (the offline ISO), and empty otherwise: install from `PAYLOAD` when it
is set, else from the network. Exit non-zero on failure; the installer
warns and carries on, since the system is already bootable.

## `fetch`

Runs at offline ISO build time as `fetch DIR`, in the Arch build container
(curl and jq available, `GITHUB_TOKEN` set). It downloads everything
`install` needs into `DIR`, which lands on the ISO at
`/opt/user-installs/<name>/` and reaches `install` as `PAYLOAD`. A failing
`fetch` fails the build. Leave `fetch` out for a tool with no offline
path; on the offline ISO its `install` then needs the network.

Both scripts are run with `bash`, so they need no execute bit.
