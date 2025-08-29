extends Node3D

## Basic clipmap-based LOD terrain generator.
##
## Chunks are generated in concentric rings around a player position.
## Each subsequent ring doubles the voxel size (`1, 2, 4, 8, ...`),
## allowing an arbitrary number of LOD tiers. Rings only shift when the
## player crosses a chunk boundary. Border voxels are duplicated to
## create skirts that hide cracks between neighbouring LOD meshes.

@export var player_path: NodePath
## Number of chunks to generate around the player for each LOD ring.
@export var chunk_radius: int = 2
## Total number of LOD levels. Add as many as desired.
@export var lod_count: int = 4
## Extra range before removing far chunks to reduce popping.
@export var hysteresis_margin: float = 0.2
## Chunk dimensions per LOD (in voxels).
## Supply one size per LOD; the last value is reused if more levels are requested.
@export var lod_chunk_dims: PackedInt32Array = [32, 64, 64, 64]

## Debug visualisations.
@export var show_chunk_bounds: bool = false
@export var show_wireframe: bool = false

@onready var player: Node3D = get_node_or_null(player_path)

var noise := FastNoiseLite.new()

var _wire_shader := Shader.new()
var _voxel_wire_material := ShaderMaterial.new()
var _bounds_material := ShaderMaterial.new()

## Per‑LOD dictionaries of existing chunks.
var chunks: Array = []
## Last observed chunk-space centre for each LOD. Used to detect when
## to shift clipmap rings.
var last_centers: Array = []

## Background mesh builder provided by the C++ extension.
var _mesher := BinaryGreedyMesher.new()

## Limit how many finished meshes are swapped per frame.
@export var rebuild_frame_budget: int = 4

## Holds voxel data and mesh instance for a single chunk.
class ChunkData:
    ## Voxel materials stored as uint8 values (0 = empty, 1..255 = material id).
    var materials: PackedByteArray
    ## Rendered mesh instance placed in the scene.
    var mesh: MeshInstance3D
    ## Optional mesh outlining the chunk bounds.
    var bounds: MeshInstance3D

func _ready() -> void:
    _wire_shader.code = "shader_type spatial; render_mode unshaded, wireframe;"
    _voxel_wire_material.shader = _wire_shader
    _bounds_material.shader = _wire_shader
    _bounds_material.set_shader_parameter("albedo", Color.RED)

    noise.seed = randi()
    # Prepare per‑LOD dictionaries and sentinel centres.
    for i in range(lod_count):
        chunks.append({})
        last_centers.append(Vector3i(1_000_000, 1_000_000, 1_000_000))

    # Initial generation around the player.
    _update_chunks(true)

func _process(_delta: float) -> void:
    _update_chunks()
    _apply_completed_jobs()

func _update_chunks(force: bool = false) -> void:
    if player == null:
        return

    var player_pos: Vector3 = player.global_transform.origin

    for lod in range(lod_count):
        var voxel_scale := 1 << lod               # 1×, 2×, 4×, 8× ...
        var dim := lod_chunk_dims[min(lod, lod_chunk_dims.size() - 1)]
        var world_size := dim * voxel_scale       # Chunk size in world units

        var center := Vector3i(
            int(floor(player_pos.x / world_size)),
            int(floor(player_pos.y / world_size)),
            int(floor(player_pos.z / world_size))
        )

        var lod_chunks: Dictionary = chunks[lod]

        if force or center != last_centers[lod]:
            var wanted := {}

            # Ensure all chunks in the visible cube exist.
            for x in range(center.x - chunk_radius, center.x + chunk_radius + 1):
                for y in range(center.y - chunk_radius, center.y + chunk_radius + 1):
                    for z in range(center.z - chunk_radius, center.z + chunk_radius + 1):
                        var key := Vector3i(x, y, z)
                        wanted[key] = true
                        if not lod_chunks.has(key):
                            lod_chunks[key] = _create_chunk(key, dim, voxel_scale, lod)

            # Remove chunks that moved outside the cube with hysteresis margin.
            var remove_radius := int(ceil(chunk_radius * (1.0 + hysteresis_margin)))
            for k in lod_chunks.keys():
                var dx := abs(k.x - center.x)
                var dy := abs(k.y - center.y)
                var dz := abs(k.z - center.z)
                if dx > remove_radius or dy > remove_radius or dz > remove_radius:
                    lod_chunks[k].mesh.queue_free()
                    if lod_chunks[k].bounds:
                        lod_chunks[k].bounds.queue_free()
                    lod_chunks.erase(k)

            chunks[lod] = lod_chunks
            last_centers[lod] = center

func _apply_completed_jobs() -> void:
    var processed := 0
    while processed < rebuild_frame_budget:
        var res = _mesher.pop_completed()
        if res.is_empty():
            break
        if res.has("chunk") and res.has("mesh") and is_instance_valid(res.chunk.mesh):
            res.chunk.mesh.mesh = res.mesh
        processed += 1

func _schedule_job(vox: PackedByteArray, size: Vector3i, scale: int, chunk: ChunkData) -> void:
    _mesher.schedule_mesh(vox, size, scale, chunk)

func _exit_tree() -> void:
    _mesher.stop()

func _make_bounds_mesh(size: Vector3) -> Mesh:
    var m := ImmediateMesh.new()
    m.surface_begin(Mesh.PRIMITIVE_LINES)
    var x := size.x
    var y := size.y
    var z := size.z
    var pts := [
        Vector3(0, 0, 0), Vector3(x, 0, 0),
        Vector3(x, 0, 0), Vector3(x, y, 0),
        Vector3(x, y, 0), Vector3(0, y, 0),
        Vector3(0, y, 0), Vector3(0, 0, 0),
        Vector3(0, 0, z), Vector3(x, 0, z),
        Vector3(x, 0, z), Vector3(x, y, z),
        Vector3(x, y, z), Vector3(0, y, z),
        Vector3(0, y, z), Vector3(0, 0, z),
        Vector3(0, 0, 0), Vector3(0, 0, z),
        Vector3(x, 0, 0), Vector3(x, 0, z),
        Vector3(x, y, 0), Vector3(x, y, z),
        Vector3(0, y, 0), Vector3(0, y, z)
    ]
    for p in pts:
        m.surface_add_vertex(p)
    m.surface_end()
    return m

func _create_chunk(coord: Vector3i, dim: int, voxel_scale: int, lod: int) -> ChunkData:
    # Duplicate border voxels to create skirts that hide seams.
    var side := dim + 1
    var vox := PackedByteArray()
    vox.resize(side * side * side)

    # Fill voxel buffer with basic heightmap data.
    for z in range(side):
        for y in range(side):
            for x in range(side):
                var gx := coord.x * dim + x
                var gy := coord.y * dim + y
                var gz := coord.z * dim + z
                var world_x := gx * voxel_scale
                var world_y := gy * voxel_scale
                var world_z := gz * voxel_scale
                var height := noise.get_noise_2d(world_x, world_z) * 8.0 + 16.0
                var idx := x + side * (y + side * z)
                vox[idx] = world_y < height ? 1 : 0

    var inst := MeshInstance3D.new()
    if show_wireframe:
        inst.material_override = _voxel_wire_material
    inst.position = Vector3(
        coord.x * dim * voxel_scale,
        coord.y * dim * voxel_scale,
        coord.z * dim * voxel_scale
    )
    add_child(inst)

    var bounds_inst: MeshInstance3D = null
    if show_chunk_bounds:
        var world_size := Vector3(dim * voxel_scale, dim * voxel_scale, dim * voxel_scale)
        bounds_inst = MeshInstance3D.new()
        bounds_inst.mesh = _make_bounds_mesh(world_size)
        bounds_inst.position = inst.position
        bounds_inst.material_override = _bounds_material
        add_child(bounds_inst)

    var data := ChunkData.new()
    data.materials = vox
    data.mesh = inst
    data.bounds = bounds_inst
    _schedule_job(vox, Vector3i(side, side, side), voxel_scale, data)
    return data

