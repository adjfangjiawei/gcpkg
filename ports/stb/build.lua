-- stb 4e9b368 -- gcpkg port definition.
-- Selected stb single-file C headers; probe is compiled as C11.

local recipe = require("gcpkg.recipe")

return recipe.header {
    name = "stb",
    version = "4e9b368",
    license = "MIT",
    homepage = "https://github.com/nothings/stb",
    description = "stb single-file public-domain C/C++ headers",
    source = {
        url = "https://codeload.github.com/nothings/stb/tar.gz/4e9b368bfc071e97206ea5c6adba68dd0cbf8897",
        sha256 = "e60706ab084e0cae35ee7282deb4a7f283e4a28be1896d097437205da01a0683",
        strip = 1,
    },
    dependencies = {},
    header = {
        headers = {
            { src = "stb_image.h", dst = "stb_image.h" },
            { src = "stb_image_write.h", dst = "stb_image_write.h" },
            { src = "stb_truetype.h", dst = "stb_truetype.h" },
            { src = "stb_rect_pack.h", dst = "stb_rect_pack.h" },
            { src = "stb_textedit.h", dst = "stb_textedit.h" },
            { src = "stb_ds.h", dst = "stb_ds.h" },
            { src = "stb_perlin.h", dst = "stb_perlin.h" },
          },
        include = "stb_image.h",
        flags = {
            "-std=c11",
          },
        license_files = {
            "LICENSE",
          },
        cxx = false,
    },
    exports = {
      includes = { "@PREFIX@/include" },
      libdirs = { "@LIBDIR@" },
      libs = {},
      binaries = {},
    },
}
