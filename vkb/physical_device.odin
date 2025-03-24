package vk_bootstrap

// Core
import "core:mem"

// Vendor
import vk "vendor:vulkan"

Physical_Device_Suitable :: enum {
	Yes,
	Partial,
	No,
}

Physical_Device :: struct {
	handle:                       vk.PhysicalDevice,
	name:                         string,
	surface:                      vk.SurfaceKHR,
	features:                     vk.PhysicalDeviceFeatures,
	properties:                   vk.PhysicalDeviceProperties,
	memory_properties:            vk.PhysicalDeviceMemoryProperties,
	instance_version:             u32,
	extensions_to_enable:         [dynamic]cstring,
	available_extensions:         []vk.ExtensionProperties,
	queue_families:               []vk.QueueFamilyProperties,
	extended_features_chain:      [dynamic]Generic_Feature,
	features2:                    vk.PhysicalDeviceFeatures2,
	defer_surface_initialization: bool,
	properties2_ext_enabled:      bool,
	suitable:                     Physical_Device_Suitable,

	// Internal
	allocator:                    mem.Allocator,
}

destroy_physical_device :: proc(self: ^Physical_Device, loc := #caller_location) {
	assert(self != nil && self.handle != nil, "Invalid Physical Device", loc)
	context.allocator = self.allocator
	delete(self.extensions_to_enable)
	delete(self.available_extensions)
	delete(self.queue_families)
	delete(self.extended_features_chain)
	if self.name != "" {
		delete(self.name)
	}
	free(self)
}

physical_device_get_queue_index :: proc(
	self: ^Physical_Device,
	type: Queue_Type,
) -> (
	index: u32,
	ok: bool,
) #optional_ok {
	index = vk.QUEUE_FAMILY_IGNORED

	switch type {
	case .Present:
		index = get_present_queue_index(self.queue_families, self.handle, self.surface)
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Present queue index unavailable.")
			return
		}
	case .Graphics:
		index = get_first_queue_index(self.queue_families, {.GRAPHICS})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Graphics queue index unavailable.")
			return
		}
	case .Compute:
		index = get_separate_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Compute queue index unavailable.")
			return
		}
	case .Transfer:
		index = get_separate_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Transfer queue index unavailable.")
			return
		}
	}

	return index, index != vk.QUEUE_FAMILY_IGNORED
}

physical_device_get_dedicated_queue_index :: proc(
	self: ^Physical_Device,
	type: Queue_Type,
) -> (
	index: u32,
	ok: bool,
) #optional_ok {
	index = vk.QUEUE_FAMILY_IGNORED
	#partial switch type {
	case .Compute:
		index = get_dedicated_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
	case .Transfer:
		index = get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
	}
	return index, index != vk.QUEUE_FAMILY_IGNORED
}

/* Has a queue family that supports compute operations but not graphics nor transfer. */
physical_device_has_dedicated_compute_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_dedicated_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

/* Has a queue family that supports transfer operations but not graphics nor compute. */
physical_device_has_dedicated_transfer_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

/* Has a queue family that supports transfer operations but not graphics. */
physical_device_has_separate_compute_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_separate_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

/* Has a queue family that supports transfer operations but not graphics. */
physical_device_has_separate_transfer_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_separate_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

/* Advanced: Get the `vk.QueueFamilyProperties` of the device if special queue setup is needed. */
physical_device_get_queue_families :: proc(self: ^Physical_Device) -> []vk.QueueFamilyProperties {
	return self.queue_families
}

/* Query the list of extensions which should be enabled. */
physical_device_get_extensions :: proc(self: ^Physical_Device) -> [dynamic]cstring {
	return self.extensions_to_enable
}

/* Query the list of extensions which the physical device supports. */
physical_device_get_available_extensions :: proc(
	self: ^Physical_Device,
) -> []vk.ExtensionProperties {
	return self.available_extensions
}

/* Returns true if an extension should be enabled on the device. */
physical_device_is_extension_present :: proc(self: ^Physical_Device, extension: cstring) -> bool {
	for &ext in &self.available_extensions {
		if cstring(&ext.extensionName[0]) == extension {
			return true
		}
	}
	return false
}

/*
If the given extension is present, make the extension be enabled on the device

Returns true the extension is present.
*/
physical_device_enable_extension_if_present :: proc(
	self: ^Physical_Device,
	extension: cstring,
) -> bool {
	for &ext in &self.available_extensions {
		if cstring(&ext.extensionName[0]) == extension {
			append(&self.extensions_to_enable, extension)
			return true
		}
	}

	log_warnf("The extension \x1b[33m%s\x1b[0m is not available", extension)

	return false
}

/*
If all the given extensions are present, make all the extensions be enabled on the device.

Returns `true` if all the extensions are present.
*/
physical_device_enable_extensions_if_present :: proc(
	self: ^Physical_Device,
	extensions: []cstring,
) -> bool {
	all_ext_present := true

	for &available in &self.available_extensions {
		for ext in extensions {
			if cstring(&available.extensionName[0]) != ext {
				log_warnf("The extension \x1b[33m%s\x1b[0m is not available", ext)
				all_ext_present = false
			}
		}
	}

	if !all_ext_present {
		return false
	}

	append(&self.extensions_to_enable, ..extensions[:])

	return true
}


/* Get the supported sample counts. */
physical_device_get_supported_sample_counts :: proc(
	self: ^Physical_Device,
) -> vk.SampleCountFlags {
	return(
		self.properties.limits.framebufferColorSampleCounts &
		self.properties.limits.framebufferDepthSampleCounts \
	)
}

/* Get the max supported MSAA. */
physical_device_get_max_msaa :: proc(self: ^Physical_Device) -> vk.SampleCountFlag {
	supported_sample_counts := physical_device_get_supported_sample_counts(self)

	if ._64 in supported_sample_counts {
		return ._64
	} else if ._32 in supported_sample_counts {
		return ._32
	} else if ._16 in supported_sample_counts {
		return ._16
	} else if ._8 in supported_sample_counts {
		return ._8
	} else if ._4 in supported_sample_counts {
		return ._4
	} else if ._2 in supported_sample_counts {
		return ._2
	}

	return ._1
}
