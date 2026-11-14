-- mosquitto 2.0.20 -- gcpkg port definition.
-- MQTT client library; `tls` feature enables OpenSSL.

local recipe = require("gcpkg.recipe")

return recipe.cmake {
    name = "mosquitto",
    version = "2.0.20",
    license = "EPL-2.0",
    homepage = "https://mosquitto.org",
    description = "MQTT client/broker library",
    source = {
        url = "https://codeload.github.com/eclipse-mosquitto/mosquitto/tar.gz/refs/tags/v2.0.20",
        sha256 = "851fb4b5bf5e2ddc4c341efcfe24c877fcb3a4356c79838103a44751c5731f6a",
        strip = 1,
    },
    dependencies = {},
    cmake = {
        defines = {
          BUILD_TESTING = "OFF",
          WITH_TLS = "OFF",
          WITH_TLS_PSK = "OFF",
          WITH_CJSON = "OFF",
          WITH_BROKER = "OFF",
          WITH_CLIENTS = "OFF",
          WITH_APPS = "OFF",
          WITH_PLUGINS = "OFF",
          WITH_SRV = "OFF",
          DOCUMENTATION = "OFF",
          WITH_STATIC_LIBRARIES = "ON",
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
        "mosquitto",
      },
      binaries = {},
    },
}
