#+vet !unused-imports
#+feature global-context
package vk_bootstrap

// Core
import "base:runtime"
import "core:dynlib"
import "core:os"

// Vendor
import vk "vendor:vulkan"

@(private = "file")
g_module: dynlib.Library = nil

@(init, private = "file")
init :: proc() {
	loaded: bool

	// Load Vulkan library by platform
	when ODIN_OS == .Windows {
		g_module, loaded = dynlib.load_library("vulkan-1.dll")
	} else when ODIN_OS == .Darwin {
		g_module, loaded = dynlib.load_library("libvulkan.dylib", true)

		if !loaded {
			g_module, loaded = dynlib.load_library("libvulkan.1.dylib", true)
		}

		if !loaded {
			g_module, loaded = dynlib.load_library("libMoltenVK.dylib", true)
		}

		// Add support for using Vulkan and MoltenVK in a Framework. App store rules for iOS
		// strictly enforce no .dylib's. If they aren't found it just falls through
		if !loaded {
			g_module, loaded = dynlib.load_library("vulkan.framework/vulkan", true)
		}

		if !loaded {
			g_module, loaded = dynlib.load_library("MoltenVK.framework/MoltenVK", true)
			ta := context.temp_allocator
			runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
			_, found_lib_path := os.lookup_env("DYLD_FALLBACK_LIBRARY_PATH", ta)
			// modern versions of macOS don't search /usr/local/lib automatically contrary to what
			// man dlopen says Vulkan SDK uses this as the system-wide installation location, so
			// we're going to fallback to this if all else fails
			if !loaded && !found_lib_path {
				g_module, loaded = dynlib.load_library("/usr/local/lib/libvulkan.dylib", true)
			}
		}
	} else {
		g_module, loaded = dynlib.load_library("libvulkan.so.1", true)
		if !loaded {
			g_module, loaded = dynlib.load_library("libvulkan.so", true)
		}
	}

	ensure(loaded, "Failed to load Vulkan library!")
	ensure(g_module != nil, "Failed to load Vulkan library module!")

	vk_get_instance_proc_addr, found := dynlib.symbol_address(g_module, "vkGetInstanceProcAddr")
	ensure(found, "Failed to get instance process address!")

	// Load the base vulkan procedures before we start using them
	vk.load_proc_addresses_global(vk_get_instance_proc_addr)
}

@(fini, private = "file")
deinit :: proc() {
	dynlib.unload_library(g_module)
}
