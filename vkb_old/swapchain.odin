package vk_bootstrap

// Core
import "base:runtime"
import "core:mem"

// Vendor
import vk "vendor:vulkan"

Swapchain :: struct {
	handle:                    vk.SwapchainKHR,
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

	// Internal
	allocator:                 mem.Allocator,
}

Queue_Family_Indices :: enum {
	Graphics,
	Present,
}

destroy_swapchain :: proc(self: ^Swapchain, loc := #caller_location) {
	assert(self != nil && self.handle != 0, "Invalid Swapchain", loc)
	vk.DestroySwapchainKHR(self.device.handle, self.handle, self.allocation_callbacks)
	free(self, self.allocator)
}

/* Returns a slice of `vk.Image` handles to the swapchain. */
swapchain_get_images :: proc(
	self: ^Swapchain,
	max_images: u32 = 0,
	allocator := context.allocator,
) -> (
	images: []vk.Image,
	ok: bool,
) #optional_ok {
	// Get the number of images in the swapchain
	image_count: u32 = 0
	if res := vk.GetSwapchainImagesKHR(self.device.handle, self.handle, &image_count, nil);
	   res != .SUCCESS {
		log_errorf("Failed to get swapchain images count: \x1b[31m%v\x1b[0m", res)
		return
	}

	if image_count == 0 {
		log_errorf("No swapchain images available!")
		return
	}

	// Limit the number of images if `max_images` is specified
	if max_images > 0 && image_count > max_images {
		image_count = max_images
	}

	// Allocate memory for the images
	images = make([]vk.Image, image_count, allocator)
	defer if !ok {
		delete(images, allocator)
	}

	// Retrieve the actual images
	if res := vk.GetSwapchainImagesKHR(
		self.device.handle,
		self.handle,
		&image_count,
		raw_data(images),
	); res != .SUCCESS {
		log_errorf("Failed to get swapchain images: \x1b[31m%v\x1b[0m", res)
		return
	}

	return images, true
}

/* Returns a slice of vk.ImageView's to the `vk.Image`'s of the swapchain. */
swapchain_get_image_views :: proc(
	self: ^Swapchain,
	p_next: rawptr = nil,
	allocator := context.allocator,
) -> (
	views: []vk.ImageView,
	ok: bool,
) #optional_ok {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	images := swapchain_get_images(self, allocator = ta) or_return

	already_contains_image_view_usage := false
	p_next := p_next

	for p_next != nil {
		if (cast(^vk.BaseInStructure)p_next).sType == .IMAGE_VIEW_CREATE_INFO {
			already_contains_image_view_usage = true
			break
		}
		p_next = (cast(^vk.BaseInStructure)p_next).pNext
	}

	desired_flags := vk.ImageViewUsageCreateInfo {
		sType = .IMAGE_VIEW_USAGE_CREATE_INFO,
		pNext = p_next,
		usage = self.image_usage_flags,
	}

	// Total of images to create views
	images_len := len(images)

	// Create image views for each image
	views = make([]vk.ImageView, images_len, allocator)
	defer if !ok {
		swapchain_destroy_image_views(self, views)
		delete(views, allocator)
	}

	for i in 0 ..< images_len {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
		}

		if self.instance_version >= vk.API_VERSION_1_1 && !already_contains_image_view_usage {
			create_info.pNext = &desired_flags
		} else {
			create_info.pNext = p_next
		}

		create_info.image = images[i]
		create_info.viewType = .D2
		create_info.format = self.image_format
		create_info.components = {
			r = .IDENTITY,
			g = .IDENTITY,
			b = .IDENTITY,
			a = .IDENTITY,
		}
		create_info.subresourceRange.aspectMask = {.COLOR}
		create_info.subresourceRange.baseMipLevel = 0
		create_info.subresourceRange.levelCount = 1
		create_info.subresourceRange.baseArrayLayer = 0
		create_info.subresourceRange.layerCount = 1

		if res := vk.CreateImageView(
			self.device.handle,
			&create_info,
			self.allocation_callbacks,
			&views[i],
		); res != .SUCCESS {
			log_fatalf("Failed to create swapchain image view: \x1b[31m%v\x1b[0m ", res)
			return
		}
	}

	return views, true
}

swapchain_destroy_image_views :: proc(self: ^Swapchain, views: []vk.ImageView) {
	for view, index in views {
		if view == 0 {
			log_warnf(
				"Trying to destroy an invalid image view at \x1b[33m%d\x1b[0m, ignoring...",
				index,
			)
			continue
		}
		vk.DestroyImageView(self.device.handle, view, self.allocation_callbacks)
	}
}
