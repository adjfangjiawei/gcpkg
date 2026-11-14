#!/usr/bin/env python3
"""Short-circuit ICU4C 72.1's generated configure probes.

gcpkg has already run ONE platform/toolchain probe for the active triplet and
passes its results through `config.cache` and GCPKG_* environment values.  ICU
must not compile, link or run conftest programs itself.  This patch only edits
the extracted configure script inside the store; it changes no build features.
"""
import os
import re
import shlex
import sys

ENV = {
    "GCPKG_C_STANDARD": "0",
    "GCPKG_CXX_STANDARD": "0",
    "GCPKG_COMPILER_ID": "unknown",
    "GCPKG_CROSS_COMPILING": "no",
    "GCPKG_DEFAULT_EXE": "a.out",
    "GCPKG_EXE_EXT": "",
    "GCPKG_OBJECT_EXT": "o",
}
for k in ENV:
    ENV[k] = os.environ.get(k, ENV[k])

def yn(ok):
    return "yes" if ok else "no"

cstd = int(ENV["GCPKG_C_STANDARD"] or 0)
cxxstd = int(ENV["GCPKG_CXX_STANDARD"] or 0)
compiler = ENV["GCPKG_COMPILER_ID"].lower()
gnu_like = compiler in ("clang", "gcc")
facts = {
    "GCPKG_C11_OK": yn(cstd >= 201112),
    "GCPKG_CXX_OK": yn(cxxstd >= 199711),
    "GCPKG_CXX11_OK": yn(cxxstd >= 201103),
    "GCPKG_CXX17_OK": yn(cxxstd >= 201703),
    "GCPKG_UTF16_C_OK": yn(cstd >= 201112 and gnu_like),
    "GCPKG_UTF16_CXX_OK": yn(cxxstd >= 201103 and gnu_like),
    "GCPKG_CROSS_COMPILING": ENV["GCPKG_CROSS_COMPILING"],
}

DEFAULT_EXE = shlex.quote(ENV["GCPKG_DEFAULT_EXE"])
EXE_FILE = shlex.quote("conftest" + ENV["GCPKG_EXE_EXT"])
OBJ_FILE = shlex.quote("conftest." + ENV["GCPKG_OBJECT_EXT"])
CROSS = shlex.quote(ENV["GCPKG_CROSS_COMPILING"])
C11 = shlex.quote(facts["GCPKG_C11_OK"])
CXX = shlex.quote(facts["GCPKG_CXX_OK"])
CXX11 = shlex.quote(facts["GCPKG_CXX11_OK"])
CXX17 = shlex.quote(facts["GCPKG_CXX17_OK"])
UTF16_C = shlex.quote(facts["GCPKG_UTF16_C_OK"])
UTF16_CXX = shlex.quote(facts["GCPKG_UTF16_CXX_OK"])

def once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise SystemExit("PATCH_COUNT %d (expected 1): %s" % (n, label))
    return text.replace(old, new, 1)

def replace_function(text, name, body, label):
    start = "# ac_fn_%s LINENO\n" % name
    end = "} # ac_fn_%s\n" % name
    i = text.find(start)
    if i < 0:
        raise SystemExit("PATCH START NOT FOUND: " + label)
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit("PATCH END NOT FOUND: " + label)
    return text[:i] + body + text[j + len(end):]

def in_range(text, start, end, old, new, label, count=1, optional=False):
    i = text.find(start)
    if i < 0:
        if optional:
            return text
        raise SystemExit("PATCH RANGE START NOT FOUND: " + label)
    j = text.find(end, i + len(start))
    if j < 0:
        raise SystemExit("PATCH RANGE END NOT FOUND: " + label)
    chunk = text[i:j]
    n = chunk.count(old)
    if n != count:
        raise SystemExit("PATCH RANGE COUNT %d (expected %d): %s" % (n, count, label))
    return text[:i] + chunk.replace(old, new) + text[j:]

def patch(text):
    # 1. Framework compiler checks: create dummy outputs, never invoke a
    #    compiler, linker, preprocessor or conftest program.
    text = re.sub(r'\(eval "\$ac_link_default"\)',
                  '( : > ' + DEFAULT_EXE + ' )', text)
    text = re.sub(r'\(eval "\$ac_link"\)',
                  '( : > ' + EXE_FILE + ' )', text)
    text = re.sub(r'\(eval "\$ac_compile"\)',
                  '( : > ' + OBJ_FILE + ' )', text)
    for var in ("$ac_link_default", "$ac_link", "$ac_compile", "$ac_cpp"):
        text = text.replace('ac_try="' + var + '"',
                            'ac_try="gcpkg: shared triplet facts"')
    # Autoconf also probes compiler version by invoking CC/CXX with
    # --version/-v/-V/-qversion.  Replace those commands with a no-op and
    # keep config.log free of compiler invocations.
    n_version = text.count('ac_try="$ac_compiler $ac_option >&5"')
    if n_version != 2:
        raise SystemExit("PATCH_COUNT %d (expected 2): compiler version ac_try" % n_version)
    text = text.replace('ac_try="$ac_compiler $ac_option >&5"',
                        'ac_try="gcpkg: shared triplet facts"')
    n_eval = text.count('(eval "$ac_compiler $ac_option >&5") 2>conftest.err')
    if n_eval != 2:
        raise SystemExit("PATCH_COUNT %d (expected 2): compiler version eval" % n_eval)
    text = text.replace('(eval "$ac_compiler $ac_option >&5") 2>conftest.err',
                        '( : ) 2>/dev/null')
    text = once(text, "if { ac_try='./conftest$ac_cv_exeext'",
                "if { ac_try=':'", "cross compiled conftest run")
    text = once(text,
                "    cross_compiling=no\n  else\n    if test \"$cross_compiling\" = maybe; then",
                "    cross_compiling=" + CROSS + "\n  else\n    if test \"$cross_compiling\" = maybe; then",
                "cross_compiling shared fact")

    # 2. Autoconf generic try helpers become pure no-ops, or a deterministic
    #    preprocessor result for the ac_nonexistent.h sanity probe.
    noop_c = """# ac_fn_c_try_compile LINENO
# gcpkg: library-side compile probes are forbidden; shared triplet facts win.
ac_fn_c_try_compile ()
{
  ac_retval=0
  return 0
} # ac_fn_c_try_compile
"""
    noop_cxx = """# ac_fn_cxx_try_compile LINENO
# gcpkg: library-side compile probes are forbidden; shared triplet facts win.
ac_fn_cxx_try_compile ()
{
  ac_retval=0
  return 0
} # ac_fn_cxx_try_compile
"""
    noop_link_c = """# ac_fn_c_try_link LINENO
# gcpkg: library-side link probes are forbidden; shared triplet facts win.
ac_fn_c_try_link ()
{
  ac_retval=0
  return 0
} # ac_fn_c_try_link
"""
    noop_link_cxx = """# ac_fn_cxx_try_link LINENO
# gcpkg: library-side link probes are forbidden; shared triplet facts win.
ac_fn_cxx_try_link ()
{
  ac_retval=0
  return 0
} # ac_fn_cxx_try_link
"""
    noop_run = """# ac_fn_c_try_run LINENO
# gcpkg: library-side run probes are forbidden; shared triplet facts win.
ac_fn_c_try_run ()
{
  ac_retval=0
  return 0
} # ac_fn_c_try_run
"""
    cpp = """# ac_fn_c_try_cpp LINENO
# gcpkg: no preprocessor process.  Autoconf deliberately feeds one missing
# header; detect that text and return failure, otherwise report success.
ac_fn_c_try_cpp ()
{
  if grep -q 'ac_nonexistent.h' "conftest.$ac_ext" 2>/dev/null; then
    ac_retval=1
    return 1
  fi
  ac_retval=0
  return 0
} # ac_fn_c_try_cpp
"""
    for name, body, label in [
        ("c_try_compile", noop_c, "C try compile"),
        ("cxx_try_compile", noop_cxx, "C++ try compile"),
        ("c_try_link", noop_link_c, "C try link"),
        ("cxx_try_link", noop_link_cxx, "C++ try link"),
        ("c_try_run", noop_run, "C try run"),
        ("c_try_cpp", cpp, "C preprocessor"),
    ]:
        text = replace_function(text, name, body, label)

    # 3. ICU 72.1-specific checks.  C11/C++17 compile-check ranges are absent
    #    in this release; C++11 and std::string_view are present.  All present
    #    checks are rewritten to shared triplet facts, preserving flags.
    text = in_range(text,
                    "checking if we have a C11 compiler",
                    "Adding CFLAGS option -std=c11",
                    'if ac_fn_c_try_compile "$LINENO"',
                    'if test ' + C11 + ' = yes',
                    "C11", optional=True)
    text = in_range(text,
                    "checking if we have a C++ compiler",
                    "result: Good",
                    'if ac_fn_cxx_try_compile "$LINENO"',
                    'if test ' + CXX + ' = yes',
                    "C++ compiler")
    text = in_range(text,
                    "checking if we have a C++11 compiler",
                    "Adding CXXFLAGS option -std=c++11",
                    'if ac_fn_cxx_try_compile "$LINENO"',
                    'if test ' + CXX11 + ' = yes',
                    "C++11")
    text = in_range(text,
                    "checking if we have a C++17 compiler",
                    "Adding CXXFLAGS option -std=c++17",
                    'if ac_fn_cxx_try_compile "$LINENO"',
                    'if test ' + CXX17 + ' = yes',
                    "C++17", optional=True)
    string_view_call = ('ac_fn_cxx_check_type "$LINENO" "std::string_view" '
                        '"ac_cv_type_std__string_view" "#include <string_view>\n"\n')
    string_view_fact = ('if test ' + CXX17 + ' = yes; then\n'
                        '  ac_cv_type_std__string_view=yes\n'
                        'else\n'
                        '  ac_cv_type_std__string_view=no\n'
                        'fi\n')
    text = in_range(text,
                    "# Check if C++17 std::string_view is available.",
                    "# Checks for typedefs",
                    string_view_call,
                    string_view_fact,
                    "C++17 std::string_view")
    text = in_range(text,
                    'if test "$CHECK_UTF16_STRING_RESULT" = "unknown"; then',
                    "# Enable/disable extras",
                    'if ac_fn_c_try_compile "$LINENO"',
                    'if test ' + UTF16_C + ' = yes',
                    "UTF-16 C")
    text = in_range(text,
                    'if test "$CHECK_UTF16_STRING_RESULT" = "unknown"; then',
                    "# Enable/disable extras",
                    'if ac_fn_cxx_try_compile "$LINENO"',
                    'if test ' + UTF16_CXX + ' = yes',
                    "UTF-16 C++")
    return text

def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: patch-configure.py CONFIGURE [OUTPUT]")
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    text = open(src, encoding="utf-8", errors="surrogateescape").read()
    out = patch(text)
    open(dst, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print("PATCH_ICU_CONFIGURE_OK " + dst)
    for k, v in facts.items():
        print("  %s=%s" % (k, v))

if __name__ == "__main__":
    main()
