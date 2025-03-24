package vkb_test

// Core
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

@(test)
test_physical_device_selection :: proc(t: ^testing.T) {
	instance_builder, instance_builder_ok := vkb.init_instance_builder()
	testing.expect(t, instance_builder_ok, "Failed to initialize instance builder")
	defer vkb.destroy_instance_builder(&instance_builder)

	instance, build_ok := vkb.build_instance(&instance_builder)
	testing.expect(t, build_ok, "Failed to build an instance")
	defer vkb.destroy_instance(instance)

	// Test case 1: Basic initialization
	case_1: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select physical device with defaults")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			testing.expect(t, physical_device != nil, "Physical device should not be nil")
			testing.expect(
				t,
				physical_device.handle != nil,
				"Physical device handle should be valid",
			)
		}
	}

	// Test case 2: Select first device unconditionally
	case_2: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_select_first_device_unconditionally(&selector)

		if !testing.expect(
			t,
			selector.criteria.use_first_gpu_unconditionally,
			"First device selection should be enabled",
		) {
			break case_2
		}

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select physical device unconditionally")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}
	}

	// Test case 3: Require specific device type (Discrete)
	case_3: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_prefer_gpu_device_type(&selector, .Discrete)

		if !testing.expect(
			t,
			selector.criteria.preferred_type == .Discrete,
			"Preferred device type should be Discrete",
		) {
			break case_3
		}

		vkb.selector_allow_any_gpu_device_type(&selector, false)

		if !testing.expect(
			t,
			selector.criteria.allow_any_type == false,
			"Allow any type should be disabled",
		) {
			break case_3
		}

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select discrete physical device")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			testing.expect(
				t,
				physical_device.properties.deviceType == .DISCRETE_GPU,
				"Selected device should be discrete GPU",
			)
		}
	}

	// Test case 4: Require minimum version (1.2)
	case_4: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_2)

		if !testing.expect(
			t,
			selector.criteria.required_version == vk.API_VERSION_1_2,
			"Required version should be Vulkan 1.2",
		) {
			break case_4
		}

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with minimum version 1.2")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			testing.expect(
				t,
				physical_device.properties.apiVersion >= vk.API_VERSION_1_2,
				"Selected device should support at least Vulkan 1.2",
			)
		}
	}

	// Test case 5: Require specific features
	case_5: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		features := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
		}
		vkb.selector_set_required_features(&selector, features)

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with required features")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			testing.expect(
				t,
				physical_device.features.geometryShader == true,
				"Selected device should support geometry shaders",
			)
			testing.expect(
				t,
				physical_device.features.tessellationShader == true,
				"Selected device should support tessellation shaders",
			)
		}
	}

	// Test case 6: Require extensions
	case_6: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_add_required_extension(&selector, "VK_KHR_swapchain")

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with swapchain extension")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			found := false
			for &ext in physical_device.available_extensions {
				if string(cstring(&ext.extensionName[0])) == "VK_KHR_swapchain" {
					found = true
					break
				}
			}
			testing.expect(t, found, "Selected device should support VK_KHR_swapchain")
		}
	}

	// Test case 7: Require dedicated compute queue
	case_7: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_require_dedicated_compute_queue(&selector)

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with dedicated compute queue")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			idx := vkb.get_dedicated_queue_index(
				physical_device.queue_families,
				{.COMPUTE},
				{.TRANSFER},
			)
			testing.expect(
				t,
				idx != vk.QUEUE_FAMILY_IGNORED,
				"Selected device should have a dedicated compute queue",
			)
		}
	}

	// Test case 8: Require minimum memory size
	case_8: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_required_device_memory_size(&selector, 4 * 1024 * 1024 * 1024) // 4GB

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with minimum memory")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			sufficient_memory := false
			for i: u32 = 0; i < physical_device.memory_properties.memoryHeapCount; i += 1 {
				if .DEVICE_LOCAL in physical_device.memory_properties.memoryHeaps[i].flags {
					if physical_device.memory_properties.memoryHeaps[i].size >=
					   4 * 1024 * 1024 * 1024 {
						sufficient_memory = true
						break
					}
				}
			}
			testing.expect(
				t,
				sufficient_memory,
				"Selected device should have at least 4GB of device-local memory",
			)
		}
	}

	// Test case 9: Multiple criteria combination
	case_9: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_defer_surface_initialization(&selector)

		vkb.selector_prefer_gpu_device_type(&selector, .Discrete)
		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_2)
		vkb.selector_add_required_extension(&selector, "VK_KHR_swapchain")
		vkb.selector_require_separate_compute_queue(&selector)

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, select_ok, "Failed to select device with multiple criteria")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		if select_ok {
			testing.expect(
				t,
				physical_device.properties.deviceType == .DISCRETE_GPU,
				"Selected device should be discrete GPU",
			)
			testing.expect(
				t,
				physical_device.properties.apiVersion >= vk.API_VERSION_1_2,
				"Selected device should support at least Vulkan 1.2",
			)
			found := false
			for &ext in physical_device.available_extensions {
				if string(cstring(&ext.extensionName[0])) == "VK_KHR_swapchain" {
					found = true
					break
				}
			}
			testing.expect(t, found, "Selected device should support VK_KHR_swapchain")
			idx := vkb.get_separate_queue_index(
				physical_device.queue_families,
				{.COMPUTE},
				{.TRANSFER},
			)
			testing.expect(
				t,
				idx != vk.QUEUE_FAMILY_IGNORED,
				"Selected device should have a separate compute queue",
			)
		}
	}

	// Test case 10: No suitable device (unrealistic requirements)
	case_10: {
		selector, ok := vkb.init_physical_device_selector(instance)
		if !testing.expect(t, ok, "Failed to initialize physical device selector") {
			return
		}
		defer vkb.destroy_physical_device_selector(&selector)

		// Require an unrealistic API version
		vkb.selector_set_minimum_version(&selector, vk.MAKE_VERSION(99, 0, 0))

		physical_device, select_ok := vkb.select_physical_device(&selector)
		testing.expect(t, !select_ok, "Selection should fail with unrealistic version requirement")
		defer if select_ok {vkb.destroy_physical_device(physical_device)}

		testing.expect(t, physical_device == nil, "No physical device should be returned")
	}
}
