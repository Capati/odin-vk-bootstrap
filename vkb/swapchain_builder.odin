package vk_bootstrap

// Core
import "base:runtime"
import "core:mem"

// Vendor
import vk "vendor:vulkan"

Swapchain_Builder :: struct {
	physical_device:          ^Physical_Device,
	device:                   ^Device,
	p_next_chain:             [dynamic]^vk.BaseOutStructure,
	create_flags:             vk.SwapchainCreateFlagsKHR,
	surface:                  vk.SurfaceKHR,
	desired_formats:          [dynamic]vk.SurfaceFormatKHR,
	instance_version:         u32,
	desired_width:            u32,
	desired_height:           u32,
	array_layer_count:        u32,
	min_image_count:          u32,
	required_min_image_count: u32,
	image_usage_flags:        vk.ImageUsageFlags,
	graphics_queue_index:     u32,
	present_queue_index:      u32,
	pre_transform:            vk.SurfaceTransformFlagsKHR,
	composite_alpha:          vk.CompositeAlphaFlagsKHR,
	desired_present_modes:    [dynamic]vk.PresentModeKHR,
	clipped:                  bool,
	old_swapchain:            vk.SwapchainKHR,
	allocation_callbacks:     ^vk.AllocationCallbacks,
	initialized:              bool,

	// Internal
	allocator:                mem.Allocator,
}

DEFAULT_SWAPCHAIN_BUILDER :: Swapchain_Builder {
	instance_version  = vk.API_VERSION_1_0,
	create_flags      = {},
	desired_width     = 256,
	desired_height    = 256,
	array_layer_count = 1,
	image_usage_flags = {.COLOR_ATTACHMENT},
	pre_transform     = {},
	composite_alpha   = {.OPAQUE},
	clipped           = true,
}

init_swapchain_builder_base :: proc(builder: ^Swapchain_Builder) {
	builder.allocator = runtime.default_allocator()

	builder.p_next_chain.allocator = builder.allocator
	builder.desired_formats.allocator = builder.allocator
	builder.desired_present_modes.allocator = builder.allocator
}

// Creates a `Swapchain_Builder` with a `vkb.Device`.
init_swapchain_builder_default :: proc(
	device: ^Device,
) -> (
	builder: Swapchain_Builder,
	ok: bool,
) #optional_ok {
	builder = DEFAULT_SWAPCHAIN_BUILDER

	init_swapchain_builder_base(&builder)

	builder.physical_device = device.physical_device
	builder.device = device
	builder.surface = device.surface
	builder.instance_version = device.instance_version
	builder.present_queue_index = device_get_queue_index(device, .Present) or_return
	builder.graphics_queue_index = device_get_queue_index(device, .Graphics) or_return
	builder.allocation_callbacks = device.allocation_callbacks

	return builder, true
}

// Creates a `Swapchain_Builder` with a specific `vkb.Device` and `vk.SurfaceKHR`.
init_swapchain_builder_surface :: proc(
	device: ^Device,
	surface: vk.SurfaceKHR,
) -> (
	builder: Swapchain_Builder,
	ok: bool,
) #optional_ok {
	builder = DEFAULT_SWAPCHAIN_BUILDER

	init_swapchain_builder_base(&builder)

	builder.physical_device = device.physical_device
	builder.device = device
	builder.surface = surface
	builder.instance_version = device.instance_version
	default_surface := device.surface
	device.surface = surface
	builder.present_queue_index = device_get_queue_index(device, .Present) or_return
	builder.graphics_queue_index = device_get_queue_index(device, .Graphics) or_return
	device.surface = default_surface
	builder.allocation_callbacks = device.allocation_callbacks

	return builder, true
}

// Creates a `Swapchain_Builder` with a specific `vkb.Device`, `vk.SurfaceKHR`, and optionally
// can provide the indices for the graphics and present queue.
//
// Note: The procedure will query the graphics & present queue if the indices are not provided.
init_swapchain_builder_handles :: proc(
	physical_device: ^Physical_Device,
	device: ^Device,
	surface: vk.SurfaceKHR,
	#any_int graphics_queue_index: u32 = vk.QUEUE_FAMILY_IGNORED,
	#any_int present_queue_index: u32 = vk.QUEUE_FAMILY_IGNORED,
) -> (
	builder: Swapchain_Builder,
	ok: bool,
) #optional_ok {
	builder = DEFAULT_SWAPCHAIN_BUILDER

	init_swapchain_builder_base(&builder)

	builder.physical_device = device.physical_device
	builder.device = device
	builder.surface = surface
	builder.instance_version = device.instance_version
	builder.present_queue_index = present_queue_index
	builder.graphics_queue_index = graphics_queue_index

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	if graphics_queue_index == vk.QUEUE_FAMILY_IGNORED ||
	   present_queue_index == vk.QUEUE_FAMILY_IGNORED {
		// Get the device queue families
		queue_family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device.handle, &queue_family_count, nil)

		if queue_family_count == 0 {
			log_error(
				"Failed to get physical device queue family properties: Queue family is empty!",
			)
			return
		}

		queue_families, queue_families_err := make(
			[]vk.QueueFamilyProperties,
			int(queue_family_count),
			ta,
		)
		if queue_families_err != nil {
			log_fatalf("Failed to allocate queue families: \x1b[31m%v\x1b[0m", queue_families_err)
			return
		}

		vk.GetPhysicalDeviceQueueFamilyProperties(
			physical_device.handle,
			&queue_family_count,
			raw_data(queue_families),
		)

		if graphics_queue_index == vk.QUEUE_FAMILY_IGNORED {
			builder.graphics_queue_index = get_first_queue_index(queue_families, {.GRAPHICS})
		}

		if present_queue_index == vk.QUEUE_FAMILY_IGNORED {
			builder.present_queue_index = get_present_queue_index(
				queue_families,
				physical_device.handle,
				surface,
			)
		}
	}

	builder.allocation_callbacks = device.allocation_callbacks

	return builder, true
}


// Creates a `Swapchain_Builder`:
// - with a `vkb.Device`.
// - with a specific `VkSurfaceKHR` and `vkb.Device`.
// - with Vulkan handles for the physical device, device and surface and optionally can provide
//   the `u32` indices for the graphics and present queue. Note: The procedure will query the
//   graphics & present queue if the indices are not provided.
init_swapchain_builder :: proc {
	init_swapchain_builder_default,
	init_swapchain_builder_surface,
	init_swapchain_builder_handles,
}

destroy_swapchain_builder :: proc(self: ^Swapchain_Builder) {
	context.allocator = self.allocator
	delete(self.p_next_chain)
	delete(self.desired_formats)
	delete(self.desired_present_modes)
}

// Create a `Swapchain`. Return an error if it failed.
@(require_results)
build_swapchain :: proc(
	self: ^Swapchain_Builder,
	allocator := context.allocator,
) -> (
	swapchain: ^Swapchain,
	ok: bool,
) #optional_ok {
	if self.old_swapchain != 0 {
		self.initialized = true
	}

	if self.initialized {
		log_info("Rebuilding swapchain...")
	} else {
		log_info("Building swapchain...")
	}

	if self.surface == 0 {
		log_error("Swapchain requires a surface handle")
		return
	}

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	desired_formats := make([dynamic]vk.SurfaceFormatKHR, ta)

	if len(self.desired_formats) == 0 {
		swapchain_builder_utils_add_desired_formats(&desired_formats)
	} else {
		append(&desired_formats, ..self.desired_formats[:])
	}

	desired_present_modes := make([dynamic]vk.PresentModeKHR, ta)

	if len(self.desired_present_modes) == 0 {
		swapchain_builder_utils_add_desired_present_modes(&desired_present_modes)
	} else {
		append(&desired_present_modes, ..self.desired_present_modes[:])
	}

	// Get surface support details (capabilities, formats and present modes)
	surface_support := swapchain_builder_utils_query_surface_support_details(
		self.physical_device.handle,
		self.surface,
		context.temp_allocator,
	) or_return

	// Set image count
	image_count: u32 = self.min_image_count

	if self.required_min_image_count >= 1 {
		if self.required_min_image_count < surface_support.capabilities.minImageCount {
			log_errorf(
				"Required minimum image count \x1b[31m%d\x1b[0m is too low",
				self.required_min_image_count,
			)
			return
		}

		image_count = self.required_min_image_count
	} else if self.min_image_count == 0 {
		// We intentionally use `minImageCount` + 1 to maintain existing behavior, even if it
		// typically results in triple buffering on most systems.
		image_count = surface_support.capabilities.minImageCount + 1
	} else {
		image_count = self.min_image_count
		if (image_count < surface_support.capabilities.minImageCount) {
			image_count = surface_support.capabilities.minImageCount
		}
	}

	if (surface_support.capabilities.maxImageCount > 0 &&
		   image_count > surface_support.capabilities.maxImageCount) {
		image_count = surface_support.capabilities.maxImageCount
	}

	surface_format := swapchain_builder_utils_find_best_surface_format(
		&surface_support.formats,
		&desired_formats,
	)

	if !self.initialized {
		// log_debugf("Image count: \x1b[32m%d\x1b[0m", image_count)
		log_debugf("Selected surface format: \x1b[32m%v\x1b[0m", surface_format.format)
		log_debugf("Selected surface color space: \x1b[32m%v\x1b[0m", surface_format.colorSpace)
	}

	extent := swapchain_builder_utils_find_extent(
		surface_support.capabilities,
		self.desired_width,
		self.desired_height,
	)

	image_array_layers := self.array_layer_count
	if surface_support.capabilities.maxImageArrayLayers < self.array_layer_count {
		if !self.initialized {
			log_warnf(
				"Requested image array layers \x1b[33m%d\x1b[0m is greater than supported max " +
				"image array layers \x1b[33m%d\x1b[0m, defaulting to maximum value...",
				image_array_layers,
				surface_support.capabilities.maxImageArrayLayers,
			)
		}
		image_array_layers = surface_support.capabilities.maxImageArrayLayers
	}
	if (self.array_layer_count == 0) {
		image_array_layers = 1
	}

	queue_family_indices: [Queue_Family_Indices]u32 = {
		.Graphics = self.graphics_queue_index,
		.Present  = self.present_queue_index,
	}

	present_mode := swapchain_builder_utils_find_present_mode(
		&surface_support.present_modes,
		&desired_present_modes,
	)

	if !self.initialized {
		log_debugf("Selected present mode: \x1b[32m%v\x1b[0m", present_mode)
	}

	// vk.SurfaceCapabilitiesKHR.supportedUsageFlags is only valid for some present modes. For
	// shared present modes, we should also check
	// vk.SharedPresentSurfaceCapabilitiesKHR.sharedPresentSupportedUsageFlags.
	is_unextended_present_mode: bool =
		(present_mode == .IMMEDIATE) ||
		(present_mode == .MAILBOX) ||
		(present_mode == .FIFO) ||
		(present_mode == .FIFO_RELAXED)

	if is_unextended_present_mode &&
	   (self.image_usage_flags & surface_support.capabilities.supportedUsageFlags) !=
		   self.image_usage_flags {
		log_errorf("Required image usages \x1b[31m%v\x1b[0m not supported", self.image_usage_flags)
		return
	}

	pre_transform := self.pre_transform
	if self.pre_transform == {} {
		pre_transform = surface_support.capabilities.currentTransform
	}

	swapchain_create_info: vk.SwapchainCreateInfoKHR = {
		sType = .SWAPCHAIN_CREATE_INFO_KHR,
	}

	setup_p_next_chain(&swapchain_create_info, &self.p_next_chain)

	when ODIN_DEBUG {
		for node in self.p_next_chain {
			assert(node.sType != .APPLICATION_INFO)
		}
	}

	swapchain_create_info.flags = self.create_flags
	swapchain_create_info.surface = self.surface
	swapchain_create_info.minImageCount = image_count
	swapchain_create_info.imageFormat = surface_format.format
	swapchain_create_info.imageColorSpace = surface_format.colorSpace
	swapchain_create_info.imageExtent = extent
	swapchain_create_info.imageArrayLayers = image_array_layers
	swapchain_create_info.imageUsage = self.image_usage_flags

	current_queue_family_indices := []u32 {
		queue_family_indices[.Graphics],
		queue_family_indices[.Present],
	}

	if (self.graphics_queue_index != self.present_queue_index) {
		swapchain_create_info.imageSharingMode = .CONCURRENT
		swapchain_create_info.queueFamilyIndexCount = 2
		swapchain_create_info.pQueueFamilyIndices = raw_data(current_queue_family_indices)
	} else {
		swapchain_create_info.imageSharingMode = .EXCLUSIVE
	}

	if !self.initialized {
		log_debugf("Image sharing mode: \x1b[32m%v\x1b[0m", swapchain_create_info.imageSharingMode)
	}

	swapchain_create_info.preTransform = pre_transform
	swapchain_create_info.compositeAlpha = self.composite_alpha
	swapchain_create_info.presentMode = present_mode
	swapchain_create_info.clipped = b32(self.clipped)
	swapchain_create_info.oldSwapchain = self.old_swapchain

	swapchain = new(Swapchain, allocator)
	ensure(swapchain != nil, "Failed to allocate a Swapchain object")
	defer if !ok {
		free(swapchain, allocator)
	}
	swapchain.allocator = allocator

	if res := vk.CreateSwapchainKHR(
		self.device.handle,
		&swapchain_create_info,
		self.allocation_callbacks,
		&swapchain.handle,
	); res != .SUCCESS {
		log_fatalf("Failed to create Swapchain: \x1b[31m%v\x1b[0m", res)
		return
	}

	swapchain.queue_indices = queue_family_indices
	swapchain.device = self.device
	swapchain.image_format = surface_format.format
	swapchain.color_space = surface_format.colorSpace
	swapchain.image_usage_flags = self.image_usage_flags
	swapchain.extent = extent

	images := swapchain_get_images(swapchain, allocator = ta) or_return

	swapchain.requested_min_image_count = image_count
	swapchain.present_mode = present_mode
	swapchain.image_count = cast(u32)len(images)
	swapchain.instance_version = self.instance_version
	swapchain.allocation_callbacks = self.allocation_callbacks

	self.initialized = true

	return swapchain, true
}

swapchain_builder_set_old_swapchain_vulkan :: proc(
	self: ^Swapchain_Builder,
	old_swapchain: vk.SwapchainKHR,
) {
	self.old_swapchain = old_swapchain
}

swapchain_builder_set_old_swapchain_vkb :: proc(
	self: ^Swapchain_Builder,
	old_swapchain: ^Swapchain,
) {
	if old_swapchain != nil && old_swapchain.handle != 0 {
		self.old_swapchain = old_swapchain.handle
	} else {
		self.old_swapchain = 0
	}
}

// Set the `oldSwapchain` field of `vk.SwapchainCreateInfoKHR`.
//
// For use in rebuilding a swapchain.
swapchain_builder_set_old_swapchain :: proc {
	swapchain_builder_set_old_swapchain_vulkan,
	swapchain_builder_set_old_swapchain_vkb,
}

// Desired size of the swapchain.
//
// By default, the swapchain will use the size of the window being drawn to.
swapchain_builder_set_desired_extent :: proc(self: ^Swapchain_Builder, width, height: u32) {
	self.desired_width = width
	self.desired_height = height
}

// When determining the surface format, make this the first to be used if supported.
swapchain_builder_set_desired_format :: proc(
	self: ^Swapchain_Builder,
	format: vk.SurfaceFormatKHR,
) {
	inject_at(&self.desired_formats, 0, format)
}

// Add this swapchain format to the end of the list of formats selected from.
swapchain_builder_add_fallback_format :: proc(
	self: ^Swapchain_Builder,
	format: vk.SurfaceFormatKHR,
) {
	append(&self.desired_formats, format)
}


// Use the default swapchain formats. This is done if no formats are provided.

// Default surface format is {`vk.FORMAT_B8G8R8A8_SRGB`, `vk.COLOR_SPACE_SRGB_NONLINEAR_KHR`}
swapchain_builder_use_default_format_selection :: proc(self: ^Swapchain_Builder) {
	clear(&self.desired_formats)
	swapchain_builder_utils_add_desired_formats(&self.desired_formats)
}

// When determining the present mode, make this the first to be used if supported.
swapchain_builder_set_present_mode :: proc(
	self: ^Swapchain_Builder,
	present_mode: vk.PresentModeKHR,
) {
	append(&self.desired_present_modes, present_mode)
}


// Use the default presentation mode. This is done if no present modes are provided.
//
// Default present modes: `MAILBOX` with fallback `FIFO`.
swapchain_builder_use_default_present_mode_selection :: proc(self: ^Swapchain_Builder) {
	clear(&self.desired_present_modes)
	swapchain_builder_utils_add_desired_present_modes(&self.desired_present_modes)
}


// Set the bitmask of the image usage for acquired swapchain images.
//
// If the surface capabilities cannot allow it, building the swapchain will result in the
// `Required_Usage_Not_Supported` error.
swapchain_builder_set_image_usage_flags :: proc(
	self: ^Swapchain_Builder,
	usage_flags: vk.ImageUsageFlags,
) {
	self.image_usage_flags = usage_flags
}

// Add a image usage to the bitmask for acquired swapchain images.
swapchain_builder_add_image_usage_flags :: proc(
	self: ^Swapchain_Builder,
	usage_flags: vk.ImageUsageFlags,
) {
	self.image_usage_flags += usage_flags
}

// Use the default image usage bitmask values.
//
// This is the default if no image usages are provided. The default is `{.COLOR_ATTACHMENT}`
swapchain_builder_use_default_image_usage_flags :: proc(self: ^Swapchain_Builder) {
	self.image_usage_flags = {.COLOR_ATTACHMENT}
}

// Set the number of views in for multiview/stereo surface
swapchain_builder_set_image_array_layer_count :: proc(
	self: ^Swapchain_Builder,
	array_layer_count: u32,
) {
	self.array_layer_count = array_layer_count
}

swapchain_builder_set_desired_min_image_count_value :: proc(
	self: ^Swapchain_Builder,
	min_image_count: u32,
) {
	self.min_image_count = min_image_count
}

Buffer_Mode :: enum u32 {
	Single_Buffering = 1,
	Double_Buffering = 2,
	Triple_Buffering = 3,
}

swapchain_builder_set_desired_min_image_count_buffer_mode :: proc(
	self: ^Swapchain_Builder,
	buffer_mode: Buffer_Mode,
) {
	self.min_image_count = transmute(u32)buffer_mode
}

// Sets the desired minimum image count for the swapchain.
swapchain_builder_set_desired_min_image_count :: proc {
	swapchain_builder_set_desired_min_image_count_value,
	swapchain_builder_set_desired_min_image_count_buffer_mode,
}


// Set whether the Vulkan implementation is allowed to discard rendering operations that affect
// regions of the surface that are not visible. Default is `true`.
//
// Note: Applications should use the default of `true` if they do not expect to read back the
// content of presentable images before presenting them or after reacquiring them, and if their
// fragment shaders do not have any side effects that require them to run for all pixels in the
// presentable image.
swapchain_builder_set_clipped :: proc(self: ^Swapchain_Builder, clipped: bool = true) {
	self.clipped = clipped
}

// Set the `vk.SwapchainCreateFlagsKHR`.
swapchain_builder_set_create_flags :: proc(
	self: ^Swapchain_Builder,
	create_flags: vk.SwapchainCreateFlagsKHR,
) {
	self.create_flags = create_flags
}

// Set the transform to be applied, like a 90 degree rotation. Default is no transform.
swapchain_builder_set_pre_transform_flags :: proc(
	self: ^Swapchain_Builder,
	pre_transform_flags: vk.SurfaceTransformFlagsKHR,
) {
	self.pre_transform = pre_transform_flags
}


// Add a structure to the pNext chain of `vk.SwapchainCreateInfoKHR`.
//
// The structure must be valid when `swapchain_builder_build()` is called.
swapchain_builder_add_p_next :: proc(self: ^Swapchain_Builder, structure: ^$T) {
	append(&self.p_next_chain, cast(^vk.BaseOutStructure)structure)
}

// Set the alpha channel to be used with other windows in on the system. Default is {.OPAQUE}.
swapchain_builder_set_composite_alpha_flags :: proc(
	self: ^Swapchain_Builder,
	composite_alpha_flags: vk.CompositeAlphaFlagsKHR,
) {
	self.composite_alpha = composite_alpha_flags
}

// Provide custom allocation callbacks.
swapchain_builder_allocation_callbacks :: proc(
	self: ^Swapchain_Builder,
	callbacks: ^vk.AllocationCallbacks,
) {
	self.allocation_callbacks = callbacks
}
