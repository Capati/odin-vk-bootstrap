package vk_bootstrap

// Core
import "core:log"

// Vendor
import vk "vendor:vulkan"

Swapchain :: struct {
	ptr:                       vk.SwapchainKHR,
	device:                    ^Device,
	image_count:               u32,
	queue_indices:             [Queue_Family_Indices]u32,
	// The image format actually used when creating the swapchain.
	image_format:              vk.Format,
	// The color space actually used when creating the swapchain.
	color_space:               vk.ColorSpaceKHR,
	image_usage_flags:         vk.ImageUsageFlags,
	extent:                    vk.Extent2D,
	// The value of `minImageCount` actually used when creating the swapchain; note that the
	// presentation engine is always free to create more images than that.
	requested_min_image_count: u32,
	// The present mode actually used when creating the swapchain.
	present_mode:              vk.PresentModeKHR,
	instance_version:          u32,
	allocation_callbacks:      ^vk.AllocationCallbacks,
}

Queue_Family_Indices :: enum {
	Graphics,
	Present,
}

destroy_swapchain :: proc(self: ^Swapchain) {
	if self == nil do return
	defer free(self)
	if self.device != nil && self.ptr != 0 {
		vk.DestroySwapchainKHR(self.device.ptr, self.ptr, self.allocation_callbacks)
	}
}

// Returns an array of `vk.Image` handles to the swapchain.
swapchain_get_images :: proc(
	self: ^Swapchain,
	allocator := context.allocator,
) -> (
	images: []vk.Image,
	err: Error,
) {
	image_count: u32 = 0
	if res := vk.GetSwapchainImagesKHR(self.device.ptr, self.ptr, &image_count, nil);
	   res != .SUCCESS {
		log.fatalf("Failed to get swapchain images count: [%v]", res)
		return {}, .Failed_Get_Swapchain_Images
	}

	images = make([]vk.Image, image_count, allocator) or_return

	if res := vk.GetSwapchainImagesKHR(self.device.ptr, self.ptr, &image_count, raw_data(images));
	   res != .SUCCESS {
		log.fatalf("Failed to get swapchain images: [%v]", res)
		return {}, .Failed_Get_Swapchain_Images
	}

	return
}
