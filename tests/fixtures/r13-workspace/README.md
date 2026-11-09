# R13 workspace fixtures

- `static/workspace.yaml` is parsed by `tests/r13.sh` to verify topological
  order, inferred `gcpkg.yaml` edges, and cycle rejection without network.
- `static/repos/app/canonfile` preserves the user's original `canon` name.
- `project/gcpkg.yaml` is a YAML-only project used to verify that
  `gcpkg add/remove` keeps `system`, `canon_cmd`, and `commands`.
- `dynamic.sh` creates local Git origins, recursive submodules, a local port,
  and five inner build-system combinations from scratch.
