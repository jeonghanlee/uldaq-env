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

* Others

```bash
make uninstall
make clean
make distclean
```
## Requirements

Plesase see uldaq for required packages. For macOS, I use `port` instead of `brew`.

