# ULDAQ Configuration Environment

MCC Universal Library for Linux (uldaq) Configuration Environmemnt, and its customized applicaton.

## About
This repository help to build the uldaq package and its customized applicatino consistently on Linux and macOS.

## uldaq commands

By default, everyhing will be within `$(TOP)` path.

* Build

```bash
make init
make conf
make build
make install
```

Note that `make install` will call `make install-exec` in the original `uldaq` makefile rule. If one would like to install `udev.rule`, please consult `Makefile` in `SRC_PATH`.

* Others

```bash
make uninstall
make clean
make distclean
```

## Requirements

Plesase see uldaq for required packages. For macOS, I use `port` instead of `brew`.
