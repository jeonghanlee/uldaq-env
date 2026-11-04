# ULDAQ Configuration Environment

[![Debian 12](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml)
[![Rocky8](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky8.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky8.yml)
[![Rocky9](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml)

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
and stop if it is missing, reverted, or incompatible. Repeated application
is supported. The explicit lifecycle commands are:

```bash
make patch.apply
make patch.check
make patch.revert
```

Reapply and rebuild after a revert. Do not install an earlier build after
changing the source. The patch covers the selected 1.2.2 source; another
`SRC_VERSION` requires its own compatible required patch.

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

## Requirements

Please take a look at the `uldaq` for the required packages. For macOS, I use `port` instead of `brew`.

## Verification

The [build verification](tests/README.md) runs the actual source acquisition,
patch targets, configure scripts, compilers, and installation commands. Linux
CI covers Debian 12 and Rocky Linux 8 and 9, including ordinary-user and
protected-prefix installations.

Source commit, patch state, and the installed library hash identify this
build. The upstream `UL_VERSION` string remains 1.2.0 in ULDAQ 1.2.2 and is
not sufficient identity evidence. TC32 recovery additionally requires the
reconnect-capable consumer driver tracked in jeonghanlee/EPICS-env#120.
