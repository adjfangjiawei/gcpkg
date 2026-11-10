-- sentencepiece 0.2.0 -- gcpkg port definition.
-- SentencePiece tokenizer; bundled protobuf-lite/absl, tests off; ctx.jobs scales the memory-heavy trainer TUs.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "sentencepiece",
    version = "0.2.0",
    license = "Apache-2.0",
    homepage = "https://github.com/google/sentencepiece",
    description = "Unsupervised text tokenizer for neural networks",
    source = {
        url = "https://codeload.github.com/google/sentencepiece/tar.gz/refs/tags/v0.2.0",
        sha256 = "9970f0a0afee1648890293321665e5b2efa04eaec9f1671fcf8048f456f5bb86",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          SPM_BUILD_TEST = "OFF",
          SPM_ENABLE_SHARED = "OFF",
          SPM_ENABLE_TCMALLOC = "OFF",
          SPM_PROTOBUF_PROVIDER = "internal",
          SPM_ABSL_PROVIDER = "internal",
          SPM_ENABLE_NFKC_COMPILE = "OFF",
        },
        args = {},
    },
    exports = {
      includes = {
        "@PREFIX@/include",
      },
      libdirs = {
        "@LIBDIR@",
      },
      libs = {
        "sentencepiece",
      },
      binaries = {
        "@PREFIX@/bin",
      },
    },
}
