package vk_bootstrap

// Packages
import "core:log"
import vk "vendor:vulkan"

Device :: struct {
	ptr:                  vk.Device,
	physical_device:      ^Physical_Device,
	surface:              vk.SurfaceKHR,
	queue_families:       []vk.QueueFamilyProperties,
	allocation_callbacks: ^vk.AllocationCallbacks,
	instance_version:     u32,
}

Queue_Type :: enum {
	Present,
	Graphics,
	Compute,
	Transfer,
}

destroy_device :: proc(self: ^Device) {
	if self == nil {
		return
	}
	defer free(self)
	delete(self.queue_families)
	vk.DestroyDevice(self.ptr, self.allocation_callbacks)
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
			self.physical_device.ptr,
			self.surface,
		)
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Present queue index unavailable.")
			return
		}
	case .Graphics:
		index = get_first_queue_index(self.queue_families, {.GRAPHICS})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Graphics queue index unavailable.")
			return
		}
	case .Compute:
		index = get_separate_queue_index(self.queue_families, {.COMPUTE}, {.TRANSFER})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Compute queue index unavailable.")
			return
		}
	case .Transfer:
		index = get_separate_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Transfer queue index unavailable.")
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
			log.error("Dedicated Compute queue index unavailable.")
			return
		}
	case .Transfer:
		index = get_dedicated_queue_index(self.queue_families, {.TRANSFER}, {.COMPUTE})
		if index == vk.QUEUE_FAMILY_IGNORED {
			log.error("Dedicated Transfer queue index unavailable.")
			return
		}
	case:
		log.error("Invalid queue family index.")
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
	vk.GetDeviceQueue(self.ptr, index, 0, &queue)
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
	vk.GetDeviceQueue(self.ptr, index, 0, &queue)
	return queue, true
}
