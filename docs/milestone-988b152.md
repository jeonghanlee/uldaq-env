# ULDAQ 1.2.2 Build And Installation

Release line: master
Milestone index: 988b152
Canonical path: `docs/milestone-988b152.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: jeonghanlee/uldaq-env issues #1 and #2; no GitHub milestone

Next session entry point: `docs/milestone-988b152.md`, G1: obtain commit and push authority for the verified changes, publish them, then observe GitHub Actions and execute M1 / T5 from the published revision before closing issues #1 and #2.

## Scope

Obtain ULDAQ 1.2.2, maintain the TCP receive correction in this repository, and distribute a verified source revision through the existing build and installation workflow. Preserve ordinary-user ownership when the installation prefix is writable and use elevated installation privileges only when required.

Out of scope: EPICS-env vendor integration, measComp reconnect implementation, production IOC deployment, and hardware acceptance. The downstream recovery work is tracked in jeonghanlee/EPICS-env#120.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Distribute ULDAQ 1.2.2 with the TCP receive fix | Milestone | Blocked | No | D1, G1 | Local build and transport checks passed; publication, remote CI, and fresh published-checkout verification remain; [detail](#m1---distribute-uldaq-122-with-the-tcp-receive-fix) |
| M2 | Respect installation prefix permissions | Milestone | Blocked | No | D2, G1 | All three Linux containers passed ownership and installation checks; publication and remote CI remain; [detail](#m2---respect-installation-prefix-permissions) |
| G1 | Authorize repository publication | External gate | Open | No | | Separate commit and push authority for the reviewed changes; [detail](#g1---authorize-repository-publication) |

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Obtain ULDAQ 1.2.2, apply and maintain the TCP receive fix in uldaq-env, and distribute the corrected library. | 2026-11-03 |
| D2 | Resolve issues #1 and #2 through plan updates, implementation, and actual verification; keep GitHub milestone assignment empty. | 2026-11-04 |

### Milestone Details

#### M1 - Distribute ULDAQ 1.2.2 with the TCP receive fix

Origin: 988b152 / M1
Identity History: none
GitHub Issue: #2, https://github.com/jeonghanlee/uldaq-env/issues/2
Status: Blocked

##### Summary

`configure/RELEASE` selects ULDAQ 1.2.2, mccdaq/uldaq@f87594f7db478adb736a7868859133c45b6ec6b7. The unpatched source allows `NetDaqDevice::receiveFrame()` to return success after EOF or an incomplete TCP response header. A caller can accept an invalid sample before a later operation detects the disconnected device.

The correction returns `ERR_DEV_NOT_CONNECTED` for EOF and `ERR_DEAD_DEV` for an incomplete header, preserving the existing socket-error and complete-frame handling. The patch is required in addition to the measComp reconnection change tracked in jeonghanlee/EPICS-env#120.

`configure/RULES_FUNC` selects `patch/$(SRC_VERSION)-tcp-receive.p0.patch` with source-root-relative paths and `-p0`. Configuration applies the required patch; direct build and installation verify its presence. `all` and `github` execute their preparation, build, and installation steps in order under parallel Make.

##### Scope

- Update `SRC_TAG` and `SRC_VERSION` in `configure/RELEASE` to select ULDAQ 1.2.2.
- Carry the TCP receive patch in `patch/`, with its upstream basis and applicability documented.
- Make patch selection and apply/revert behavior explicit; a missing or incompatible required patch must fail before configuration and build continue.
- Ensure the direct `build` path and the `all` and `github` targets cannot compile unpatched source. Document and exercise these entry points and the complete source acquisition, patch, configuration, build, and installation sequence in the existing Linux CI jobs.
- Verify the installed library's identity and transport behavior with real consumer code.
- Publish a reproducible uldaq-env source revision and provide its immutable reference to the EPICS-env integration work.

Out of scope: changes to `tools/prep-vendors.bash` in EPICS-env, measComp reconnect code, new binary package formats, production deployment, and claims about hardware power cycling, sustained network loss, EXP-32, USB, or Windows. Additional platform claims require their own observed checks.

##### Completion Criteria

- A fresh source initialization obtains the intended ULDAQ 1.2.2 source; tag, commit, and configured version agree.
- The required patch is selected and applied before build; revert restores the original source exactly, and reapply reproduces the corrected source. Missing or incompatible patch input fails visibly.
- After the required initialization and configuration, `make build` followed by `make install`, `make all`, and `make github` produce the corrected installation. When entered with unpatched source, each build path must apply the required patch before compilation or fail before compilation; missing or incompatible required patch input must not reach build or installation.
- The documented build and installation sequence succeeds on the existing Debian 12, Rocky Linux 8, and Rocky Linux 9 CI targets, installing headers and the corrected shared library.
- An installed-library consumer runs the real TC32 transport regression with the reconnect-capable measComp driver and real EPICS/asyn/ULDAQ code. The unpatched library reproduces the EOF last-value failure; the patched library passes all required recovery and policy checks with normal IOC exit.
- Source identity and the library actually loaded at runtime are recorded using source references, configuration, library paths, and hashes. The API version string alone is not accepted as identity evidence.
- An immutable published uldaq-env revision contains the source selection, patch, build instructions, and verification evidence; a fresh checkout reproduces the corrected installation for downstream use.

##### Dependencies And Decisions

- D1 defines the assigned scope.
- G1 blocks publication as of 2026-11-04; resume as In progress after commit and push authority is recorded.
- EPICS-env consumes the published uldaq-env revision after this work. Its vendor integration and real-device acceptance are tracked in jeonghanlee/EPICS-env#120 and do not establish completion of this repository's checks.
- The functional regression requires the existing reconnect-capable measComp test fixture and real EPICS/asyn libraries. Record the exact fixture inputs and library identities with each run; simulate only the external TC32 UDP/TCP endpoint.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-04, reviewed issue #2 scope accepted for implementation.
Implementation Authorization: 2026-11-04, implement and verify both open issues.
Superseded Plan Artifacts: none

1. Select ULDAQ 1.2.2 in `configure/RELEASE` and verify the upstream source identity.
2. Add the TCP receive patch and align its filename, path format, selection rule, and strip level with the patch targets; reject missing or incompatible required input.
3. Verify apply, revert, reapply, and error handling on isolated copies of the actual upstream source.
4. Update the build and patch rules under `configure/` so direct `build`, `all`, and `github` enforce the required patch before compilation. Document the complete build/install sequence and exercise all three entry points in the existing Linux CI jobs while preserving the existing configuration targets.
5. Build and install into an isolated prefix, verify the library actually loaded by the consumer IOC, and run the real transport regression with both original and patched libraries.
6. After implementation and verification, prepare publication under the repository's Git workflow; record the published immutable reference and verify a fresh checkout before downstream consumption.

##### Test Plan

For T3, use isolated checkouts and installation prefixes. Exercise the documented `init`/configuration/`build`/`install` sequence and `init` followed by `all` with both unpatched and correctly patched source trees. Run each `github` case from a fresh checkout without an existing source directory so its own `init` supplies the source. Do not manually apply the patch before an unpatched-source check: the entry point must apply it before compilation or stop before compilation. For all three paths, also check missing or incompatible required patch input and a successful corrected installation. Do not replace the real Make targets or their configure, build, or install commands with substitutes.

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Source identity | Run the repository's real `make init`; inspect the upstream checkout and `configure/RELEASE`. | Fresh source directory | ULDAQ 1.2.2 resolves to the intended upstream commit; configured version agrees. |
| T2 | Patch lifecycle | Run real `make patch.apply`, `make patch.revert`, and reapply on upstream source; compare bytes and exercise missing/incompatible patch input. | Isolated actual upstream source trees | Exact correction, exact restoration, reproducible reapply, and nonzero failure for invalid required input. |
| T3 | Build entry points and installation | Execute the real direct `build`/`install`, `all`, and `github` paths with their required setup and the source/patch cases defined above; inspect installed headers and library. | Isolated CI jobs: Debian 12; Rocky Linux 8; Rocky Linux 9 | Each supported path installs the corrected library; no path compiles unpatched source, and invalid required patch input prevents build and installation. |
| T4 | Transport regression | Run the real consumer IOC, measComp driver, asyn, and installed ULDAQ against the existing TC32 network fixture; compare original and patched libraries and inspect loaded-library identity. | Isolated Linux network namespace; EPICS Base 7.0.10; recorded asyn and fixture revisions | Original library reproduces EOF last-value loss; patched library passes offline startup, EOF, short header, timeout, value retention, reconnection, settings restoration, port policy, and normal exit checks. |
| T5 | Distribution | Fetch the published immutable uldaq-env revision in a fresh checkout and execute its documented patch/build/install sequence. | Clean checkout and isolated install prefix | Published source reproduces the verified corrected installation; downstream has an immutable source reference. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-04 | Debian 12, Rocky 8.10, Rocky 9 local containers; Debian 13 host | Passed | Real `make init` resolved the expected upstream commit; [input identity](verification-uldaq-1.2.2.md#tested-input-identity). |
| T2 | 2026-11-04 | Isolated upstream source on all three local container platforms | Passed | Exact correction, repeated apply, byte-exact revert/reapply, and missing/empty/incompatible patch refusal; [results](verification-uldaq-1.2.2.md#local-container-results). |
| T3 | 2026-11-04 | Same three Linux CI images, executed locally | Local Passed; GitHub Actions Pending | 143 build checks per platform; separate configuration compatibility checks passed; [results and execution times](verification-uldaq-1.2.2.md#local-container-results). Remote workflows have not run for these changes. |
| T4 | 2026-11-04 18:10 UTC | Debian 13; real EPICS Base 7.0.10, asyn 4.45.0 and measComp; isolated TC32 network fixture | Passed | Original installed library reproduced EOF value loss; corrected installed library passed 29/29 with normal IOC exit; [library and fixture identities](verification-uldaq-1.2.2.md#transport-results). |
| T5 | Not run | Fresh published checkout | Pending | none |

The installed-library comparison above was executed for this implementation. It is separate from the earlier candidate results in jeonghanlee/EPICS-env#120 and does not establish publication, hardware acceptance, or downstream integration.

##### Closure Evidence

- Local verification is recorded in [ULDAQ 1.2.2 Verification](verification-uldaq-1.2.2.md).
- 2026-11-04: implementation and maintainer-documentation review found no open corrective findings.
- Repository commit, upstream landing evidence, remote CI, fresh published-checkout verification, and issue closure remain pending.

##### GitHub Projection

Title: Distribute ULDAQ 1.2.2 with the TCP receive fix
Labels: bug
GitHub Milestone: none
Observed State: open
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-04 18:29 UTC; remote updated at 2026-11-04T18:29:22Z. Body matches the verified candidate results; state is open, label is bug, assignee is jeonghanlee, and milestone is none. Recheck with `gh issue view 2 --repo jeonghanlee/uldaq-env`.

#### M2 - Respect installation prefix permissions

Origin: 988b152 / M2
Identity History: none
GitHub Issue: #1, https://github.com/jeonghanlee/uldaq-env/issues/1
Status: Blocked

##### Summary

The former literal `sudo` invocation in `github` created root-owned paths even under a writable installation prefix. `github` now uses the existing `SUDO` selection, based on the nearest existing installation ancestor. Source acquisition, patching, configuration, and compilation retain the invoking user's ownership; only a protected installation requires elevation.

##### Scope

- Use the existing `SUDO` selection for the installation step of `github`.
- Determine writability from the nearest existing ancestor when the installation prefix or its parents do not exist.
- Keep source acquisition, patching, configuration, and compilation under the invoking user's account.
- Verify writable and protected installation prefixes through the real `github` target on the supported Linux CI platforms.

Out of scope: ownership repair of earlier installations, host sudo policy changes, and additional platform support claims.

##### Completion Criteria

- An ordinary user can install into an existing or nested new writable prefix without elevated privileges; all installed files and directories belong to that user.
- A protected prefix still uses the available `sudo` command for installation and receives the installed headers and shared library.
- The existing Debian 12, Rocky Linux 8, and Rocky Linux 9 CI environments pass the real build and installation checks.
- The fix and verification evidence are published in this repository before issue closure.

##### Dependencies And Decisions

- D2 assigns this work. M1 and M2 share the build entry points but neither is a separate external gate for the other.
- G1 blocks publication as of 2026-11-04; resume as In progress after commit and push authority is recorded.
- Test-only sudo policy and protected prefixes exist inside disposable containers, not on the host.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-04, issue #1 scope accepted for implementation.
Implementation Authorization: 2026-11-04, implement and verify both open issues.
Superseded Plan Artifacts: none

1. Replace literal `sudo` in `configure/RULES_SRC` with the existing privilege selection, retaining ordered source, configuration, build, and installation steps.
2. Update `configure/CONFIG_SRC` to inspect the nearest existing installation ancestor, including missing nested directories.
3. Exercise real unprivileged and privileged installations in isolated Linux containers; retain command output, native exit status, source identity, artifact hashes, and file ownership.
4. Record results and prepare the fix for publication before closing the linked issue.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Writable installation | Run real `make github` as an ordinary user into a new nested prefix and repeat installation into the existing prefix; inspect ownership recursively. | Disposable Debian 12, Rocky Linux 8, and Rocky Linux 9 containers | Installation succeeds without root-owned paths under the prefix. |
| T2 | Protected installation | Run real `make github` as an ordinary user into a protected prefix using container-local passwordless sudo; inspect headers and shared library. | Same Linux containers, protected `/opt` prefix | Only installation is elevated and the expected artifacts exist with root ownership. |
| T3 | Root CI compatibility | Run real direct, `all`, and `github` entry points as root, sharing M1 / T3 evidence. | Existing Linux CI container images | Patched builds and installations succeed. |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-04 | Debian 12, Rocky 8.10, Rocky 9 local containers | Passed | 15 checks per platform: real ordinary-user `github`, nested new prefix, repeated install, and recursive ownership; [results](verification-uldaq-1.2.2.md#local-container-results). |
| T2 | 2026-11-04 | Same local containers; protected `/opt` prefix | Passed | 11 checks per platform: real elevated installation with root-owned artifacts and user-owned source/build tree; [results](verification-uldaq-1.2.2.md#local-container-results). |
| T3 | 2026-11-04 | Same three Linux CI images, executed locally | Local Passed; GitHub Actions Pending | Shared M1 / T3 evidence: 143 build checks per platform. The literal-sudo mutation failed the real ordinary-user ownership assertion; [regression controls](verification-uldaq-1.2.2.md#regression-controls). |

##### Closure Evidence

- Local verification is recorded in [ULDAQ 1.2.2 Verification](verification-uldaq-1.2.2.md).
- 2026-11-04: implementation and maintainer-documentation review found no open corrective findings.
- Repository commit, upstream landing evidence, remote CI, and issue closure remain pending.

##### GitHub Projection

Title: github target hard-codes sudo
Labels: bug
GitHub Milestone: none
Observed State: open
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-04 18:29 UTC; remote updated at 2026-11-04T18:29:18Z. Body matches the verified candidate results; state is open, label is bug, assignee is jeonghanlee, and milestone is none. Recheck with `gh issue view 1 --repo jeonghanlee/uldaq-env`.

#### G1 - Authorize repository publication

Origin: 988b152 / G1
GitHub Issue: none
Status: Open

##### Summary

The repository owner must provide the separate commit and push authority required by the repository Git workflow. This gate affects M1 and M2; it does not invalidate their completed local verification.

##### Completion Criteria

- Commit authority and push authority for the reviewed changes are recorded.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-11-04 | Open | Implementation and issue work are authorized; separate commit and push delegation has not been recorded. |

##### Closure Evidence

- none

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |

### Backlog Details

No unassigned work is recorded in this document.
