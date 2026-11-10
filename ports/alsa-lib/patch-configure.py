#!/usr/bin/env python3
"""Short-circuit alsa-lib's generated configure probes.

gcpkg has already probed the active triplet once.  This script replaces the
few unconditional compile/link/CPP/subprocess tests in the generated configure
with those explicit results.  Every replacement must match exactly once.
"""
import re
import sys

def between(text, start, end, replacement, label):
    i = text.find(start)
    if i < 0:
        raise SystemExit("PATCH START NOT FOUND: " + label)
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit("PATCH END NOT FOUND: " + label)
    return text[:i] + replacement + text[j:]

def once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise SystemExit("PATCH COUNT %d (expected 1): %s" % (n, label))
    return text.replace(old, new, 1)

def patch(text):
    # LFS dirent64 compile+link probe -> shared toolchain fact.
    text = between(
        text,
        'cat confdefs.h - <<_ACEOF >conftest.$ac_ext\n/* end confdefs.h.  */\n#include <dirent.h>',
        'if test "$have_lfs" = "yes"; then',
        'have_lfs="$gcpkg_have_lfs"\n',
        "LFS")
    # __thread compile+link probe -> shared toolchain fact.
    text = between(
        text,
        '$as_echo_n "checking for __thread... " >&6; }',
        'rm -f core conftest.err conftest.$ac_objext \\\n    conftest$ac_exeext conftest.$ac_ext\n',
        '$as_echo_n "checking for __thread... " >&6; }\n'
        'if test "$gcpkg_have___thread" = "yes"; then\n'
        '  $as_echo "#define HAVE___THREAD 1" >>confdefs.h\n'
        '  { $as_echo "$as_me:${as_lineno-$LINENO}: result: yes" >&5\n'
        '  $as_echo "yes" >&6; }\n'
        'else\n'
        '  { $as_echo "$as_me:${as_lineno-$LINENO}: result: no" >&5\n'
        '  $as_echo "no" >&6; }\n'
        'fi\n',
        "__thread")
    # MMX inline-asm compile+link probe -> shared arch fact.
    text = between(
        text,
        'cat confdefs.h - <<_ACEOF >conftest.$ac_ext\n/* end confdefs.h.  */\n\nint\nmain ()\n{\n__asm__ volatile ("" : : : "mm0");',
        'rm -f core conftest.err conftest.$ac_objext \\\n    conftest$ac_exeext conftest.$ac_ext\n',
        'if test "$gcpkg_have_mmx" = "yes"; then\n'
        '  $as_echo "#define HAVE_MMX \\"1\\"" >>confdefs.h\n'
        'fi\n',
        "MMX")
    # ld --help probe: --enable-symbolic-functions is already an explicit gate.
    text = once(text,
                "if ld --help | grep -q -- '-Bsymbolic-functions'; then",
                'if test "$symfuncs" = "yes"; then',
                "symbolic-functions")
    # CPP preprocessor probe for __USER_LABEL_PREFIX__ -> shared triplet fact.
    text, n = re.subn(r'SYMBOL_PREFIX=`.*?s:\^PREFIX=::"`',
                      'SYMBOL_PREFIX="$gcpkg_symbol_prefix"', text,
                      count=1, flags=re.S)
    if n != 1:
        raise SystemExit("PATCH COUNT %d (expected 1): SYMBOL_PREFIX" % n)
    # Softfloat is an enabled feature, but upstream uses it to silently turn
    # OFF alisp and two PCM plugins.  Keep every feature on; retain -lm so
    # the float plugins still link on a hardware-FPU triplet.
    text = once(text,
                'ALSA_DEPLIBS=""\nif test "$softfloat" != "yes"; then\n  ALSA_DEPLIBS="-lm"\nfi',
                'ALSA_DEPLIBS="-lm"', "softfloat -lm")
    text = once(text,
                'test "$softfloat" = "yes" && build_alisp="no"',
                ':', "softfloat alisp")
    text = once(text,
                'if test "$softfloat" = "yes"; then\n  build_pcm_lfloat="no"\n  build_pcm_ladspa="no"\nfi',
                ':', "softfloat pcm plugins")
    # python3-config / python-config subprocesses -> explicit --with-python* args.
    text = once(text,
                'pythonlibs0=$(python3-config --libs --embed 2> /dev/null)',
                'pythonlibs0=', "python3-config embed")
    text = once(text,
                'pythonlibs0=$(python3-config --libs)',
                'pythonlibs0=', "python3-config libs")
    text = once(text,
                'pythoninc0=$(python3-config --includes)',
                'pythoninc0=', "python3-config includes")
    text = once(text,
                'pythonlibs0=$(python-config --libs)',
                'pythonlibs0=', "python-config libs")
    text = once(text,
                'pythoninc0=$(python-config --includes)',
                'pythoninc0=', "python-config includes")
    return text

def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: patch-configure.py CONFIGURE [OUTPUT]")
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    with open(src, "r", encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    out = patch(text)
    with open(dst, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(out)
    print("PATCH_CONFIGURE_OK " + dst)

if __name__ == "__main__":
    main()
