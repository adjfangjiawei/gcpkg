-- D-Bus message bus library
-- gcpkg port definition.
local recipe = require("gcpkg.recipe")

return recipe.meson {
    name = "dbus",
    version = "1.16.2",
    description = "D-Bus message bus library",
    license = "AFL-2.1/GPL-2.0",
    homepage = "https://dbus.freedesktop.org",
    source = {
        url = "https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz",
        sha256 = "0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2",
        strip = 1,
    },
    dependencies = { "expat" },
    meson = {
        options = {
          modular_tests = "disabled",
          intrusive_tests = "false",
          installed_tests = "false",
          doxygen_docs = "disabled",
          xml_docs = "disabled",
          traditional_activation = "false",
          user_session = "false",
          systemd = "disabled",
          selinux = "disabled",
          apparmor = "disabled",
          libaudit = "disabled",
          x11_autolaunch = "disabled"
        },
        auto_features = "disabled",
    },
    exports = {
      includes = { "@PREFIX@/include/dbus-1.0", "@LIBDIR@/dbus-1.0/include" },
      libdirs = { "@LIBDIR@" },
      libs = { "dbus-1" },
      binaries = { "@PREFIX@/bin" }
    },
}
