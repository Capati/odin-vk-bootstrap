package vk_bootstrap

// Vendor
import vk "vendor:vulkan"

FEATURES_FIELDS_CAPACITY :: 256

Physical_Device_Suitable :: enum {
	Yes,
	Partial,
	No,
}

Physical_Device :: struct {
	ptr:                          vk.PhysicalDevice,
	name:                         string,
	surface:                      vk.SurfaceKHR,
	features:                     vk.PhysicalDeviceFeatures,
	properties:                   vk.PhysicalDeviceProperties,
	memory_properties:            vk.PhysicalDeviceMemoryProperties,
	instance_version:             u32,
	extensions_to_enable:         [dynamic]cstring,
	available_extensions:         []vk.ExtensionProperties,
	queue_families:               []vk.QueueFamilyProperties,
	// std::vector<detail::GenericFeaturesPNextNode> extended_features_chain;
	features2:                    vk.PhysicalDeviceFeatures2,
	defer_surface_initialization: bool,
	properties2_ext_enabled:      bool,
	suitable:                     Physical_Device_Suitable,
}

destroy_physical_device :: proc(self: ^Physical_Device) {
	if self == nil do return
	defer free(self)
	delete(self.extensions_to_enable)
	delete(self.available_extensions)
	delete(self.queue_families)
	if self.name != "" {
		delete(self.name)
	}
}

init_physical_device :: proc() -> (pd: Physical_Device, err: Error) {
	return
}

// Has a queue family that supports compute operations but not graphics nor transfer.
physical_device_has_dedicated_compute_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_dedicated_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

// Has a queue family that supports transfer operations but not graphics nor compute.
physical_device_has_dedicated_transfer_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

// Has a queue family that supports transfer operations but not graphics.
physical_device_has_separate_compute_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_separate_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

// Has a queue family that supports transfer operations but not graphics.
physical_device_has_separate_transfer_queue :: proc(self: ^Physical_Device) -> (result: bool) {
	result =
		get_separate_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE}) !=
		vk.QUEUE_FAMILY_IGNORED
	return
}

// Advanced: Get the `vk.QueueFamilyProperties` of the device if special queue setup is needed.
physical_device_get_queue_families :: proc(self: ^Physical_Device) -> []vk.QueueFamilyProperties {
	return self.queue_families
}

// Query the list of extensions which should be enabled.
physical_device_get_extensions :: proc(self: ^Physical_Device) -> [dynamic]cstring {
	return self.extensions_to_enable
}

// Query the list of extensions which the physical device supports.
physical_device_get_available_extensions :: proc(
	self: ^Physical_Device,
) -> []vk.ExtensionProperties {
	return self.available_extensions
}

// Returns true if an extension should be enabled on the device.
physical_device_is_extension_present :: proc(self: ^Physical_Device, extension: cstring) -> bool {
	for ext in &self.available_extensions {
		if cstring(&ext.extensionName[0]) == extension do return true
	}
	return false
}

// If the given extension is present, make the extension be enabled on the device.
// Returns true the extension is present.
physical_device_enable_extension_if_present :: proc(
	self: ^Physical_Device,
	extension: cstring,
) -> bool {
	for ext in &self.available_extensions {
		if cstring(&ext.extensionName[0]) == extension {
			append(&self.extensions_to_enable, extension)
			return true
		}
	}
	return false
}
