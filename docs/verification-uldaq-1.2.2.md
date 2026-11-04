# ULDAQ 1.2.2 Verification

Observed on 2026-11-04, x86-64 Linux. These results cover the build and test
inputs identified below, published in revision
0320f5edecfaa16cf6ef75aaee122487f68aca12. Its three required GitHub Actions
jobs passed. The published-checkout reproduction below also satisfies the
distribution acceptance criterion for issue #2.

## Source And Build Contract

The selected upstream is `mccdaq/uldaq`, tag `v1.2.2`, commit
`f87594f7db478adb736a7868859133c45b6ec6b7`. The versioned p0 patch changes only
the EOF and incomplete-header error assignment in `NetDaqDevice::receiveFrame`.
`UL_VERSION` remains 1.2.0 upstream and is not used to establish identity.

The real suite in [tests/test_build.py](../tests/test_build.py) exercised
source acquisition, exact apply/revert/reapply, invalid required patch inputs,
direct builds, parallel `all` and `github`, and the real installers. The
[case contract](../tests/README.md) defines the required observations.

## Local Container Results

Times are UTC on 2026-11-04. Each completed container command exited zero.
`build` runs as root; `user` installs into a new nested writable prefix and
repeats installation; `protected` invokes `github` as an ordinary user and
uses container-local sudo only for installation into `/opt/uldaq-ci`.

| Platform | Mode | First Command | Last Command End | Passed Checks |
| --- | --- | --- | --- | --- |
| Debian 12 | build | 18:08:13 | 18:13:55 | 143/143 |
| Debian 12 | user | 18:13:55 | 18:15:07 | 15/15 |
| Debian 12 | protected | 18:15:07 | 18:16:15 | 11/11 |
| Rocky Linux 8.10 | build | 18:10:12 | 18:14:57 | 143/143 |
| Rocky Linux 8.10 | user | 18:14:57 | 18:15:53 | 15/15 |
| Rocky Linux 8.10 | protected | 18:15:53 | 18:16:50 | 11/11 |
| Rocky Linux 9 | build | 18:17:25 | 18:22:17 | 143/143 |
| Rocky Linux 9 | user | 18:22:17 | 18:23:21 | 15/15 |
| Rocky Linux 9 | protected | 18:23:21 | 18:24:27 | 11/11 |

Every platform passed 169 checks. The images are `debian:bookworm-slim`,
`rockylinux/rockylinux:8.10`, and `rockylinux/rockylinux:9`; package sets match
their repository workflows. Rocky 8's direct configuration used `conf.rocky8`.
The Rocky 9 local image obtained packages from the official HTTPS base URL.
These are local container results, not remote GitHub Actions results.

Debian 13 additionally passed the 143-check build suite. Its installed library
was consumed by the transport comparison below. Separate real configure runs
passed 14 checks for `debugconf` and `conf.rocky10`, including patch presence
and preservation of `--enable-debug` and `--enable-new-dtags`, respectively.
This alias check on Debian does not establish Rocky 10 platform support.

### Additional CI Platforms

The workflow shell steps for Debian 13, Ubuntu 24.04, Ubuntu 26.04, and
Rocky Linux 10 also ran in local containers on 2026-11-04. Each run used
the real source, configure, compiler, patch, and installation paths; each
container command exited zero. The recorded workflow hashes match the
files published in c54a7e7d453ebe795ef2e7aadd7e56e69146eeb3.

| Platform | Container Image | Build | User | Protected |
| --- | --- | --- | --- | --- |
| Debian 13 | `debian:13-slim` | 143/143 | 15/15 | 11/11 |
| Ubuntu 24.04 | `ubuntu:24.04` | 143/143 | 15/15 | 11/11 |
| Ubuntu 26.04 | `ubuntu:26.04` | 143/143 | 15/15 | 11/11 |
| Rocky Linux 10 | `rockylinux/rockylinux:10` | 143/143 | 15/15 | 11/11 |

These 676 checks establish local build and installation coverage. They do
not exercise GitHub checkout, artifact upload, or event filtering services.

## Published Revision And GitHub Actions

The source selection, required patch, ownership correction, build instructions,
and verification evidence are published in
[0320f5edecfaa16cf6ef75aaee122487f68aca12](https://github.com/jeonghanlee/uldaq-env/commit/0320f5edecfaa16cf6ef75aaee122487f68aca12).
The following runs completed successfully, including checkout, root build,
ordinary-user installation, protected-prefix installation, and evidence upload.

| Platform | Published Revision | Result | Run |
| --- | --- | --- | --- |
| Debian 12 | 0320f5e | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41903647406) |
| Rocky Linux 8.10 | 0320f5e | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41903647320) |
| Rocky Linux 9 | 0320f5e | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41903647572) |

These results satisfy the publication and CI criteria for issue #1.
Revision c54a7e7d453ebe795ef2e7aadd7e56e69146eeb3 expands CI to seven Linux
platforms and updates checkout, artifact upload, and documentation-only event
filters without changing the build/test inputs listed below. Its runs are
separate from the three-platform verification above. All seven jobs completed
successfully on 2026-11-04:

| Platform | Published Revision | Result | Run |
| --- | --- | --- | --- |
| Debian 12 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912974755) |
| Debian 13 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912975041) |
| Ubuntu 24.04 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912974872) |
| Ubuntu 26.04 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912975043) |
| Rocky Linux 8.10 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912974943) |
| Rocky Linux 9 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912974947) |
| Rocky Linux 10 | c54a7e7 | Passed | [GitHub Actions](https://github.com/jeonghanlee/uldaq-env/actions/runs/41912974831) |

The README badges link to each workflow's current result. These successful
push runs do not directly test the exclusion of documentation-only events.

### Published Checkout Reproduction

The Debian 12 run for 0320f5edecfaa16cf6ef75aaee122487f68aca12 reproduced the
corrected installation from a fresh published checkout. Its job log records
`git init` at 20:08:26 UTC on 2026-11-04, followed by a fetch of that exact
commit. The associated `uldaq-debian12-verification` artifact identifies the
same commit and run. The log and artifact were inspected on 2026-11-04 at
21:46 UTC; [CI run and evidence](https://github.com/jeonghanlee/uldaq-env/actions/runs/41903647406).

All 17 build/test input hashes in each of the build, user, and protected
records matched the corresponding published file bytes. The real suite made
isolated copies of these exact build inputs, acquired the actual upstream
source, and executed the shipped patch, configure, compiler, and installer
paths. The records contain 143/143 build, 15/15 user, and 11/11 protected
checks, each with a complete Passed result.

| Initially Unpatched Case | Successful Make Sequence | Installation Result |
| --- | --- | --- |
| `direct-original` | `init`, `conf`, `build`, `install` | Corrected source, installed header and shared library |
| `all-original` | `init`, `all` | Corrected source, installed header and shared library |
| `github-original` | `github` | Corrected source, installed header and shared library |

Every command in these sequences exited zero. Each installation record
contains its resolved library path, prefix, owner, and SHA-256 hashes.
The three cases recorded the same header and library hashes:

| Installed File | SHA-256 |
| --- | --- |
| `include/uldaq.h` | 8cf7e3415ed465ee2cd8c867b947196fc7364740b1da5f398fab23daf95a62e5 |
| `lib/libuldaq.so.1.2.2` | b1da44fcc26188386248355b53d3c486f746038b848de61f47b3a188a338fdd1 |

This evidence satisfies the fresh published-checkout distribution criterion
for issue #2. It identifies the Debian 12 CI installations separately from
the Debian 13 libraries used for the transport comparison below; it makes no
claim of identical binary hashes across those environments.

## Transport Results

Both consumers used real EPICS Base 7.0.10, asyn 4.45.0, the reconnect-capable
measComp driver and its existing TC32 fixture in isolated network namespaces.
Only the external TC32 UDP/TCP endpoint was simulated. Each IOC was built
against its installed ULDAQ headers and library; `ldd` resolved `libuldaq` to
that installation before execution.

The original library failed the expected EOF value-retention assertion:
the last channel changed from 22.5 to 0.0. Six earlier assertions passed;
the test exited 1 and terminated that IOC after the failure. The corrected
library passed all 29 assertions, including observed EOF, short-header and
timeout faults, value retention, recovery, settings restoration, auto-connect
and enable policy, and normal IOC exit 0. Neither run reported fixture errors.

| Installed Library | SHA-256 |
| --- | --- |
| original | eba7bd444db2a38e1ef885efe79e8573e7b8a36d29e7fea8f8831225023f9955 |
| patched | 70d732c978adf108a5743612a31514b6a6024e7947a549aa73f0afa98705faf9 |

The following hashes identify the actual consumer and fixture inputs.

| measComp Input | SHA-256 |
| --- | --- |
| tests/reconnect_ioc.cpp | b44fd759b0724b6bb4300b740771d56ffdd140495664e6e36ce01c4b16344dd7 |
| measCompApp/src/drvMultiFunction.cpp | f1d3e202cea90d7eabaf4fd25316ebaa383662a63b2fc13ff9816d0c8cfaf367 |
| measCompApp/src/measCompDiscover.cpp | 2f770a1008ee3d30dd9d4aa8a75fb2d45f5d5e1056822b738946d69b69e023f8 |
| measCompApp/src/measCompDiscover.h | a942bfbb8fd596ef4ad1e9271e3b55ba3f6fbd7136bbd3ba6782fc36427ccee7 |
| measCompApp/Db/measCompTemperatureIn.template | 7e5e1b4bde7c2b15af70b558d34e061dd0822c0d5de57adf87a435b4aad3aa6b |
| tests/test_reconnect.py | a0bff3428da92bdaf618981807efd284d99c4b0998c319eaf5744d7ad2aa0cef |
| tests/tc32_simulator.py | ebd229b0f244ec42a63f1d5e056e5180ccf8790fbeead326fbc2635f9074ded7 |
| tests/build_reconnect.py | 8f87b37b2d96cb1e5b81d41c60da904df7bcfd5d771fe246d7050965e73819c6 |

## Regression Controls

Each mutation changed a separate scratch copy of the shipped code. The real
suite failed at the declared assertion; no configure, compiler, installer,
internal function, or test assertion was replaced. These expected failures
are regression controls and are not counted as successful product tests.

| Mutation | Expected Assertion | Observed |
| --- | --- | --- |
| build: patch.check -> build: | unpatched direct build rejected | Failed as required |
| $(QUIET) $(SUDO) $(MAKE) install -> $(QUIET) sudo $(MAKE) install | user-github: installed ownership | Failed as required |

## Tested Input Identity

All nine baseline container runs recorded the same complete build/test input map;
current bytes and membership were compared with that map. The suite excludes
site-local overrides and Python bytecode. Command arguments, UTC start times,
elapsed durations, native status, full logs, assertions, and installation
hashes are retained in each run's `commands.json`, `checks.json`, `source.json`,
`result.json`, `logs/`, and installation records. The workflows preserve these
same evidence types as downloadable artifacts when GitHub Actions runs.

| Build/Test Input | SHA-256 |
| --- | --- |
| Makefile | 2104e1e0dfdab46a8e4dc4edd560ddb5b3ee1f6f5f77761f0f710f94a3e26c6b |
| configure/CONFIG | e8a45810e5b6b0f38771589247b3390ccc2f38189bc7ae869f1370e66b19779d |
| configure/CONFIG_APPNAME | 621fcd414963ab1adbe1c1593f213f6f35b6b53bd3dc86fe4e93d5e60fd8a5c0 |
| configure/CONFIG_SITE | d4e29b41862bd89abeb2f70bfe68f58af257f7fb4ad6aeb38e230bf77769957c |
| configure/CONFIG_SRC | ba984dc46217cda349e0a3393dd1d8798a64dce0b227cfb115fcb0ab91078beb |
| configure/CONFIG_VARS | 8510f85cefc9ce5038ca30d9f790f4365b2a5ac22f935ff1a8b570ca7f4c38af |
| configure/RELEASE | 5ea12ff4da474eb2e02d63e9f3fe581653ac20ca1e166b09f2e33e1dbcf8e955 |
| configure/RULES | cdb171e752388a7c521014885903df518fcf61a076f34913b6755a92993485ce |
| configure/RULES_FUNC | c07acac240c29c00dbec3da195baacedf4398e7be69b1a5d0df60b71d67eba55 |
| configure/RULES_INSTALL | 45a3ae17f99dc1a69838fbfdcca0ead60415bc18f28b42a6f9720f44652102c9 |
| configure/RULES_PATCH | d5a9bb28ff0154e9cc073e3d2526e3cd69a321b0ac489027e731d73241015dbb |
| configure/RULES_SRC | 57972032d7df307fe35cb025113d31e65205196557fbc8d891da785648ceb426 |
| configure/RULES_VARS | 3ea60b796c9d8c3e4c39464a7cf69fcdcb4bbba6af621a5660620b823d169d4d |
| patch/1.2.2-tcp-receive.p0.patch | b60dcf7d08debbcca926629caedf8f7e0dbf333ec2853695b09d35e5737b5401 |
| tests/README.md | 026f70e7c122b2392b94845982f349c6fccdbed54d5ea899c459c3e5f13f6ec2 |
| tests/test_build.py | 62cdae8954122cd8ec37344c959e952c7a9b24d0f06c0c4c48b44021ce192195 |
| tools/patch-source.bash | 1d0aa7579c409d5b0653896c8482a1306eaf99804c0169809a2de39ad8a99aa2 |

## Limits

No production IOC, real-device power cycle, endurance, EXP-32, USB, Windows,
macOS, or hardware acceptance is established here. Rocky Linux 10 coverage
is limited to the recorded build and installation checks.
The consumer fixture belongs to the separate integration work tracked in
jeonghanlee/EPICS-env#120. Issue #1 has published build and installation
evidence; issue #2 also has verified fresh-checkout distribution evidence.
Neither result establishes downstream integration or hardware acceptance.
