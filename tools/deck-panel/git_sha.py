# PlatformIO pre-build script (#615): puts the repo's short commit on the test screen, so whoever looks at the glass
# can tell which build is on it. "-dirty" when tools/deck-panel has uncommitted changes; "unknown" outside git.
import subprocess


def short_sha(cwd):
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=cwd, capture_output=True, text=True,
                             check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--", "."], cwd=cwd, capture_output=True, text=True,
                               check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return sha + ("-dirty" if dirty else "")


Import("env")  # noqa: F821 (PlatformIO's SCons global)
env.Append(CPPDEFINES=[("DECK_PANEL_SHA", '\\"%s\\"' % short_sha(env.subst("$PROJECT_DIR")))])  # noqa: F821
