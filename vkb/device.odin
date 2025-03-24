package vk_bootstrap

// Core
import "core:mem"

// Vendor
import vk "vendor:vulkan"

Device :: struct {
	handle:               vk.Device,
	physical_device:      ^Physical_Device,
	surface:              vk.SurfaceKHR,
	queue_families:       []vk.QueueFamilyProperties,
	allocation_callbacks: ^vk.AllocationCallbacks,
	instance_version:     u32,

	// Internal
	allocator:            mem.Allocator,
}

Queue_Type :: enum {
	Present,
	Graphics,
	Compute,
	Transfer,
}

destroy_device :: proc(self: ^Device, loc := #caller_location) {
	assert(self != nil && self.handle != nil, "Invalid Device", loc)
	context.allocator = self.allocator
	delete(self.queue_families)
	vk.DestroyDevice(self.handle, self.allocation_callbacks)
	free(self)
}

device_get_queue_index :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	index: u32,
	ok: bool,
) #optional_ok {
	index = vk.QUEUE_FAMILY_IGNORED

	switch type {
	case .Present:
		index = get_present_queue_index(
			self.queue_families,
			self.physical_device.handle,
			self.surface,
		)
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

	return index, true
}

device_get_dedicated_queue_index :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	index: u32,
	ok: bool,
) #optional_ok {
	index = vk.QUEUE_FAMILY_IGNORED

	#partial switch type {
	case .Compute:
		index = get_dedicated_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Dedicated Compute queue index unavailable.")
			return
		}
	case .Transfer:
		index = get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log_error("Dedicated Transfer queue index unavailable.")
			return
		}
	case:
		log_error("Invalid queue family index.")
		return
	}

	return index, true
}

device_get_queue :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	queue: vk.Queue,
	ok: bool,
) #optional_ok {
	index := device_get_queue_index(self, type) or_return
	vk.GetDeviceQueue(self.handle, index, 0, &queue)
	return queue, true
}

device_get_dedicated_queue :: proc(
	self: ^Device,
	type: Queue_Type,
) -> (
	queue: vk.Queue,
	ok: bool,
) #optional_ok {
	index := device_get_dedicated_queue_index(self, type) or_return
	vk.GetDeviceQueue(self.handle, index, 0, &queue)
	return queue, true
}
