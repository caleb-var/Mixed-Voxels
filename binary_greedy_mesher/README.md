# Flecs Extension

This directory provides a Godot GDExtension integrating the [Flecs](https://flecs.dev) entity component system.

## Layout

- `SConstruct` – build script for the extension.
- `src/` – core extension sources (`register_types.*`, `flecs_gd.*`).
- `modules/` – Flecs modules compiled as shared libraries.
  - `world/` – example world module exposing components and systems.
- `../deps/` – third‑party dependencies such as `flecs.c` and `tiny_bvh.h`.

## Building

From this directory run:

```bash
scons build_library=no
```

Before building the extension make sure `deps/godot-cpp` is built:

```bash
cd ../deps/godot-cpp
scons custom_api_file=../extension_api.json
```

