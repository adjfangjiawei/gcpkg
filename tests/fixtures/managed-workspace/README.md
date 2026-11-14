# Managed-workspace fixtures

- `static/workspace.yaml` describes a small three-repository dependency tree for
  offline graph and configuration checks.
- `static/repos/app/conanfile.txt` is the Conan marker; `canonfile` is the
  compatibility alias marker.
- `project/gcpkg.yaml` is a YAML-only project with `system`, `conan_cmd`,
  `canon_cmd` and `commands` fields.
- `dynamic.sh` builds local Git origins, recursive submodules, a local port and
  several inner build-system combinations without network access. Its local
  Conan stand-in reads both `CONAN_*` and legacy `CANON_*` variables.
