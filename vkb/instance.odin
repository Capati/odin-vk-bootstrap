package vk_bootstrap

// Core
import "core:mem"

// Vendor
import vk "vendor:vulkan"

Instance :: struct {
	handle:                  vk.Instance,
	debug_messenger:         vk.DebugUtilsMessengerEXT,
	allocation_callbacks:    ^vk.AllocationCallbacks,
	headless:                bool,
	properties2_ext_enabled: bool,
	instance_version:        u32,
	api_version:             u32,

	// Internal
	allocator:               mem.Allocator,
}

/* Destroy the surface created from this instance. */
destroy_surface :: proc(self: ^Instance, surface: vk.SurfaceKHR, loc := #caller_location) {
	assert(self != nil && self.handle != nil, "Invalid Instance", loc)
	assert(surface != 0, "Invalid Surface", loc)
	vk.DestroySurfaceKHR(self.handle, surface, self.allocation_callbacks)
}

/* Destroy the instance and the debug messenger. */
destroy_instance :: proc(self: ^Instance, loc := #caller_location) {
	assert(self != nil && self.handle != nil, "Invalid Instance", loc)
	if self.debug_messenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(self.handle, self.debug_messenger, nil)
	}
	vk.DestroyInstance(self.handle, nil)
	free(self, self.allocator)
}
