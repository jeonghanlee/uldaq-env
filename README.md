# ULDAQ Configuration Environment

[![Build Test](https://github.com/jeonghanlee/uldaq-env/actions/workflows/build.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/build.yml)
[![Linter Run](https://github.com/jeonghanlee/uldaq-env/actions/workflows/linter.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/linter.yml)

MCC Universal Library for Linux (uldaq) Configuration Environment, and its customized application.

* https://github.com/mccdaq/uldaq
* required packages

```bash
apt install autoconf libtool libusb-1.0-0-dev
```

## About
This repository helps to build the uldaq package and its customized application consistently on Linux and macOS.

## uldaq commands

By default, everything will be within `$(TOP)` path. In case, one would like to install them in a host system, for example, `/usr/local`. One can define it via

```bash
echo "INSTALL_LOCATION=/usr/local" > configure/CONFIG_SITE.local
```

* Build

```bash
make init
make conf
make build
make install
```

Note that `make install` will call `make install-exec` in the original `uldaq` makefile rule and call `make install-includeHEADER' in `SRC_PATH/src`. If one would like to install `udev.rule`, please consult `Makefile` in `SRC_PATH`.

* Others

```bash
make uninstall
make clean
make distclean
```

## Requirements

Please see uldaq for required packages. For macOS, I use `port` instead of `brew`.
