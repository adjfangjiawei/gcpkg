-- jsoncons 1.10.0 -- gcpkg port definition.
-- Header-only JSON, JSON Pointer, JSON Patch and CBOR library.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "jsoncons",
    version = "1.10.0",
    license = "BSL-1.0",
    homepage = "https://github.com/danielaparker/jsoncons",
    description = "Header-only JSON, JSON Pointer, JSON Patch and CBOR library",
    source = {
        url = "https://codeload.github.com/danielaparker/jsoncons/tar.gz/refs/tags/v1.10.0",
        sha256 = "c829350a2eece662beb378143e2ab1c1cbb07d703687bf168626665a8a7d8bc1",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "include/jsoncons", dst = "jsoncons" },
          },
        include = "jsoncons/json.hpp",
        flags = {
            "-std=c++17",
          },
        license_files = {
            "LICENSE",
          },
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
