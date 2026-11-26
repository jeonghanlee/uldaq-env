# Build And Installation Verification

`test_build.bash` copies the real build files into fresh isolated directories
and invokes their actual Make targets. The first source initialization uses
the configured upstream repository. Later cases clone that real Git checkout
as a local source cache; each clone must resolve to the expected 1.2.2 commit.
No configure, compiler, patch, installation, or internal library operation is
replaced with a substitute.

## Execution

Install the repository's build dependencies, Bash, Git, `patch`, and the binutils
package that provides `readelf`. Choose a new workspace path for each run; the
suite retains it on both success and failure.

```bash
bash tests/test_build.bash --workspace /tmp/uldaq-build-check
```

Use `--config-target conf.rocky8` for the direct Rocky 8 configuration path.
The `all` and `github` cases exercise their own default configuration step.
The existing Linux workflows run the suite as root and then run `--mode user`
and `--mode protected --protected-prefix /opt/uldaq-ci` as an ordinary user.
Those permission cases require disposable containers with a container-local
passwordless sudo policy; they do not modify host policy or host prefixes.

The suite requires Bash 4.4 or newer. Exit status 0 is Passed, 1 is Failed, and
2 is Incomplete.

## Required Cases

| Case | Real Path | Required Result |
| --- | --- | --- |
| Source identity | `init` and upstream Git checkout | Expected 1.2.2 commit |
| Patch lifecycle | Apply, apply again, revert, reapply | The receive correction block, the connection deadline and both timeout configuration items present after apply; idempotence, byte-exact restoration and reapplication |
| Unpatched source | Direct `build` and `install` | Nonzero exit with the required-patch diagnostic |
| Invalid required patch | Missing, empty, and incompatible patch through `build`, `all`, `github`, and `install` | Nonzero exit and the required-patch diagnostic before configuration, compilation, or installation |
| Direct workflow | `init`, configuration, `build`, `install`; original and prepatched source | Corrected installed headers and shared library |
| Combined workflow | `init`, then parallel `all`; original and prepatched source | Ordered configuration, build, and corrected installation |
| Complete workflow | Parallel `github` from a fresh source directory | Source initialization and corrected installation |
| Writable prefix | Ordinary-user `github` into a new nested prefix, then installation into that existing prefix | Every installed path belongs to the invoking user |
| Protected prefix | Ordinary-user `github` with container-local sudo | Installed artifacts belong to root; source and build files remain user-owned |
| Vendor record, no Git checkout | Every installation above | `cfg` holds only the directory `uldaq` with `build-record` and `build-record.sha256`; `build-record` equals the expected lines, with the `readelf` build-id and the SHA-256 of the installed shared object, `tag=unknown` and `source=unknown`, the upstream version and tag, the patch file name, and the architecture; the digest file equals the SHA-256 of `build-record` |
| Vendor record, Git checkout | Installation from a Git checkout: untagged commit, several tags on `HEAD`, modified tracked file | `tag=untagged`, then the highest tag by version order, then `source=<hash>+dirty` |
| Vendor record, patch states | The record writer called directly after `patch.revert`, and again with a patch file that names another source file | No patch line when the patch is not applied, and `patch=unknown` when its state cannot be classified |
| Uninstall | `uninstall` twice with another wrapper's files in the same prefix | Only this wrapper's files and emptied directories are removed; the second run exits 0 and removes nothing |

## Evidence And Verdicts

Each run records hashes of the complete declared build/test input set in
`source.tsv`, native command arguments, UTC start times, elapsed time and
exit codes in `commands.tsv`, and full command output under `logs/`. Every
assertion is persisted in `checks.tsv`; installed header and library hashes
and ownership are retained in the `*-installation.txt` records. `result.txt`
records the final outcome and whether all required cases completed. A confirmed
failed assertion remains Failed; a run that stops without a failed assertion is
Incomplete. Only a completed run with no failures is Passed.

The suite has no sustained-rate or long-duration acceptance claim. A command
has a 900-second execution bound; it is an execution limit, not a performance
requirement. The case matrix above defines coverage. File removal and invalid
patch contents are faults at the actual filesystem input boundary. Installation
checks consume the files produced by the real installer, not a success marker.

The baseline patch cycle is the bounded rehearsal before compilation. Required
input faults are checked before longer builds. Keep the first failed evidence
unchanged when correcting a tool, and run corrected bytes in a new workspace.
Output capture is sequential and file-backed; it does not collect a continuous
event stream or require rate, rotation, clock-boundary, or replay services.

## Regression Controls

`mutations.tsv` lists each mutation with its expected failing assertion;
`build-mutants.bash` builds one scratch copy per row, requires the old text to
occur exactly once, and records the file hashes before and after the change. Run
the suite on each copy and compare the failing assertion with the table. The
rows are: use a literal `sudo` on the library install of `src_install` (ownership assertion), remove
`build`'s patch prerequisite (unpatched-source assertion), drop a line of the
`build-record` (record assertion), and remove the whole `cfg` directory on
uninstall (uninstall assertion). Further rows break the tag order of the record
(`sort -V` replaced by a plain sort), drop the `+dirty` marker, set the
privilege variable to always use `sudo` (ownership assertion), write a patch
line for a patch that is not applied, and drop the `patch=unknown` line for an
unclassifiable patch. A failure at an unrelated setup step does not
establish a regression.

## Timeout Test

`test_timeout.pl` checks the network timeout configuration items against an installed
patched library. The library and the client calls are real; only the external TC32
endpoint is simulated, by `fixtures/TC32.pm` (a copy of the measComp fixture; the origin
commit and SHA-256 are in `fixtures/TC32.pm.source`). The test is not part of the
continuous-integration workflows, because it needs a network namespace.

```bash
perl tests/test_timeout.pl --prefix /opt/uldaq --workspace /tmp/uldaq-timeout-check
```

The prefix holds `include/uldaq.h` and `lib/libuldaq.so`. The script re-executes itself
under `unshare -Urn`, creates the dummy interface `sim0` and the fixture address on `lo`,
compiles `timeout_client.cpp` against the library, and drives the client through a line
protocol while it serves the fixture. Requirements: Perl with core modules only (the
fixture states Perl 5.26 or newer), `g++`, `ip`, and `unshare`. Exit status 0 is Passed,
1 is Failed, 2 is Incomplete.

| Claim | Fault | Required result |
| --- | --- | --- |
| Defaults | none | Both items read 3000 |
| Set and read | none | The set values are read back |
| Invalid values | `0`, `-1`, `2147483648` | `ERR_BAD_CONFIG_VAL`, stored values unchanged |
| Connect bound | device does not answer UDP queries | `ulConnectDaqDevice()` fails within the window of the connection timeout: 700 ms with the command timeout set to 300 ms (a step that still used the command timeout would end early), and the default 3000 ms |
| Command bound | device accepts a command and stops answering | The command fails with `ERR_DEV_NOT_CONNECTED` within the window of the command timeout alone (400 ms, with the connection timeout set to 600 ms: a state query that waited for it would end later) |
| Reconnect | none | The values stay when the same handle is connected again |
| Exposure | the `timeout` fault | The fixture records the fault, and records no unsupported request |

A wait of expected length T must end no earlier than T minus 5 ms and no later than
1.125 T plus 100 ms: the kernel timer wheel rounds a socket timeout up by at most 12.5
percent. A run keeps `checks.tsv`, `client.txt`, `commands.txt`, `library.txt` (resolved
library path and SHA-256), and `result.txt` in the workspace.

`timeout-mutations.json` lists six mutations of the patched `NetDaqDevice.cpp` and `ETc32.h` with the
expected failing checks. Build the scratch copies with `build-mutants.py` of the
test-framework skill on a built source tree, rebuild each copy, and run the test against
its library; a mutation counts only when the failing checks match the table and the
source hash read by the build equals `mutated_sha256`.

Not covered: the TCP connect step (the fixture cannot drop the SYN packet separately from
the UDP queries), the connection code query as the step that ends the wait, USB devices,
and real hardware.

## Transport Verification Boundary

The build suite does not establish TC32 recovery. That check uses the existing
measComp `tests/build_reconnect.py`, `tests/test_reconnect.py`, TC32 endpoint
fixture, and temperature record template with real EPICS Base 7.0.10 and asyn.
Build the consumer against the installed ULDAQ headers and shared library,
record its input hashes and loaded-library identity, and run original and
corrected libraries separately in isolated network namespaces. The original
library must reproduce EOF last-value loss; the corrected library must pass
all transport, policy, and normal-exit checks. Only the external device endpoint
is simulated. This does not establish hardware or endurance acceptance.
