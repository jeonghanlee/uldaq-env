# Build And Installation Verification

`test_build.py` copies the real build files into fresh isolated directories
and invokes their actual Make targets. The first source initialization uses
the configured upstream repository. Later cases clone that real Git checkout
as a local source cache; each clone must resolve to the expected 1.2.2 commit.
No configure, compiler, patch, installation, or internal library operation is
replaced with a substitute.

## Execution

Install the repository's build dependencies, Git, Python 3, and `patch`.
Choose a new workspace path for each run; the suite retains it on both
success and failure.

```bash
python3 -B tests/test_build.py --workspace /tmp/uldaq-build-check
```

Use `--config-target conf.rocky8` for the direct Rocky 8 configuration path.
The `all` and `github` cases exercise their own default configuration step.
The existing Linux workflows run the suite as root and then run `--mode user`
and `--mode protected --protected-prefix /opt/uldaq-ci` as an ordinary user.
Those permission cases require disposable containers with a container-local
passwordless sudo policy; they do not modify host policy or host prefixes.

## Required Cases

| Case | Real Path | Required Result |
| --- | --- | --- |
| Source identity | `init` and upstream Git checkout | Expected 1.2.2 commit |
| Patch lifecycle | Apply, apply again, revert, reapply | Exact two-line correction, idempotence, byte-exact restoration and reapplication |
| Unpatched source | Direct `build` and `install` | Nonzero exit with the required-patch diagnostic |
| Invalid required patch | Missing, empty, and incompatible patch through `build`, `all`, `github`, and `install` | Nonzero exit before configuration, compilation, or installation |
| Direct workflow | `init`, configuration, `build`, `install`; original and prepatched source | Corrected installed headers and shared library |
| Combined workflow | `init`, then parallel `all`; original and prepatched source | Ordered configuration, build, and corrected installation |
| Complete workflow | Parallel `github` from a fresh source directory | Source initialization and corrected installation |
| Writable prefix | Ordinary-user `github` into a new nested prefix, then installation into that existing prefix | Every installed path belongs to the invoking user |
| Protected prefix | Ordinary-user `github` with container-local sudo | Installed artifacts belong to root; source and build files remain user-owned |

## Evidence And Verdicts

Each run records hashes of the complete declared build/test input set in
`source.json`, native command arguments, UTC start times, elapsed seconds and
exit codes in `commands.json`, and full command output under `logs/`. Every
assertion is persisted in `checks.json`; installed header and library hashes
and ownership are retained in the installation records. `result.json` records
the final outcome and whether all required cases completed. A confirmed failed
assertion remains Failed; an execution exception without a failed assertion
is Incomplete. Only a completed run with no failures is Passed.

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

To prove the checks detect regressions, use separate scratch copies with one
mutation at a time: restore literal `sudo` in `github` and require the ordinary-
user ownership assertion to fail; remove `build`'s patch prerequisite and
require the unpatched-source assertion to fail. A failure at an unrelated
setup step does not establish either regression.

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
