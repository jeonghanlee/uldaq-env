# ULDAQ Configuration Environment

[![Debian 12](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml)
[![Debian 13](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian13.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian13.yml)
[![Ubuntu 24.04](https://github.com/jeonghanlee/uldaq-env/actions/workflows/ubuntu24.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/ubuntu24.yml)
[![Ubuntu 26.04](https://github.com/jeonghanlee/uldaq-env/actions/workflows/ubuntu26.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/ubuntu26.yml)
[![Rocky8](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky8.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky8.yml)
[![Rocky9](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml)
[![Rocky10](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky10.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky10.yml)

MCC Universal Library for Linux (`uldaq`) Configuration Environment and its customized application.

* The source codes are located in <https://github.com/mccdaq/uldaq/>
* Required packages (Debian and its variants) as follows

```bash
apt install autoconf libtool libusb-1.0-0-dev patch
```

## About
This repository helps to build the `uldaq` package and its customized application consistently on Linux and macOS.

The default source is ULDAQ 1.2.2, upstream commit
`f87594f7db478adb736a7868859133c45b6ec6b7`. The required TCP receive patch
reports EOF and incomplete response headers as errors. Its filename uses
`SRC_VERSION`, independently of the slash in `SRC_TAG=tags/v1.2.2`, and its
paths are relative to the source root (`-p0`).

`conf`, `debugconf`, `conf.rocky8`, and `conf.rocky10` apply the patch before
configuration. `build` and `install` check that it is present in the source
and stop if it is missing, reverted, or incompatible. The explicit lifecycle
commands are:

```bash
make patch.apply
make patch.check
make patch.revert
```

`tools/apply_patch.bash` applies and checks the patch and `tools/revert_patch.bash`
reverts it; both are copies of the tools of the patch skill, and the origin, skill
commit, and digest of each are in the `.source` file beside it. Both classify the
patch first with `patch --dry-run` in both directions, so both can run again: a
second `make patch.apply` reports that the patch is already applied and changes
nothing, and a second `make patch.revert` reports that it is not applied and
changes nothing. A state that is neither stops with an error. The tools exit with
0 when done, already so, or skipped; 1 when `patch.check` finds the patch not
applied or `patch` fails while changing the source; 2 for a missing, empty, or
unreadable patch file; 3 when the state cannot be classified. A plain `patch`
call on a patched source would stop with "Reversed (or previously applied) patch
detected" and leave a `.rej` file; after such a stop, revert, remove the `.rej`
file, and apply again.

Reapply and rebuild after a revert. Do not install an earlier build after
changing the source. The patch covers the selected 1.2.2 source; another
`SRC_VERSION` requires its own compatible required patch. The inventory of the
carried patch is `patch/README.md`.

## `uldaq` commands

By default, everything will be within `/usr/local` path. It can be customized via

```bash
echo "INSTALL_LOCATION=where...." > configure/CONFIG_SITE.local
```

* Build

```bash
make init
make conf
make build
make install
```

```bash
make init
make debugconf 
make build
make install
```

* Build on Rocky 8 or Red Hat Variant

Even if their compiler and linker is indeed very mordern, Red Hat made a choice to build their binutils packages to default to the order `RPATH` instead of `RUNPATH`. So we have to enable it by using the red hat specific configuration option.


```bash
make init
make conf.rocky8
make build
make install
```

* Build on Rocky 10

`conf.rocky10` calls the same configuration recipe as `conf.rocky8`. Both
targets retain the Red Hat linker settings and the configured installation
prefix. Existing calls to `conf.rocky8` remain supported.

```bash
make init
make conf.rocky10
make build
make install
```



* Others

After `make init`, `make all` runs configuration, build, and installation in
order, including with parallel Make. `make github` also initializes the
source, so it requires a fresh source directory. It keeps acquisition,
patching, and compilation under the caller's account and uses `SUDO` for
installation only when needed. On Linux, a writable installation prefix,
including a new nested prefix under a writable ancestor, does not use sudo.
Protected prefixes require an available sudo command and permission to use it.

```bash
make uninstall
make clean
make distclean
```

## Vendor record

On Linux, `make install` writes `<prefix>/cfg/uldaq/build-record` and its digest
file `<prefix>/cfg/uldaq/build-record.sha256` for the shared objects it
installed, in the `key=value` form that EPICS-env uses for its modules. Other
wrappers may install into the same prefix, so the list of files comes from a
staged installation of the configured source, never from a directory scan.
macOS installations write no record.

* `build-record`: the lines `format=1`, `name=uldaq`, `version` (the upstream
  version, `SRC_VERSION`), `tag` and `source` (the tag and the commit of this
  repository), `upstream` (`SRC_TAG` without the leading `tags/`), `patch` (one
  line naming the required patch file when the source clone carries it; no line
  when the patch is not applied, and `patch=unknown` when its state cannot be
  determined), and `arch` (`linux-` and the machine name), in this order. Then, for each
  installed shared object, `artifact=<path> <sha256>` directly followed by
  `buildid=<path> <hex>`, sorted by path, with the path relative to the prefix.
  The build-id is read by `readelf -n` from the installed file, or `none` when
  the file has none. Symbolic links and static archives are not listed.
* `tag` is the highest tag by version order on `HEAD`, `untagged`, or
  `unknown`; `source` is the full commit hash, followed by `+dirty` when a
  tracked file differs from `HEAD`, or `unknown` when it cannot be read from the
  repository root.
* `build-record.sha256`: one line, the sha256 of `build-record`.

A build-id identifies one binary built on one operating system; the source
identity is carried by `tag`, `source`, `upstream`, and `patch`. Both files are
written through a temporary file in the same directory and renamed, with the
mode the umask gives and no explicit `chmod`; `cfg` and `cfg/uldaq` are created
only when absent, and the digest file is written after the record. The files
are not tracked by Git and are rewritten completely on every install. `make
uninstall` runs the source uninstall, removes these two files, the directory
`cfg/uldaq`, and `cfg` when it is empty, and removes the directories that became
empty; it never removes the prefix itself or files of other wrappers.

## Requirements

Please take a look at the `uldaq` for the required packages. For macOS, I use `port` instead of `brew`.

## Verification

The [build verification](tests/README.md) runs the actual source acquisition,
patch targets, configure scripts, compilers, and installation commands. Linux
CI covers Debian 12 and 13, Ubuntu 24.04 and 26.04, and Rocky Linux 8, 9,
and 10, including ordinary-user and protected-prefix installations. Pushes
and pull requests that change only Markdown files or files under `docs/`
do not trigger these workflows.

Source commit, patch state, and the installed library hash identify this
build. The upstream `UL_VERSION` string remains 1.2.0 in ULDAQ 1.2.2 and is
not sufficient identity evidence. TC32 recovery additionally requires the
reconnect-capable consumer driver tracked in jeonghanlee/EPICS-env#120.
