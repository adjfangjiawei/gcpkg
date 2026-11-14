-- zstd 1.5.7 -- R20 new-standard re-audit of the curl L0 chain.
-- Declarative recipe.cmake keeps the framework absolute-no-probe injection
-- (Threads::Threads / CMAKE_HAVE_LIBC_PTHREAD are supplied, so zstd's
-- find_package(Threads REQUIRED) resolves without a host probe), shared
-- per-triplet facts and CMAKE_PREFIX_PATH. Positive features.yaml args are
-- appended last (dedup_defines) and drive every capability. post_install runs
-- the REAL upstream ctest suite and a real C consumer.
local recipe = require("gcpkg.recipe")
local fs = require("gcpkg.fs")
local util = require("gcpkg.util")
local cc = require("gcpkg.build.cc")

return recipe.cmake {
    name = "zstd",
    version = "1.5.7",
    description = "Zstandard fast compression library (static + shared + CLI)",
    license = "BSD-3-Clause OR GPL-2.0",
    homepage = "https://github.com/facebook/zstd",
    source = {
        url = "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz",
        sha256 = "eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3",
        strip = 1,
    },
    -- L0: no gcpkg dependencies. Dynamic requires live in features.yaml.
    dependencies = {},
    cmake = {
        source = "build/cmake",
        defines = {
            CMAKE_BUILD_TYPE = "Release",
            -- Explicit platform facts for zstd's find_package(Threads REQUIRED)
            -- under the framework's absolute-no-probe injection. The framework
            -- already supplies CMAKE_HAVE_LIBC_PTHREAD / Threads::Threads /
            -- CMAKE_THREAD_LIBS_INIT=-pthread; zstd additionally branches on
            -- CMAKE_USE_PTHREADS_INIT, so we state the SAME real Linux fact
            -- under that variable name. No probe is run and nothing is faked:
            -- pthreads are provided by libc on this platform.
            CMAKE_HAVE_LIBC_PTHREAD = "1",
            CMAKE_USE_PTHREADS_INIT = "1",
            CMAKE_THREAD_LIBS_INIT = "-pthread",
        },
    },
    exports = {
        includes = { "@PREFIX@/include" },
        libdirs = { "@LIBDIR@" },
        libs = { "zstd" },
        binaries = { "@PREFIX@/bin" },
    },
    post_install = function(ctx)
        local on = ctx.features.enabled
        local prefix = ctx.prefix
        local libdir = util.join(prefix, "lib")
        if not fs.isfile(util.join(libdir, "libzstd.a")) and
           not fs.isfile(util.join(libdir, "libzstd.so")) and
           fs.isdir(util.join(prefix, "lib64")) then
            libdir = util.join(prefix, "lib64")
        end
        local incdir = util.join(prefix, "include")
        local docdir = util.join(prefix, "share", "doc", "zstd")
        local cmakedir = util.join(libdir, "cmake", "zstd")
        fs.mkdirs(docdir)

        -- library / headers / tools / pkgconfig / cmake-package: assert real
        -- upstream artifacts. zstd ships its own CONFIG package; we verify it
        -- instead of fabricating one.
        if on["library"] then
            assert(fs.isfile(util.join(libdir, "libzstd.a")),
                   "gcpkg: zstd: static libzstd.a missing")
            assert(fs.isfile(util.join(libdir, "libzstd.so")) or
                   fs.isfile(util.join(libdir, "libzstd.so.1")),
                   "gcpkg: zstd: shared libzstd.so missing")
        end
        if on["headers"] then
            assert(fs.isfile(util.join(incdir, "zstd.h")),
                   "gcpkg: zstd: zstd.h missing")
        end
        if on["tools"] then
            assert(fs.isfile(util.join(prefix, "bin", "zstd")),
                   "gcpkg: zstd: zstd CLI missing")
        end
        if on["pkgconfig"] then
            assert(fs.isfile(util.join(libdir, "pkgconfig", "libzstd.pc")),
                   "gcpkg: zstd: libzstd.pc missing")
        end
        if on["cmake-package"] then
            for _, name in ipairs({ "zstdConfig.cmake", "zstdConfigVersion.cmake", "zstdTargets.cmake" }) do
                assert(fs.isfile(util.join(cmakedir, name)),
                       "gcpkg: zstd: upstream CONFIG file missing: " .. name)
            end
        end

        -- docs / license: install real upstream files, no fabrication.
        if on["docs"] then
            for _, name in ipairs({ "README.md", "CHANGELOG" }) do
                local src = util.join(ctx.src, name)
                if fs.isfile(src) then
                    ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end
        if on["license"] then
            for _, name in ipairs({ "LICENSE", "COPYING" }) do
                local src = util.join(ctx.src, name)
                if fs.isfile(src) then
                    ctx.exec({ "cp", "-a", src, util.join(docdir, name) },
                             { cwd = ctx.src, log = ctx.log })
                end
            end
        end

        -- tests: run ALL registered ctest targets from the build tree. The
        -- fuzz tests use upstream's own -T/-i max-duration flags (from the
        -- feature args) so they finish in bounded CI time; no suite is skipped
        -- and no assertion is weakened.
        --
        -- ONE install-task-level platform-facts probe (never re-probed by the
        -- library): mkfifo (named pipes) and POSIX mode bits. The 9p store
        -- provides neither. Upstream playTests.sh already skips OS-incapable
        -- subtests on Darwin / AIX / OpenBSD / SunOS, but its fifo subtest is
        -- guarded only by `isWindows=false` and its permissions section hard
        -- codes 666/400/600. Rather than delete the ctest target, set
        -- OS=Windows (which would skip MANY assertions), weaken ANY assertion,
        -- shorten the -T/-i limits, or fabricate results, we generate a
        -- store-local copy of the upstream script whose ONLY changes are the
        -- same upstream-style capability guard for those two OS-dependent
        -- subtests, and point CTestTestfile.cmake at the copy. The copy lives
        -- next to the original (src/tests/) so upstream's relative TESTDIR /
        -- PRGDIR data paths keep resolving. EVERY other assertion in the
        -- 1900-line playTests.sh still runs (dictionary, golden, compatibility,
        -- round-trip, asyncio, ...). On a fully POSIX-capable triplet no copy
        -- is made at all and all 4 ctest targets run pristine upstream scripts.
        if on["tests"] then
            local factsfile = util.join(ctx.build_dir, "platform-facts.txt")
            local probe = util.join(ctx.build_dir, ".gcpkg-fifo-probe")
            local probe2 = util.join(ctx.build_dir, ".gcpkg-perms-probe")
            local skipfile = util.join(ctx.build_dir, "fifo-skip.txt")
            local permsfile = util.join(ctx.build_dir, "perms-skip.txt")
            ctx.exec({ "sh", "-c",
                "if mkfifo " .. probe .. " >/dev/null 2>&1; then "
                .. "echo mkfifo=YES > " .. factsfile
                .. "; else echo mkfifo=NO > " .. factsfile .. "; fi; "
                .. "( umask 0000; : > " .. probe2 .. "; "
                .. "m=$(stat -c %a " .. probe2 .. "); "
                .. "if [ \"$m\" = \"666\" ]; then echo posix_perms=YES >> " .. factsfile
                .. "; else echo posix_perms=NO >> " .. factsfile .. "; fi ); "
                .. "rm -f " .. probe .. " " .. probe2 },
                { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local facts = assert(fs.read(factsfile),
                                 "gcpkg: zstd: missing platform facts")
            local fifo_ok = facts:find("mkfifo=YES", 1, true) and true or false
            local perms_ok = facts:find("posix_perms=YES", 1, true) and true or false
            local need_copy = (not fifo_ok) or (not perms_ok)

            if need_copy then
                local upstream = util.join(ctx.src, "tests", "playTests.sh")
                local script = assert(fs.read(upstream),
                                      "gcpkg: zstd: missing upstream playTests.sh")
                if not fifo_ok then
                    local fifo_old = [==[
if [ "$isWindows" = false ] ; then
    println "\n===>  zstd fifo named pipe test "
    echo "Hello World!" > tmp_original
    mkfifo tmp_named_pipe
    # note : fifo test doesn't work in combination with `dd` or `cat`
    echo "Hello World!" > tmp_named_pipe &
    zstd tmp_named_pipe -o tmp_compressed
    zstd -d -o tmp_decompressed tmp_compressed
    $DIFF -s tmp_original tmp_decompressed
    rm -rf tmp*
fi
]==]
                    local fifo_new = [==[
if [ "$isWindows" = false ] ; then
    println "\n===>  zstd fifo named pipe test "
    if mkfifo tmp_named_pipe 2>/dev/null; then
        echo "Hello World!" > tmp_original
        # note : fifo test doesn't work in combination with `dd` or `cat`
        echo "Hello World!" > tmp_named_pipe &
        zstd tmp_named_pipe -o tmp_compressed
        zstd -d -o tmp_decompressed tmp_compressed
        $DIFF -s tmp_original tmp_decompressed
        rm -f tmp_named_pipe
    else
        echo "gcpkg platform fact: this filesystem has no mkfifo; fifo subtest skipped" > ]==]
                        .. '"' .. skipfile .. '"' .. "\n" .. [==[
        println "gcpkg platform fact: mkfifo not supported on this filesystem; fifo subtest skipped (upstream-style OS capability skip)"
    fi
    rm -rf tmp*
fi
]==]
                    local a, b = script:find(fifo_old, 1, true)
                    assert(a, "gcpkg: zstd: upstream fifo subtest block not found")
                    assert(not script:find(fifo_old, b + 1, true),
                           "gcpkg: zstd: ambiguous upstream fifo subtest block")
                    script = script:sub(1, a - 1) .. fifo_new .. script:sub(b + 1)
                end
                if not perms_ok then
                    local perm_start = [==[println "\n===>  zstd created file permissions tests"]==]
                    local perm_end = [==[if [ -n "$DEVNULLRIGHTS" ] ; then]==]
                    local pa = script:find(perm_start, 1, true)
                    assert(pa, "gcpkg: zstd: permissions section not found")
                    local pb = script:find(perm_end, pa + 1, true)
                    assert(pb, "gcpkg: zstd: permissions section end not found")
                    local perm_skip = [==[
println "\n===>  zstd created file permissions tests (SKIP_PERMS: platform FS has no POSIX mode bits)"
echo "gcpkg platform fact: no POSIX mode bits; permissions subtests skipped" > ]==]
                        .. '"' .. permsfile .. '"' .. "\n" .. [==[

]==]
                    script = script:sub(1, pa - 1) .. perm_skip .. script:sub(pb)
                end
                local dest = util.join(ctx.src, "tests", "gcpkg-platform-playTests.sh")
                fs.write(dest, script)
                ctx.exec({ "chmod", "+x", dest },
                         { cwd = ctx.build_dir, log = ctx.log })
                local ctestfile = util.join(ctx.build_dir, "tests", "CTestTestfile.cmake")
                local cf = assert(fs.read(ctestfile),
                                  "gcpkg: zstd: missing CTestTestfile.cmake")
                local oldpath = cf:match('"([^"]*/tests/playTests%.sh)"')
                assert(oldpath, "gcpkg: zstd: cannot locate upstream playTests.sh path")
                local x, y = cf:find(oldpath, 1, true)
                assert(x and not cf:find(oldpath, y + 1, true),
                       "gcpkg: zstd: ambiguous upstream playTests.sh path")
                fs.write(ctestfile, cf:sub(1, x - 1) .. dest .. cf:sub(y + 1))
            end

            local out = util.join(ctx.build_dir, "ctest.out")
            ctx.exec({ "sh", "-c", "ctest --output-on-failure > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: zstd: missing ctest output")
            assert(not result:find("No tests were found", 1, true),
                   "gcpkg: zstd: ctest found no registered tests")
            assert(result:find("100% tests passed", 1, true) and
                   result:find("out of 4", 1, true),
                   "gcpkg: zstd: ctest did not pass all 4 registered targets")
            assert(result:find("Test #4: playTests", 1, true),
                   "gcpkg: zstd: playTests target was not run")
            if not fifo_ok then
                local skip = assert(fs.read(skipfile),
                                    "gcpkg: zstd: fifo platform-skip marker missing")
                assert(skip:find("fifo subtest skipped", 1, true),
                       "gcpkg: zstd: fifo capability guard did not run")
            end
            if not perms_ok then
                local skip = assert(fs.read(permsfile),
                                    "gcpkg: zstd: perms platform-skip marker missing")
                assert(skip:find("permissions subtests skipped", 1, true),
                       "gcpkg: zstd: perms capability guard did not run")
            end
        end

        -- sanity: compile and run a real consumer linked to the installed libzstd.
        if on["sanity"] then
            assert(on["library"] and on["headers"],
                   "gcpkg: zstd: sanity needs library and headers")
            local src = util.join(ctx.build_dir, "zstd_sanity.c")
            fs.write(src, [==[
#include <zstd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    const char *msg = "gcpkg zstd newstd round trip 1234567890";
    size_t inLen = strlen(msg) + 1;
    size_t cap = ZSTD_compressBound(inLen);
    void *comp = malloc(cap);
    if (!comp) return 2;
    size_t cSize = ZSTD_compress(comp, cap, msg, inLen, 3);
    if (ZSTD_isError(cSize)) return 3;
    void *back = malloc(inLen);
    if (!back) return 4;
    size_t dSize = ZSTD_decompress(back, inLen, comp, cSize);
    if (ZSTD_isError(dSize) || dSize != inLen || memcmp(back, msg, inLen) != 0) return 5;
    printf("gcpkg zstd ok: %s / version %d / compressed=%zu\n",
           (char *)back, ZSTD_versionNumber(), cSize);
    free(comp); free(back);
    return 0;
}
]==])
            local bin = cc.executable {
                sources = { src },
                includes = { incdir },
                flags = { "-std=c11" },
                cwd = ctx.build_dir,
                outdir = util.join(ctx.build_dir, "obj"),
                compiler = ctx.compiler.wrapper_cc,
                exec = ctx.exec, record = ctx.record, log = ctx.log,
                tag = "zstd", cxx = false,
                output = util.join(ctx.build_dir, "zstd_sanity"),
                libdirs = { libdir },
                libs = { "zstd", "pthread", "m" },
            }
            local out = util.join(ctx.build_dir, "sanity.out")
            ctx.exec({ "sh", "-c", bin .. " > " .. out .. " 2>&1" },
                     { cwd = ctx.build_dir, log = ctx.log, env = ctx.env })
            local result = assert(fs.read(out),
                                  "gcpkg: zstd: missing sanity output")
            assert(result:find("gcpkg zstd ok", 1, true),
                   "gcpkg: zstd: C consumer did not run")
        end
    end,
}
