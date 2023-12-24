package main

// Core
import "core:fmt"
import "core:log"
import "core:mem"

// Vendor
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

// Package
import "./../../vkb"

MINIMUM_API_VERSION :: vk.API_VERSION_1_2

create_instance :: proc() -> (instance: ^vkb.Instance, err: vkb.Error) {
	// Create a new instance builder
	builder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&builder)

	// Require the minimum Vulkan api version 1.2
	vkb.instance_set_minimum_version(&builder, MINIMUM_API_VERSION)

	// Get supported layers and extensions
	system_info := vkb.get_system_info() or_return
	defer vkb.destroy_system_info(&system_info)

	when ODIN_DEBUG {
		// Enable `VK_LAYER_KHRONOS_validation` layer
		vkb.instance_request_validation_layers(&builder)

		// Enable debug reporting with bootstrap default messenger
		vkb.instance_use_default_debug_messenger(&builder)

		VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

		if vkb.is_layer_available(&system_info, VK_LAYER_LUNARG_MONITOR) {
			// Displays FPS in the application's title bar. It is only compatible with the
			// Win32 and XCB windowing systems. Mark as not required layer.
			// https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
			when ODIN_OS == .Windows || ODIN_OS == .Linux {
				vkb.instance_enable_layer(&builder, VK_LAYER_LUNARG_MONITOR)
			}
		}
	}

	// Create the Vulkan instance
	return vkb.build_instance(&builder)
}

request_physical_device :: proc(
	instance: ^vkb.Instance,
	surface: vk.SurfaceKHR,
) -> (
	physical_device: ^vkb.Physical_Device,
	err: vkb.Error,
) {
	// Create a new physical device selector
	selector := vkb.init_physical_device_selector(instance) or_return
	defer vkb.destroy_selection_criteria(&selector)

	// Set Vulkan 1.2 support
	vkb.selector_set_minimum_version(&selector, MINIMUM_API_VERSION)

	// We want a GPU that can render to current Window surface
	vkb.selector_set_surface(&selector, surface)

	// Try to select a suitable device
	return vkb.selector_select(&selector)
}

main :: proc() {
	context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
	defer log.destroy_console_logger(context.logger)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)

	defer {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	}

	// Initialize SDL
	sdl_flags := sdl.InitFlags{.VIDEO, .JOYSTICK, .GAMECONTROLLER, .EVENTS}
	if res := sdl.Init(sdl_flags); res != 0 {
		log.errorf("Failed to initialize the native window: [%s]", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window_flags: sdl.WindowFlags = {.VULKAN, .ALLOW_HIGHDPI, .SHOWN}

	window := sdl.CreateWindow(
		"Vulkan",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		800,
		600,
		window_flags,
	)
	if window == nil {
		log.errorf("Failed to create the native window: [%s]", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	instance, instance_err := create_instance()
	if instance_err != nil do return
	defer vkb.destroy_instance(instance)

	surface: vk.SurfaceKHR
	if !sdl.Vulkan_CreateSurface(window, instance.ptr, &surface) {
		log.errorf("SDL couldn't create vulkan surface: %s", sdl.GetError())
		return
	}
	defer vkb.destroy_surface(instance, surface)

	physical_device, physical_device_err := request_physical_device(instance, surface)
	if physical_device_err != nil do return
	// In Vulkan you don't need to destroy a physical device, but here you need
	// to free some resources when the physical device was created.
	defer vkb.destroy_physical_device(physical_device)

	running := true

	for running {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			#partial switch (e.type) {
			case .QUIT:
				running = false
				break
			}
		}
	}
}
