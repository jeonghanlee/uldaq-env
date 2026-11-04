"""Exercise the shipped Make targets against real ULDAQ source and toolchains."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


UPSTREAM_COMMIT = "f87594f7db478adb736a7868859133c45b6ec6b7"
PATCH_NAME = "1.2.2-tcp-receive.p0.patch"
CORRECTION = b"err = (received == 0) ? ERR_DEV_NOT_CONNECTED : ERR_DEAD_DEV;"
SOURCE_FILE = Path("src/net/NetDaqDevice.cpp")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Suite:
    def __init__(self, args):
        self.args = args
        self.repository = args.repository.resolve()
        self.workspace = args.workspace.resolve()
        self.workspace.mkdir(parents=True, exist_ok=False)
        self.logs = self.workspace / "logs"
        self.logs.mkdir()
        self.checks = []
        self.commands = []
        self.seed = args.source_repository
        self.snapshot = {}
        for member in [self.repository / "Makefile"] + [
                p for directory in ("configure", "tools", "patch", "tests")
                for p in sorted((self.repository / directory).rglob("*"))
                if p.is_file() and not p.name.endswith(".local") and "__pycache__" not in p.parts]:
            self.snapshot[str(member.relative_to(self.repository))] = digest(member)
        self.save("source.json", self.snapshot)

    def save(self, name, value):
        (self.workspace / name).write_text(json.dumps(value, indent=2) + "\n")

    def check(self, name, condition, evidence=None):
        self.checks.append({"name": name, "passed": bool(condition), "evidence": evidence})
        self.save("checks.json", self.checks)
        print("[{}] {}".format("PASS" if condition else "FAIL", name), flush=True)
        if not condition:
            raise AssertionError(name)

    def run(self, cwd, command, expected=0):
        log_path = self.logs / "{:03d}-{}.log".format(len(self.commands) + 1, cwd.name)
        env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": os.environ["HOME"],
               "LANG": "C", "LC_ALL": "C", "PYTHONDONTWRITEBYTECODE": "1"}
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        before = time.monotonic()
        with log_path.open("w") as log:
            result = subprocess.run(command, cwd=str(cwd), env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=900)
        self.commands.append({"cwd": str(cwd), "argv": command, "started": started,
                              "seconds": time.monotonic() - before,
                              "exit_code": result.returncode, "log": str(log_path)})
        self.save("commands.json", self.commands)
        if expected is not None:
            self.check(cwd.name + ": " + " ".join(command[:3]),
                       result.returncode == expected,
                       {"exit_code": result.returncode, "log": str(log_path)})
        return result.returncode, log_path.read_text()

    def make(self, case, prefix, *targets, **kwargs):
        command = ["make", "-j" + str(self.args.jobs)] + list(targets)
        command.append("INSTALL_LOCATION=" + str(prefix))
        if self.seed:
            command.append("SRC_GITURL=" + str(self.seed))
        return self.run(case, command, **kwargs)

    def case(self, name):
        case = self.workspace / name
        case.mkdir()
        shutil.copy2(str(self.repository / "Makefile"), str(case / "Makefile"))
        for directory in ("configure", "tools", "patch"):
            shutil.copytree(str(self.repository / directory), str(case / directory),
                            ignore=shutil.ignore_patterns("*.local", "__pycache__"))
        self.check(name + ": exact build inputs", all(
            digest(case / member) == value for member, value in self.snapshot.items()
            if not member.startswith("tests/")))
        return case, case / "prefix" / "nested" / "install"

    def initialized(self, name):
        case, prefix = self.case(name)
        self.make(case, prefix, "init")
        _, commit = self.run(case / "uldaq-src", ["git", "rev-parse", "HEAD"])
        self.check(name + ": upstream commit", commit.strip() == UPSTREAM_COMMIT, commit.strip())
        if not self.seed:
            self.seed = case / "uldaq-src"
        return case, prefix

    def installed(self, case, prefix, owner=None):
        header, library = prefix / "include/uldaq.h", prefix / "lib/libuldaq.so"
        self.check(case.name + ": installed artifacts", header.is_file() and library.is_file())
        self.check(case.name + ": installed header", digest(header) == digest(case / "uldaq-src/src/uldaq.h"))
        self.check(case.name + ": compiled source correction",
                   CORRECTION in (case / "uldaq-src" / SOURCE_FILE).read_bytes())
        self.run(case, ["ldd", str(library)])
        if owner is not None:
            wrong = [str(p) for p in [prefix] + list(prefix.rglob("*")) if p.lstat().st_uid != owner]
            self.check(case.name + ": installed ownership", not wrong, wrong)
        self.save(case.name + "-installation.json", {
            "header_sha256": digest(header), "library_sha256": digest(library),
            "library": str(library.resolve()), "prefix": str(prefix), "owner": owner})

    def patch_cycle(self):
        case, prefix = self.initialized("patch-cycle")
        source = case / "uldaq-src" / SOURCE_FILE
        original = source.read_bytes()
        code, output = self.make(case, prefix, "build", expected=None)
        self.check("unpatched direct build rejected", code != 0 and "required patch not applied" in output)
        self.make(case, prefix, "patch.apply")
        patched = source.read_bytes()
        self.check("exact TCP correction", patched != original and
                   patched.replace(b"\t\t\t// EOF or a short header cannot represent a complete response.\n"
                                   b"\t\t\t" + CORRECTION + b"\n", b"", 1) == original)
        self.make(case, prefix, "patch.apply")
        self.check("idempotent apply", source.read_bytes() == patched)
        self.make(case, prefix, "patch.revert")
        self.check("byte-exact revert", source.read_bytes() == original)
        self.run(case / "uldaq-src", ["git", "diff", "--exit-code"])
        code, output = self.make(case, prefix, "install", expected=None)
        self.check("unpatched installation rejected", code != 0 and "required patch not applied" in output)
        self.make(case, prefix, "patch.apply")
        self.check("byte-exact reapply", source.read_bytes() == patched)

    def invalid_patches(self):
        for target in ("build", "all", "github", "install"):
            for fault in ("missing", "empty", "incompatible"):
                name = target + "-" + fault
                case, prefix = self.case(name) if target == "github" else self.initialized(name)
                patch = case / "patch" / PATCH_NAME
                if fault == "missing":
                    patch.rename(patch.with_suffix(".disabled"))
                elif fault == "empty":
                    patch.write_text("")
                else:
                    patch.write_text(patch.read_text().replace("NetDaqDevice.cpp", "AbsentDevice.cpp"))
                code, output = self.make(case, prefix, target, expected=None)
                self.check(name + ": required patch rejected", code != 0 and "error: required patch" in output)
                source = case / "uldaq-src"
                self.check(name + ": no configuration or compilation",
                           not (source / "config.status").exists() and not list(source.rglob("*.o")))
                self.check(name + ": no installation", not prefix.exists())

    def builds(self):
        for target, prepatched in (("direct", False), ("direct", True),
                                   ("all", False), ("all", True), ("github", False)):
            name = target + ("-patched" if prepatched else "-original")
            case, prefix = self.case(name) if target == "github" else self.initialized(name)
            if prepatched:
                self.make(case, prefix, "patch.apply")
            if target == "direct":
                self.make(case, prefix, self.args.config_target)
                self.make(case, prefix, "build")
                self.make(case, prefix, "install")
            else:
                self.make(case, prefix, target)
            self.installed(case, prefix, os.getuid())

    def permissions(self):
        self.check("permission suite uses ordinary user", os.getuid() != 0, os.getuid())
        case, prefix = self.case(self.args.mode + "-github")
        if self.args.mode == "protected":
            prefix = self.args.protected_prefix
            self.check("protected prefix specified", prefix is not None)
            self.check("protected parent not writable", not os.access(str(prefix.parent), os.W_OK))
        self.make(case, prefix, "github")
        self.installed(case, prefix, 0 if self.args.mode == "protected" else os.getuid())
        self.check("source remains user-owned", all(
            p.lstat().st_uid == os.getuid() for p in (case / "uldaq-src").rglob("*")))
        if self.args.mode == "user":
            self.make(case, prefix, "install")
            self.installed(case, prefix, os.getuid())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--source-repository", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--mode", choices=("build", "user", "protected"), default="build")
    parser.add_argument("--protected-prefix", type=Path)
    parser.add_argument("--config-target", default="conf")
    args = parser.parse_args()
    suite = Suite(args)
    complete = False
    error = None
    try:
        if args.mode == "build":
            suite.patch_cycle()
            suite.invalid_patches()
            suite.builds()
        else:
            suite.permissions()
        complete = True
    except Exception as failure:
        error = "{}: {}".format(type(failure).__name__, failure)
        print(error, flush=True)
    failed = [check["name"] for check in suite.checks if not check["passed"]]
    verdict = "Failed" if failed else ("Passed" if complete else "Incomplete")
    suite.save("result.json", {"complete": complete, "verdict": verdict, "error": error,
                               "total": len(suite.checks), "failed": failed,
                               "mode": args.mode, "source": suite.snapshot})
    print("{}: {} checks; evidence {}".format(verdict, len(suite.checks), suite.workspace), flush=True)
    return 0 if verdict == "Passed" else (1 if failed else 2)


if __name__ == "__main__":
    raise SystemExit(main())
