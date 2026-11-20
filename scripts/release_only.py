"""Identify a release-please version bump for CI and docs workflows."""

import json
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args])


def release_only(base, head):
    manifest = ".release-please-manifest.json"
    # Match the version fields release-please owns. In Cargo.lock only the
    # local markup package may change; dependencies must still go through CI.
    fields = {
        manifest: rb'(?m)^  "\.": "{v}"$',
        "Cargo.toml": rb'\[package\]\nname = "markup"\nversion = "{v}"',
        "Cargo.lock": rb'\[\[package\]\]\nname = "markup"\nversion = "{v}"',
        ".claude-plugin/plugin.json": rb'(?m)^  "version": "{v}",$',
        ".claude-plugin/marketplace.json": rb'(?m)^      "version": "{v}"$',
        "lua/markup/config.lua": rb'(?m)^\tversion = "{v}", -- x-release-please-version$',
        "llms.txt": rb'(?m)^Version {v} <!-- x-release-please-version -->$',
        "skills/markup-nvim/SKILL.md": rb'(?m)^(?:  version: "{v}" # x-release-please-version|For markup\.nvim {v}\. <!-- x-release-please-version -->)$',
    }
    changed = git("diff", "--name-only", "-z", base, head).decode().split("\0")[:-1]
    if set(changed) != set(fields) | {"CHANGELOG.md"}:
        return False
    if git("diff", "--summary", base, head):  # renames, additions, mode changes
        return False

    def version(ref):
        return json.loads(git("show", f"{ref}:{manifest}"))["."].encode()

    old, new = version(base), version(head)
    if old == new or not re.fullmatch(rb"\d+\.\d+\.\d+", new):
        return False

    for path, pattern in fields.items():
        before = git("show", f"{base}:{path}")
        after = git("show", f"{head}:{path}")
        expected, count = re.subn(
            pattern.replace(b"{v}", re.escape(old)),
            lambda match: match[0].replace(old, new),
            before,
        )
        if count != (2 if path == "skills/markup-nvim/SKILL.md" else 1) or expected != after:
            return False
    return True


if __name__ == "__main__":
    print("true" if release_only(*sys.argv[1:]) else "false")
