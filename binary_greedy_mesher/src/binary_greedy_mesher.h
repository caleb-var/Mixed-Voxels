#ifndef BINARY_GREEDY_MESHER_H
#define BINARY_GREEDY_MESHER_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

using namespace godot;

class BinaryGreedyMesher : public RefCounted {
    GDCLASS(BinaryGreedyMesher, RefCounted);

protected:
    static void _bind_methods();

public:
    BinaryGreedyMesher() = default;
    Ref<ArrayMesh> build_mesh(const PackedByteArray &voxels, const Vector3i &size, int lod = 0);
};

#endif // BINARY_GREEDY_MESHER_H
