#+private
package vk_bootstrap

// Core
import "core:log"

// Vendor
import vk "vendor:vulkan"

swapchain_builder_utils_add_desired_formats :: proc(formats: ^[dynamic]vk.SurfaceFormatKHR) {
	append(formats, vk.SurfaceFormatKHR{format = .B8G8R8A8_SRGB, colorSpace = .SRGB_NONLINEAR})
	append(formats, vk.SurfaceFormatKHR{format = .R8G8B8A8_SRGB, colorSpace = .SRGB_NONLINEAR})
}

swapchain_builder_utils_add_desired_present_modes :: proc(
	present_modes: ^[dynamic]vk.PresentModeKHR,
) {
	append(present_modes, vk.PresentModeKHR.FIFO)
	append(present_modes, vk.PresentModeKHR.MAILBOX)
}

Surface_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

swapchain_builder_utils_query_surface_support_details :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) -> (
	details: Surface_Support_Details,
	ok: bool,
) #optional_ok {
	if surface == 0 {
		log.error("Surface handle cannot be null")
		return
	}

	// Capabilities
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physical_device,
		surface,
		&details.capabilities,
	); res != .SUCCESS {
		log.fatalf("Failed to get physical device surface capabilities? \x1b[31m%v\x1b[0m", res)
		return
	}

	// Supported formats
	format_count: u32
	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil);
	   res != .SUCCESS {
		log.fatalf("Failed to get surface formats count: \x1b[31m%v\x1b[0m", res)
		return
	}

	if format_count == 0 {
		log.fatal("No surface format found!")
		return
	}

	details.formats = make([]vk.SurfaceFormatKHR, int(format_count), allocator)
	defer if !ok {
		delete(details.formats)
	}

	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&format_count,
		raw_data(details.formats),
	); res != .SUCCESS {
		log.fatalf("Failed to get surface formats: \x1b[31m%v\x1b[0m", res)
		return
	}

	// Supported present modes
	present_mode_count: u32
	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		nil,
	); res != .SUCCESS {
		log.fatalf("Failed to get surface present modes count: \x1b[31m%v\x1b[0m", res)
		return
	}

	if present_mode_count == 0 {
		log.fatal("No surface present mode found.")
		return
	}

	details.present_modes = make([]vk.PresentModeKHR, int(present_mode_count), allocator)
	defer if !ok {
		delete(details.present_modes)
	}

	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		raw_data(details.present_modes),
	); res != .SUCCESS {
		log.fatalf("Failed to get surface present modes: \x1b[31m%v\x1b[0m", res)
		return
	}

	return details, true
}

swapchain_builder_utils_find_best_surface_format :: proc(
	available_formats: ^[]vk.SurfaceFormatKHR,
	desired_formats: ^[dynamic]vk.SurfaceFormatKHR,
) -> vk.SurfaceFormatKHR {
	if surface_format, ok := swapchain_builder_utils_find_desired_surface_format(
		available_formats,
		desired_formats,
	); ok {
		return surface_format
	}

	// Use the first available format as a fallback if any desired formats aren't found
	log.warnf(
		"Desired surface formats not found, fallback to the first available format: " +
		"\x1b[33m%v\x1b[0m | \x1b[33m%v\x1b[0m",
		available_formats[0].format,
		available_formats[0].colorSpace,
	)

	return available_formats[0]
}

swapchain_builder_utils_find_desired_surface_format :: proc(
	available_formats: ^[]vk.SurfaceFormatKHR,
	desired_formats: ^[dynamic]vk.SurfaceFormatKHR,
) -> (
	format: vk.SurfaceFormatKHR,
	ok: bool,
) {
	for desired in desired_formats {
		for available in available_formats {
			// finds the first format that is desired and available
			if desired.format == available.format && desired.colorSpace == available.colorSpace {
				return desired, true
			}
		}
	}

	log.warn("No suitable desired format")

	// if no desired format is available,
	// we report that no format is suitable to the user request
	return
}

swapchain_builder_utils_find_extent :: proc(
	capabilities: vk.SurfaceCapabilitiesKHR,
	desired_width, desired_height: u32,
) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	actual_extent: vk.Extent2D = {desired_width, desired_height}

	actual_extent.width = max(
		capabilities.minImageExtent.width,
		min(capabilities.maxImageExtent.width, actual_extent.width),
	)
	actual_extent.height = max(
		capabilities.minImageExtent.height,
		min(capabilities.maxImageExtent.height, actual_extent.height),
	)

	return actual_extent
}

swapchain_builder_utils_find_present_mode :: proc(
	available_resent_modes: ^[]vk.PresentModeKHR,
	desired_present_modes: ^[dynamic]vk.PresentModeKHR,
) -> vk.PresentModeKHR {
	#reverse for desired in desired_present_modes {
		for available in available_resent_modes {
			// finds the first present mode that is desired and available
			if (desired == available) {
				return desired
			}
		}
	}

	// Only present mode required, use as a fallback
	return .FIFO
}
