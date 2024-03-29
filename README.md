# ULDAQ Configuration Environment

[![Debian 12](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/debian12.yml)
[![Rocky9](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml/badge.svg)](https://github.com/jeonghanlee/uldaq-env/actions/workflows/rocky9.yml)

MCC Universal Library for Linux (`uldaq`) Configuration Environment and its customized application.

* The source codes are located in <https://github.com/mccdaq/uldaq/>
* Required packages (Debian and its variants) as follows

```bash
apt install autoconf libtool libusb-1.0-0-dev
```

## About
This repository helps to build the `uldaq` package and its customized application consistently on Linux and macOS.

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


* Others

```bash
make uninstall
make clean
make distclean
```

## Requirements

Please take a look at the `uldaq` for the required packages. For macOS, I use `port` instead of `brew`.
