package vk_bootstrap

// Core
import "base:runtime"
import "core:mem"

// Vendor
import vk "vendor:vulkan"

/*
Gathers useful information about the available vulkan capabilities, like layers and instance
extensions. Use this for enabling features conditionally, ie if you would like an extension but
can use a fallback if it isn't supported but need to know if support is available first.
*/
System_Info :: struct {
	available_layers:            []vk.LayerProperties,
	available_extensions:        []vk.ExtensionProperties,
	validation_layers_available: bool,
	debug_utils_available:       bool,

	// internal
	allocator:                   mem.Allocator,
}

/* VK_LAYER_KHRONOS_validation */
VALIDATION_LAYER_NAME :: "VK_LAYER_KHRONOS_validation"

/* Get information about the available vulkan capabilities. */
get_system_info :: proc(
	allocator := context.allocator,
) -> (
	info: System_Info,
	ok: bool,
) #optional_ok {
	layer_count: u32
	if res := vk.EnumerateInstanceLayerProperties(&layer_count, nil); res != .SUCCESS {
		log_errorf("Failed to enumerate instance layer properties count: \x1b[31m%v\x1b[0m", res)
		return
	}

	info.allocator = allocator

	info.available_layers = make([]vk.LayerProperties, layer_count, allocator)

	if layer_count > 0 {
		if res := vk.EnumerateInstanceLayerProperties(
			&layer_count,
			raw_data(info.available_layers),
		); res != .SUCCESS {
			log_errorf("Failed to enumerate instance layer properties: \x1b[31m%v\x1b[0m", res)
			return
		}

		for &layer in &info.available_layers {
			if cstring(&layer.layerName[0]) == VALIDATION_LAYER_NAME {
				info.validation_layers_available = true
				break
			}
		}
	}

	extension_count: u32 = 0
	if res := vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil);
	   res != .SUCCESS {
		log_errorf("Failed to enumerate instance extension properties: \x1b[31m%v\x1b[0m", res)
		return
	}

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	available_extensions := make([dynamic]vk.ExtensionProperties, extension_count, ta)

	if extension_count > 0 {
		if res := vk.EnumerateInstanceExtensionProperties(
			nil,
			&extension_count,
			raw_data(available_extensions),
		); res != .SUCCESS {
			log_errorf("Failed to enumerate instance extension properties: \x1b[31m%v\x1b[0m", res)
			return
		}

		// Check if `VK_EXT_debug_utils` extensions is available
		for &ext in &available_extensions {
			if cstring(&ext.extensionName[0]) == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				info.debug_utils_available = true
				break
			}
		}
	}

	// Check for layer extensions
	for &layer in &info.available_layers {
		layer_extension_count: u32 = 0
		if res := vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_extension_count,
			nil,
		); res != .SUCCESS {
			log_errorf("Failed to enumerate layer extension properties: \x1b[31m%v\x1b[0m", res)
			return
		}

		if layer_extension_count == 0 {
			continue
		}

		layer_extensions := make([]vk.ExtensionProperties, layer_extension_count, ta)

		if res := vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_extension_count,
			raw_data(layer_extensions),
		); res != .SUCCESS {
			log_errorf("Failed to enumerate layer extension properties: \x1b[31m%v\x1b[0m", res)
			return
		}

		for &ext in &layer_extensions {
			found := false
			for &available_ext in &available_extensions {
				if cstring(&available_ext.extensionName[0]) == cstring(&ext.extensionName[0]) {
					found = true
					break
				}
			}

			if !found {
				extension_count += 1
				append(&available_extensions, ext)
			}

			if info.debug_utils_available {
				continue
			}

			// Check if `VK_EXT_debug_utils` extensions is available from this layer extension
			if cstring(&ext.extensionName[0]) == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				info.debug_utils_available = true
			}
		}
	}

	info.available_extensions = make([]vk.ExtensionProperties, extension_count, allocator)
	copy(info.available_extensions[:], available_extensions[:])

	return info, true
}

/* Clean up and deallocating resources associated with the `System_Info` object. */
destroy_system_info :: proc(self: ^System_Info) {
	context.allocator = self.allocator
	delete(self.available_layers)
	delete(self.available_extensions)
}

/* Returns `true` if a layer is available. */
is_layer_available :: proc(self: ^System_Info, layer_name: cstring) -> bool {
	if layer_name == nil {
		return false
	}
	return check_layer_supported(self.available_layers, layer_name)
}

/* Returns `true` if an extension is available. */
is_extension_available :: proc(self: ^System_Info, ext_name: cstring) -> bool {
	if ext_name == nil {
		return false
	}
	return check_extension_supported(self.available_extensions, ext_name)
}

/*
Checks if a specific Vulkan layer is supported by comparing it against a list of available
layers.
 */
check_layer_supported :: proc "contextless" (
	available_layers: []vk.LayerProperties,
	layer_name: cstring,
) -> bool #no_bounds_check {
	if layer_name == nil {
		return false
	}

	for &layer in available_layers {
		if (cstring(&layer.layerName[0]) == layer_name) {
			return true
		}
	}

	return false
}

/*
Checks if all required Vulkan layers are supported by comparing them against a list of
available layers.
*/
check_layers_supported :: proc(
	available_layers: []vk.LayerProperties,
	required_layers: []cstring,
) -> bool {
	all_supported := true

	for layer_name in required_layers {
		if check_layer_supported(available_layers, layer_name) {
			continue
		}
		log_warnf("Required instance layer \x1b[31m%s\x1b[0m not present!", layer_name)
		all_supported = false
	}

	return all_supported
}

/*
Checks if a specific Vulkan extension is supported by comparing it against a list of available
extensions
*/
check_extension_supported :: proc(
	available_extensions: []vk.ExtensionProperties,
	ext_name: cstring,
) -> bool {
	if ext_name == nil {
		return false
	}

	for &ext in available_extensions {
		if (cstring(&ext.extensionName[0]) == ext_name) {
			return true
		}
	}

	return false
}

/*
Checks if all required Vulkan extensions are supported by comparing them against a list of
available extensions.
*/
check_extensions_supported :: proc(
	available_extensions: []vk.ExtensionProperties,
	required_extensions: []cstring,
) -> bool {
	all_supported := true

	for ext_name in required_extensions {
		if check_extension_supported(available_extensions, ext_name) {
			continue
		}
		log_errorf("Required instance extension \x1b[33m%s\x1b[0m not present!", ext_name)
		all_supported = false
	}

	return all_supported
}
