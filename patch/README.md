# Carried patches

Inventory of the patches that `make patch.apply` applies to the upstream source of
`SRC_NAME` at the pin of `configure/RELEASE`. Every patch is a `p0` unified diff
made from the source root with `git diff --no-prefix`, and the byte (C locale)
sorted order of the file names is the apply order. Apply and check use
`tools/apply_patch.bash`, revert uses `tools/revert_patch.bash` (copies of the
tools of the patch skill; the `.source` file beside each copy records its origin).

## Patches

| File | Pin | Fixes | Origin |
| --- | --- | --- | --- |
| `1.2.2-net-timeout.p0.patch` | ULDAQ 1.2.2, tag `v1.2.2`, commit `f87594f7db478adb736a7868859133c45b6ec6b7` | `NetDaqDevice::receiveFrame` in `src/net/NetDaqDevice.cpp` reports EOF and an incomplete response header as an error (`ERR_DEV_NOT_CONNECTED` on EOF, `ERR_DEAD_DEV` otherwise). Configuration items `DEV_CFG_NET_CONNECT_TIMEOUT` and `DEV_CFG_NET_COMMAND_TIMEOUT` of network devices, in milliseconds, default 3000, set with `ulDevSetConfig()` and read with `ulDevGetConfig()`. A failed command of the TC-32 and the E-TC (`ETc32`, `ETc`) ends after the command timeout with `ERR_DEV_NOT_CONNECTED` and skips the connection state query (`queriesStateAfterFailedCommand()`) | uldaq-env issues 2, 3 and 5; no upstream pull request or commit is recorded |

## Rules of this repository

- The patch is required: `build` and `install` run `make patch.check` and stop when
  the source does not carry it. `conf`, `debugconf`, `conf.rocky8`, and `conf.rocky10`
  run `make patch.apply` first.
- The file name starts with `SRC_VERSION`; a new `SRC_VERSION` needs its own
  compatible patch file, and a patch of the old version is then selected by nothing.
- Retirement: when the pin moves, examine every row again; remove a patch whose fix
  the new version holds, together with its row, in the same change as the bump.
- Verification: `tests/test_build.bash` runs the patch cycle (unpatched build and
  install rejected, apply, apply again, revert byte for byte, reapply) and the
  invalid-patch cases; see `tests/README.md`.
