// gcpkg C++ runtime.
//
// Design: this binary is deliberately small. It embeds Lua 5.4 in a restricted
// environment, exposes a handful of OS primitives (process execution, file IO,
// YAML parsing) and then hands control to lua/main.lua. All package-manager
// behaviour -- ports, features, dependency resolution, compile databases --
// lives in Lua so that new build systems / package managers can be integrated
// without recompiling this binary and without patching upstream projects.
#include <lua.hpp>
#include <yaml-cpp/yaml.h>

#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "Process.h"

namespace fs = std::filesystem;

namespace {

struct Context {
    lua_State* L = nullptr;
    std::string exe;
    std::string exeDir;
    std::string share;
    std::vector<std::string> roots;
    std::vector<std::string> args;
    bool verbose = false;
};

char kEnvKey = 0;
char kLoadedKey = 0;

using LuaFn = int (*)(lua_State*);

Context* contextOf(lua_State* L) {
    return static_cast<Context*>(lua_touserdata(L, lua_upvalueindex(1)));
}

void pushEnv(lua_State* L) {
    lua_pushlightuserdata(L, &kEnvKey);
    lua_rawget(L, LUA_REGISTRYINDEX);
}

void pushLoaded(lua_State* L) {
    lua_pushlightuserdata(L, &kLoadedKey);
    lua_rawget(L, LUA_REGISTRYINDEX);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushlightuserdata(L, &kLoadedKey);
        lua_pushvalue(L, -2);
        lua_rawset(L, LUA_REGISTRYINDEX);
    }
}

void reg(lua_State* L, Context* c, const char* name, LuaFn fn) {
    lua_pushlightuserdata(L, c);
    lua_pushcclosure(L, fn, 1);
    lua_setfield(L, -2, name);  // table is just below the closure
}

std::string optStr(lua_State* L, int idx, const char* key, const std::string& def = "") {
    lua_getfield(L, idx, key);
    std::string out = def;
    if (lua_isstring(L, -1)) {
        out = lua_tostring(L, -1);
    }
    lua_pop(L, 1);
    return out;
}

bool optBool(lua_State* L, int idx, const char* key, bool def = false) {
    lua_getfield(L, idx, key);
    bool out = def;
    if (lua_isboolean(L, -1)) {
        out = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);
    return out;
}

gcpkg::ExecOptions parseExec(lua_State* L, bool capture) {
    int idx = lua_absindex(L, 1);
    if (!lua_istable(L, idx)) {
        luaL_error(L, "exec options must be a table");
    }
    gcpkg::ExecOptions o;
    o.capture = capture;

    lua_getfield(L, idx, "cmd");
    if (lua_istable(L, -1)) {
        lua_Integer n = static_cast<lua_Integer>(lua_rawlen(L, -1));
        for (lua_Integer i = 1; i <= n; ++i) {
            lua_rawgeti(L, -1, i);
            o.argv.emplace_back(luaL_checkstring(L, -1));
            lua_pop(L, 1);
        }
    } else if (lua_isstring(L, -1)) {
        // Convenience: a single string means one bare program name.
        o.argv.emplace_back(lua_tostring(L, -1));
    }
    lua_pop(L, 1);

    o.cwd = optStr(L, idx, "cwd");
    o.log = optStr(L, idx, "log");
    o.quiet = optBool(L, idx, "quiet");

    lua_getfield(L, idx, "env");
    if (lua_istable(L, -1)) {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            std::string key = luaL_checkstring(L, -2);
            std::string value = luaL_checkstring(L, -1);
            o.env[key] = value;
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    return o;
}

// ---------------------------------------------------------------- sys.exec --

int l_exec(lua_State* L) {
    Context* c = contextOf(L);
    gcpkg::ExecOptions o = parseExec(L, false);
    if (o.argv.empty()) {
        return luaL_error(L, "exec: empty command");
    }
    if (c->verbose) {
        std::string line = "[gcpkg:cmd]";
        for (const auto& a : o.argv) {
            line += " " + a;
        }
        std::cout << line << std::endl;
    }
    lua_pushinteger(L, gcpkg::execute(o).code);
    return 1;
}

int l_capture(lua_State* L) {
    gcpkg::ExecOptions o = parseExec(L, true);
    gcpkg::ExecResult r = gcpkg::execute(o);
    lua_pushinteger(L, r.code);
    lua_pushlstring(L, r.out.data(), r.out.size());
    return 2;
}

// ---------------------------------------------------------------- filesystem --

int l_now(lua_State* L) {
    using namespace std::chrono;
    double seconds = duration<double>(steady_clock::now().time_since_epoch()).count();
    lua_pushnumber(L, seconds);
    return 1;
}

int l_size(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::error_code ec;
    auto n = fs::file_size(path, ec);
    lua_pushinteger(L, ec ? 0 : static_cast<lua_Integer>(n));
    return 1;
}


int l_read(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        lua_pushnil(L);
        lua_pushfstring(L, "cannot read %s", path.c_str());
        return 2;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    std::string data = ss.str();
    lua_pushlstring(L, data.data(), data.size());
    return 1;
}

int l_write(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) {
        return luaL_error(L, "cannot write %s", path.c_str());
    }
    out.write(data, static_cast<std::streamsize>(len));
    lua_pushboolean(L, 1);
    return 1;
}

int l_append(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    std::ofstream out(path, std::ios::binary | std::ios::app);
    if (!out) {
        return luaL_error(L, "cannot append to %s", path.c_str());
    }
    out.write(data, static_cast<std::streamsize>(len));
    lua_pushboolean(L, 1);
    return 1;
}

int l_mkdir(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    std::error_code ec;
    fs::create_directories(path, ec);
    lua_pushboolean(L, ec ? 0 : 1);
    return 1;
}

int l_isdir(lua_State* L) {
    lua_pushboolean(L, fs::is_directory(luaL_checkstring(L, 1)) ? 1 : 0);
    return 1;
}

int l_isfile(lua_State* L) {
    lua_pushboolean(L, fs::is_regular_file(luaL_checkstring(L, 1)) ? 1 : 0);
    return 1;
}

int l_exists(lua_State* L) {
    lua_pushboolean(L, fs::exists(luaL_checkstring(L, 1)) ? 1 : 0);
    return 1;
}

int l_listdir(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    lua_newtable(L);
    std::error_code ec;
    lua_Integer i = 1;
    for (const auto& entry : fs::directory_iterator(path, ec)) {
        lua_pushstring(L, entry.path().filename().string().c_str());
        lua_rawseti(L, -2, i++);
    }
    return 1;
}

int l_cwd(lua_State* L) {
    lua_pushstring(L, fs::current_path().string().c_str());
    return 1;
}

int l_realpath(lua_State* L) {
    std::string p = luaL_checkstring(L, 1);
    std::error_code ec;
    fs::path r = fs::weakly_canonical(p, ec);
    lua_pushstring(L, (ec ? p : r.string()).c_str());
    return 1;
}

int l_symlink(lua_State* L) {
    std::string target = luaL_checkstring(L, 1);
    std::string link = luaL_checkstring(L, 2);
    std::error_code ec;
    fs::remove(link, ec);
    fs::create_symlink(target, link, ec);
    lua_pushboolean(L, ec ? 0 : 1);
    return 1;
}

int l_getenv(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    const char* value = std::getenv(name);
    if (value) {
        lua_pushstring(L, value);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// ---------------------------------------------------------------- YAML ------

bool isNumeric(const std::string& s, double& out) {
    if (s.empty()) {
        return false;
    }
    char* end = nullptr;
    errno = 0;
    double v = std::strtod(s.c_str(), &end);
    if (end == s.c_str() || *end != '\0' || errno == ERANGE) {
        return false;
    }
    out = v;
    return true;
}

void pushYaml(lua_State* L, const YAML::Node& node) {
    if (!node || node.IsNull()) {
        lua_pushboolean(L, 0);
        return;
    }
    if (node.IsSequence()) {
        lua_newtable(L);
        for (std::size_t i = 0; i < node.size(); ++i) {
            pushYaml(L, node[i]);
            lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
        }
        return;
    }
    if (node.IsMap()) {
        lua_newtable(L);
        for (auto it = node.begin(); it != node.end(); ++it) {
            std::string key = it->first.Scalar();
            lua_pushlstring(L, key.data(), key.size());
            pushYaml(L, it->second);
            lua_rawset(L, -3);
        }
        return;
    }
    std::string s = node.Scalar();
    if (s == "true" || s == "True" || s == "TRUE") {
        lua_pushboolean(L, 1);
    } else if (s == "false" || s == "False" || s == "FALSE") {
        lua_pushboolean(L, 0);
    } else if (s == "null" || s == "~") {
        lua_pushboolean(L, 0);
    } else {
        double number = 0;
        if (node.Tag() != "!!str" && isNumeric(s, number)) {
            lua_pushnumber(L, number);
        } else {
            lua_pushlstring(L, s.data(), s.size());
        }
    }
}

int l_yaml_parse(lua_State* L) {
    std::size_t len = 0;
    const char* text = luaL_checklstring(L, 1, &len);
    try {
        YAML::Node root = YAML::Load(std::string(text, len));
        pushYaml(L, root);
        return 1;
    } catch (const YAML::Exception& e) {
        return luaL_error(L, "YAML parse error: %s", e.what());
    }
}

// ---------------------------------------------------------------- misc ------

int l_arch(lua_State* L) {
#if defined(__x86_64__) || defined(_M_X64)
    lua_pushliteral(L, "x86_64");
#elif defined(__aarch64__) || defined(_M_ARM64)
    lua_pushliteral(L, "aarch64");
#elif defined(__arm__)
    lua_pushliteral(L, "arm");
#elif defined(__i386__)
    lua_pushliteral(L, "i386");
#else
    lua_pushliteral(L, "unknown");
#endif
    return 1;
}

int l_os(lua_State* L) {
#if defined(__APPLE__)
    lua_pushliteral(L, "darwin");
#elif defined(_WIN32)
    lua_pushliteral(L, "windows");
#else
    lua_pushliteral(L, "linux");
#endif
    return 1;
}

int l_nproc(lua_State* L) {
    unsigned int n = std::thread::hardware_concurrency();
    lua_pushinteger(L, n == 0 ? 1 : static_cast<lua_Integer>(n));
    return 1;
}

int l_compiler(lua_State* L) {
    bool cxx = lua_isstring(L, 1) && std::string(lua_tostring(L, 1)) == "cxx";
    const char* envName = cxx ? "CXX" : "CC";
    const char* fallback = cxx ? "c++" : "cc";
    const char* v = std::getenv(envName);
    lua_pushstring(L, (v && *v) ? v : fallback);
    return 1;
}

int l_log(lua_State* L) {
    const char* level = luaL_optstring(L, 1, "info");
    const char* msg = luaL_optstring(L, 2, "");
    FILE* out = std::string(level) == "error" ? stderr : stdout;
    std::fprintf(out, "[gcpkg:%s] %s\n", level, msg);
    // Keep phase lines ordered with child curl/tar output even when stdout is
    // redirected to a file (where C stdio would otherwise be fully buffered).
    std::fflush(out);
    return 0;
}

int l_set_verbose(lua_State* L) {
    contextOf(L)->verbose = lua_toboolean(L, 1) != 0;
    return 0;
}

int l_roots(lua_State* L) {
    Context* c = contextOf(L);
    lua_newtable(L);
    for (std::size_t i = 0; i < c->roots.size(); ++i) {
        lua_pushstring(L, c->roots[i].c_str());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    return 1;
}

int l_add_root(lua_State* L) {
    Context* c = contextOf(L);
    std::string p = luaL_checkstring(L, 1);
    if (std::find(c->roots.begin(), c->roots.end(), p) == c->roots.end()) {
        c->roots.insert(c->roots.begin(), p);
    }
    return 0;
}

int l_share(lua_State* L) {
    lua_pushstring(L, contextOf(L)->share.c_str());
    return 1;
}

int l_lua_root(lua_State* L) {
    lua_pushstring(L, (contextOf(L)->share + "/lua").c_str());
    return 1;
}

int l_exe(lua_State* L) {
    lua_pushstring(L, contextOf(L)->exe.c_str());
    return 1;
}

int l_wrapper_bin(lua_State* L) {
    Context* c = contextOf(L);
    std::vector<std::string> candidates;
    if (const char* env = std::getenv("GCPKG_INTERCEPT_BIN")) {
        candidates.emplace_back(env);
    }
    candidates.push_back(c->exeDir + "/gcpkg-intercept");
    candidates.push_back(std::string(GCPKG_BINARY_ROOT) + "/bin/gcpkg-intercept");
    for (const auto& p : candidates) {
        if (fs::is_regular_file(p)) {
            lua_pushstring(L, p.c_str());
            return 1;
        }
    }
    lua_pushstring(L, candidates.front().c_str());
    return 1;
}

// ---------------------------------------------------------------- loaders ---

// Loads a Lua chunk with the sandbox table as its _ENV, calls it with no
// arguments and leaves exactly one return value on the stack.
bool callChunk(lua_State* L, const std::string& path) {
    if (luaL_loadfile(L, path.c_str()) != LUA_OK) {
        return false;  // error message on top
    }
    pushEnv(L);
    const char* up = lua_setupvalue(L, -2, 1);
    if (!up || std::string(up) != "_ENV") {
        lua_pop(L, 1);
        lua_pushfstring(L, "chunk '%s' has no _ENV upvalue", path.c_str());
        return false;
    }
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
        return false;
    }
    return true;
}

int l_require(lua_State* L) {
    Context* c = contextOf(L);
    std::string name = luaL_checkstring(L, 1);

    pushLoaded(L);  // cache table
    lua_getfield(L, -1, name.c_str());
    if (!lua_isnil(L, -1)) {
        return 1;  // cached module (top of stack)
    }
    lua_pop(L, 2);  // nil + cache

    std::string rel = name;
    std::replace(rel.begin(), rel.end(), '.', '/');

    std::vector<std::string> tried;
    for (const auto& root : c->roots) {
        for (const char* suffix : {".lua", "/init.lua"}) {
            std::string path = root + "/" + rel + suffix;
            tried.push_back(path);
            if (!fs::is_regular_file(path)) {
                continue;
            }
            if (!callChunk(L, path)) {
                return lua_error(L);
            }
            pushLoaded(L);
            lua_pushvalue(L, -2);  // module copy
            lua_setfield(L, -2, name.c_str());
            lua_pop(L, 1);  // cache
            return 1;
        }
    }
    std::string msg = "module '" + name + "' not found. Searched:\n  ";
    for (const auto& p : tried) {
        msg += p + "\n  ";
    }
    return luaL_error(L, "%s", msg.c_str());
}

int l_loadchunk(lua_State* L) {
    std::string path = luaL_checkstring(L, 1);
    if (!callChunk(L, path)) {
        return lua_error(L);
    }
    return 1;
}

// ---------------------------------------------------------------- bootstrap -

void createEnv(lua_State* L, Context* c) {
    lua_newtable(L);
    int e = lua_absindex(L, -1);

    const char* allowed[] = {"assert",  "error",         "ipairs", "pairs",
                            "next",    "select",        "tonumber", "tostring",
                            "type",    "pcall",         "xpcall", "setmetatable",
                            "getmetatable", "rawget",    "rawset", "rawequal",
                            "rawlen",  "table",         "string", "math",
                            "utf8",    "print",         "warn"};
    for (const char* name : allowed) {
        lua_getglobal(L, name);
        lua_setfield(L, e, name);
    }

    // A trimmed-down os library: os.execute / io.* / load* / debug are NOT
    // exposed, so port scripts must go through the audited gcpkg.sys.exec.
    lua_newtable(L);                 // sandbox os
    lua_getglobal(L, "os");          // real os
    const char* osfns[] = {"time", "date", "clock", "difftime", "getenv"};
    for (const char* name : osfns) {
        lua_getfield(L, -1, name);
        lua_setfield(L, -3, name);
    }
    lua_pop(L, 1);  // real os
    lua_setfield(L, e, "os");

    lua_newtable(L);  // package
    lua_newtable(L);  // package.loaded
    lua_setfield(L, -2, "loaded");
    lua_setfield(L, e, "package");

    lua_pushvalue(L, e);
    reg(L, c, "require", l_require);
    lua_pop(L, 1);

    lua_newtable(L);  // gcpkg
    int g = lua_absindex(L, -1);

    lua_newtable(L);  // gcpkg.sys
    reg(L, c, "exec", l_exec);
    reg(L, c, "capture", l_capture);
    reg(L, c, "now", l_now);
    reg(L, c, "size", l_size);
    reg(L, c, "read", l_read);
    reg(L, c, "write", l_write);
    reg(L, c, "append", l_append);
    reg(L, c, "mkdir", l_mkdir);
    reg(L, c, "isdir", l_isdir);
    reg(L, c, "isfile", l_isfile);
    reg(L, c, "exists", l_exists);
    reg(L, c, "listdir", l_listdir);
    reg(L, c, "cwd", l_cwd);
    reg(L, c, "realpath", l_realpath);
    reg(L, c, "symlink", l_symlink);
    reg(L, c, "getenv", l_getenv);
    reg(L, c, "yaml_parse", l_yaml_parse);
    reg(L, c, "arch", l_arch);
    reg(L, c, "os", l_os);
    reg(L, c, "nproc", l_nproc);
    reg(L, c, "compiler", l_compiler);
    reg(L, c, "log", l_log);
    reg(L, c, "set_verbose", l_set_verbose);
    reg(L, c, "roots", l_roots);
    reg(L, c, "add_root", l_add_root);
    reg(L, c, "share", l_share);
    reg(L, c, "lua_root", l_lua_root);
    reg(L, c, "exe", l_exe);
    reg(L, c, "wrapper_bin", l_wrapper_bin);
    reg(L, c, "loadchunk", l_loadchunk);
    lua_setfield(L, g, "sys");

    lua_newtable(L);  // gcpkg.args
    for (std::size_t i = 0; i < c->args.size(); ++i) {
        lua_pushstring(L, c->args[i].c_str());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    lua_setfield(L, g, "args");

    lua_pushstring(L, c->exe.c_str());
    lua_setfield(L, g, "exe");
    lua_pushstring(L, c->share.c_str());
    lua_setfield(L, g, "share");
    lua_pushliteral(L, "0.2.0");
    lua_setfield(L, g, "version");

    lua_setfield(L, e, "gcpkg");

    lua_pushvalue(L, e);
    lua_setfield(L, e, "_G");

    lua_pushlightuserdata(L, &kEnvKey);
    lua_pushvalue(L, e);
    lua_rawset(L, LUA_REGISTRYINDEX);
    // leave E on the stack; caller pops it
}

std::string findShare(const std::string& exe) {
    std::vector<std::string> candidates;
    if (const char* env = std::getenv("GCPKG_SHARE")) {
        candidates.emplace_back(env);
    }
    fs::path exeDir = fs::path(exe).parent_path();
    candidates.push_back((exeDir / ".." / "share" / "gcpkg").lexically_normal().string());
    candidates.push_back((exeDir / ".." / "..").lexically_normal().string());
    candidates.push_back(GCPKG_SOURCE_ROOT);
    candidates.push_back(fs::current_path().string());
    for (const auto& p : candidates) {
        if (fs::is_regular_file(fs::path(p) / "lua" / "main.lua")) {
            return fs::weakly_canonical(p).string();
        }
    }
    return candidates.back();
}

std::vector<std::string> initialRoots(const std::string& share) {
    std::vector<std::string> roots;
    if (const char* env = std::getenv("GCPKG_LUA_PATH")) {
        std::string s(env);
        std::size_t start = 0;
        while (start <= s.size()) {
            std::size_t pos = s.find(':', start);
            std::string part = s.substr(start, pos == std::string::npos ? std::string::npos : pos - start);
            if (!part.empty()) {
                roots.push_back(part);
            }
            if (pos == std::string::npos) {
                break;
            }
            start = pos + 1;
        }
    }
    roots.push_back(share + "/lua");
    roots.push_back(fs::current_path().string() + "/lua");
    roots.push_back(fs::current_path().string() + "/.gcpkg/lua");
    return roots;
}

void printLuaError(lua_State* L) {
    const char* msg = lua_tostring(L, -1);
    std::fprintf(stderr, "[gcpkg:error] %s\n", msg ? msg : "(unknown Lua error)");
}

}  // namespace

int gcpkg_main(int argc, char** argv) {
    std::string exe = argv[0];
    if (exe.find('/') == std::string::npos) {
        char buf[4096];
        ssize_t n = ::readlink("/proc/self/exe", buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            exe = buf;
        }
    }
    // Absolute paths matter: CC/CXX wrapper symlinks are resolved from a
    // different working directory than the one gcpkg was launched from.
    exe = fs::weakly_canonical(exe).string();

    lua_State* L = luaL_newstate();
    if (!L) {
        std::fprintf(stderr, "gcpkg: cannot create Lua state\n");
        return 2;
    }
    luaL_openlibs(L);

    Context c;
    c.L = L;
    c.exe = exe;
    c.exeDir = fs::path(exe).parent_path().string();
    c.share = findShare(exe);
    c.roots = initialRoots(c.share);
    c.verbose = std::getenv("GCPKG_VERBOSE") != nullptr;
    for (int i = 1; i < argc; ++i) {
        c.args.emplace_back(argv[i]);
    }

    createEnv(L, &c);
    lua_pop(L, 1);  // sandbox E

    std::string mainPath = c.share + "/lua/main.lua";
    if (!fs::is_regular_file(mainPath)) {
        std::fprintf(stderr, "gcpkg: Lua engine not found at %s (set GCPKG_SHARE)\n", mainPath.c_str());
        lua_close(L);
        return 2;
    }
    if (!callChunk(L, mainPath)) {
        printLuaError(L);
        lua_close(L);
        return 2;
    }
    lua_getfield(L, -1, "run");
    if (!lua_isfunction(L, -1)) {
        std::fprintf(stderr, "gcpkg: lua/main.lua must return a table with run(args)\n");
        lua_close(L);
        return 2;
    }
    lua_newtable(L);
    for (std::size_t i = 0; i < c.args.size(); ++i) {
        lua_pushstring(L, c.args[i].c_str());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    int rc = 0;
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        printLuaError(L);
        rc = 1;
    } else {
        rc = lua_isinteger(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 0;
    }
    lua_close(L);
    return rc;
}
