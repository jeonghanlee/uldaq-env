# ULDAQ 1.2.2 Build And Installation

Release line: master
Milestone index: 988b152
Canonical path: `docs/milestone-988b152.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: jeonghanlee/uldaq-env issues #1 and #2; no GitHub milestone

Next session entry point: `docs/milestone-988b152.md`: M1 and M2 are complete, with issues #2 and #1 closed on 2026-11-04. Commit and publish the final verification and closure records under separate Git authority; version-tag placement is a separate follow-up.

## Scope

Obtain ULDAQ 1.2.2, maintain the TCP receive correction in this repository, and distribute a verified source revision through the existing build and installation workflow. Preserve ordinary-user ownership when the installation prefix is writable and use elevated installation privileges only when required.

Out of scope: EPICS-env vendor integration, measComp reconnect implementation, production IOC deployment, and hardware acceptance. The downstream recovery work is tracked in jeonghanlee/EPICS-env#120.

## Milestone

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Distribute ULDAQ 1.2.2 with the TCP receive fix | Milestone | Complete | No | D1, G1 | Published in 0320f5e; required CI and fresh-checkout distribution verification passed; issue #2 body synchronized and closed on 2026-11-04; [detail](#m1---distribute-uldaq-122-with-the-tcp-receive-fix) |
| M2 | Respect installation prefix permissions | Milestone | Complete | No | D2, G1 | Published fix and required CI satisfy acceptance; issue #1 body synchronized and closed on 2026-11-04; [detail](#m2---respect-installation-prefix-permissions) |
| G1 | Authorize repository publication | External gate | Complete | No | | Commit and push authorized and completed on 2026-11-04; [detail](#g1---authorize-repository-publication) |

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
Status: Complete

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
- G1 completed on 2026-11-04 after commit and push authorization; resumed as In progress. The implementation is published in 0320f5edecfaa16cf6ef75aaee122487f68aca12.
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
| T3 | 2026-11-04 | Debian 12, Rocky 8.10, Rocky 9 local containers and GitHub Actions | Passed | 143 local build checks per platform; published revision 0320f5e passed all three remote build/install jobs; [published results](verification-uldaq-1.2.2.md#published-revision-and-github-actions). |
| T4 | 2026-11-04 18:10 UTC | Debian 13; real EPICS Base 7.0.10, asyn 4.45.0 and measComp; isolated TC32 network fixture | Passed | Original installed library reproduced EOF value loss; corrected installed library passed 29/29 with normal IOC exit; [library and fixture identities](verification-uldaq-1.2.2.md#transport-results). |
| T5 | 2026-11-04 21:46 UTC | Published revision 0320f5e; Debian 12 GitHub Actions | Passed | Fresh checkout fetched the exact published revision; all 17 build/test input hashes matched; direct, all, and github installations passed with recorded header/library hashes; [published checkout reproduction](verification-uldaq-1.2.2.md#published-checkout-reproduction). |

The installed-library comparison above was executed for this implementation. It is separate from the earlier candidate results in jeonghanlee/EPICS-env#120 and does not establish publication, hardware acceptance, or downstream integration.

##### Closure Evidence

- Local verification is recorded in [ULDAQ 1.2.2 Verification](verification-uldaq-1.2.2.md).
- 2026-11-04: implementation and maintainer-documentation review found no open corrective findings.
- Published implementation: 0320f5edecfaa16cf6ef75aaee122487f68aca12. Debian 12, Rocky 8.10, and Rocky 9 GitHub Actions passed; [run links](verification-uldaq-1.2.2.md#published-revision-and-github-actions).
- 2026-11-04: M1 / T5 passed using the existing Debian 12 CI execution. Its checkout log and verification artifact establish the published revision, exact build inputs, successful real build/install commands, and installed-library identity; [evidence](verification-uldaq-1.2.2.md#published-checkout-reproduction).
- 2026-11-04 21:57 UTC: issue #2 body synchronized with all eight acceptance items checked; [closure comment](https://github.com/jeonghanlee/uldaq-env/issues/2#issuecomment-6643143158) published. Remote state verified as closed with reason completed at 2026-11-04T21:57:24Z. All required verification and the linked-issue closure condition are satisfied.

##### GitHub Projection

Title: Distribute ULDAQ 1.2.2 with the TCP receive fix
Labels: bug
GitHub Milestone: none
Observed State: closed
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-04 21:57 UTC; remote updated at 2026-11-04T21:57:24Z. State is closed with reason completed, label is bug, assignee is jeonghanlee, and milestone is none. Remote body and closure comment match the prepared content. Recheck with `gh issue view 2 --repo jeonghanlee/uldaq-env`.

#### M2 - Respect installation prefix permissions

Origin: 988b152 / M2
Identity History: none
GitHub Issue: #1, https://github.com/jeonghanlee/uldaq-env/issues/1
Status: Complete

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
- G1 completed on 2026-11-04 after commit and push authorization; resumed as In progress. The implementation is published in 0320f5edecfaa16cf6ef75aaee122487f68aca12.
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
| T1 | 2026-11-04 | Debian 12, Rocky 8.10, Rocky 9 local containers and GitHub Actions | Passed | 15 local checks per platform; the real ordinary-user installation step also passed in each published CI job; [local results](verification-uldaq-1.2.2.md#local-container-results) and [CI results](verification-uldaq-1.2.2.md#published-revision-and-github-actions). |
| T2 | 2026-11-04 | Same platforms; protected `/opt` prefix | Passed | 11 local checks per platform; the protected-prefix installation step also passed in each published CI job; [CI results](verification-uldaq-1.2.2.md#published-revision-and-github-actions). |
| T3 | 2026-11-04 | Same three Linux CI images, executed locally and on GitHub Actions | Passed | 143 local build checks per platform; published revision 0320f5e passed all three remote build/install jobs. The literal-sudo mutation failed the real ownership assertion; [regression controls](verification-uldaq-1.2.2.md#regression-controls). |

##### Closure Evidence

- Local verification is recorded in [ULDAQ 1.2.2 Verification](verification-uldaq-1.2.2.md).
- 2026-11-04: implementation and maintainer-documentation review found no open corrective findings.
- Published implementation: 0320f5edecfaa16cf6ef75aaee122487f68aca12. All required build and installation steps passed on Debian 12, Rocky 8.10, and Rocky 9 GitHub Actions; [run links](verification-uldaq-1.2.2.md#published-revision-and-github-actions).
- 2026-11-04 21:24 UTC: issue #1 body synchronized with all five acceptance items checked; [closure comment](https://github.com/jeonghanlee/uldaq-env/issues/1#issuecomment-6642478546) published. Remote state verified as closed with reason completed at 2026-11-04T21:24:31Z.

##### GitHub Projection

Title: github target hard-codes sudo
Labels: bug
GitHub Milestone: none
Observed State: closed
Observed Labels: bug
Observed Milestone: none
Last Compared: 2026-11-04 21:24 UTC; remote updated at 2026-11-04T21:24:31Z. State is closed with reason completed, label is bug, assignee is jeonghanlee, and milestone is none. Remote body and closure comment match the prepared content. Recheck with `gh issue view 1 --repo jeonghanlee/uldaq-env`.

#### G1 - Authorize repository publication

Origin: 988b152 / G1
GitHub Issue: none
Status: Complete

##### Summary

The repository owner supplied separate commit and push authority on 2026-11-04. Publication of the reviewed implementation and the subsequent CI expansion completed under that authority.

##### Completion Criteria

- Commit authority and push authority for the reviewed changes are recorded.

##### Verification Results

| Observed At | Result | Evidence |
| --- | --- | --- |
| 2026-11-04 | Complete | Separate commit and push authority recorded; 0320f5edecfaa16cf6ef75aaee122487f68aca12 and c54a7e7d453ebe795ef2e7aadd7e56e69146eeb3 are published on origin/master. |

##### Closure Evidence

- 2026-11-04: both authorized publications completed. The remote master reference was verified as c54a7e7d453ebe795ef2e7aadd7e56e69146eeb3 after the CI expansion push.

## Backlog

### Work

| ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- |

### Backlog Details

No unassigned work is recorded in this document.
