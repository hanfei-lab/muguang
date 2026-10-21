#!/usr/bin/env python3
"""Check deployment metadata in the distributed app and its login helper."""
import pathlib
import plistlib
import re
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
expected = {"x86_64": "10.15", "arm64": "11.0"}
bundles = [(app, "Muguang"),
           (app / "Contents/Library/LoginItems/MuguangLoginHelper.app", "MuguangLoginHelper")]
for bundle, executable_name in bundles:
    with (bundle / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info["LSMinimumSystemVersion"] == "10.15", bundle
    assert info["LSMinimumSystemVersionByArchitecture"] == expected, bundle
    assert info["CFBundleShortVersionString"] == "0.2.2", bundle
    executable = bundle / "Contents/MacOS" / executable_name
    arches = subprocess.check_output(["xcrun", "lipo", "-archs", str(executable)], encoding="utf-8").split()
    assert set(arches) == set(expected), arches
    for arch, minimum in expected.items():
        output = subprocess.check_output(["xcrun", "otool", "-arch", arch, "-l", str(executable)], encoding="utf-8")
        match = re.search(r"cmd LC_BUILD_VERSION.*?\bminos\s+(\d+(?:\.\d+)*)", output, re.S)
        assert match and match.group(1) == minimum, (bundle, arch, output)
        print("PASS: {} {} deployment target {}".format(executable_name, arch, minimum))
print("PASS: main/helper bundle metadata and both architecture slices")
