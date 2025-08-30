#include "register_types.h"
#include "binary_greedy_mesher.h"

#include "binary_greedy_mesher.h"
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>

using namespace godot;

    void initialize_binary_greedy_mesher_module(ModuleInitializationLevel p_level) {
        if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
            return;
        }
        ClassDB::register_class<BinaryGreedyMesher>();
    }

    void uninitialize_binary_greedy_mesher_module(ModuleInitializationLevel p_level) {
        if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
            return;
        }
    }

    extern "C" {
    GDExtensionBool GDE_EXPORT binary_greedy_mesher_library_init(
            GDExtensionInterfaceGetProcAddress p_get_proc_address,
            GDExtensionClassLibraryPtr p_library,
            GDExtensionInitialization *r_initialization) {
        GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
        init_obj.register_initializer(initialize_binary_greedy_mesher_module);
        init_obj.register_terminator(uninitialize_binary_greedy_mesher_module);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
        return init_obj.init();
    }
}
