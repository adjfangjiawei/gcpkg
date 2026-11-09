-- parallel-hashmap v1.4.1 -- gcpkg port definition.
-- Header-only parallel hash maps and btrees.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "parallel-hashmap",
    version = "v1.4.1",
    license = "Apache-2.0",
    homepage = "https://github.com/greg7mdp/parallel-hashmap",
    description = "Header-only concurrent hash maps and btrees",
    source = {
        url = "https://codeload.github.com/greg7mdp/parallel-hashmap/tar.gz/refs/tags/v1.4.1",
        sha256 = "949874f4207b8735422438b23b884fb1f4b926689bb5eebff38cc4d357d09cd2",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "parallel_hashmap", dst = "parallel_hashmap" },
          },
        include = "parallel_hashmap/phmap.h",
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
