#ifndef BINARY_GREEDY_MESHER_H
#define BINARY_GREEDY_MESHER_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>

using namespace godot;

class BinaryGreedyMesher : public RefCounted {
    GDCLASS(BinaryGreedyMesher, RefCounted);

protected:
    static void _bind_methods();

    struct Job {
        PackedByteArray voxels;
        Vector3i size;
        int lod;
        Variant chunk;
    };

    struct Result {
        Ref<ArrayMesh> mesh;
        Variant chunk;
    };

    std::mutex jobs_mutex;
    std::condition_variable jobs_cv;
    std::deque<Job> jobs;
    std::mutex results_mutex;
    std::deque<Result> results;
    std::thread worker;
    bool stop_worker = false;

    void thread_main();

public:
    BinaryGreedyMesher();
    ~BinaryGreedyMesher();

    Ref<ArrayMesh> build_mesh(const PackedByteArray &voxels, const Vector3i &size, int lod = 0);
    void schedule_mesh(const PackedByteArray &voxels, const Vector3i &size, int lod, Variant chunk);
    Dictionary pop_completed();
    void stop();
};

#endif // BINARY_GREEDY_MESHER_H
