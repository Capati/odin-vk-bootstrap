package vkb_test

// Core
import "base:runtime"
import "core:log"
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import vkb "../"

@test
instance_with_surface :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

    mock.should_save_api_version = true
    mock.instance_api_version = vk.API_VERSION_1_1
    add_extension_properties(&mock.physical_devices_details[0].extensions,
    	vk.KHR_MULTIVIEW_EXTENSION_NAME)
    add_extension_properties(&mock.physical_devices_details[0].extensions,
    	vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME)
    add_extension_properties(&mock.physical_devices_details[0].extensions,
    	vk.EXT_ROBUSTNESS_2_EXTENSION_NAME)

    basic_surface_details := create_basic_surface_details()
    surface := vk_mock_get_new_surface(basic_surface_details)

    instance_builder := vkb.create_instance_builder()
    defer vkb.destroy_instance_builder(instance_builder)

    vkb.instance_builder_require_api_version(instance_builder, 1, 1, 0)
    vkb.instance_builder_use_default_debug_messenger(instance_builder)

    vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder)
	if !testing.expect(t, vkb_instance_err == nil, "Expected vkb_instance_err to be nil") {
			log.errorf("%#v", vkb_instance_err)
			return
	}
	defer vkb.destroy_instance(vkb_instance)

	{
		selector := vkb.create_physical_device_selector(vkb_instance)
		defer vkb.destroy_physical_device_selector(selector)

		vkb.physical_device_selector_set_surface(selector, surface)

		vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
		if !testing.expect(t, vkb_physical_device_err == nil, "Expected vkb_physical_device_err to be nil") {
			log.errorf("%#v", vkb_physical_device_err)
			return
		}
		defer vkb.destroy_physical_device(vkb_physical_device)

		device_builder := vkb.create_device_builder(vkb_physical_device)
		defer vkb.destroy_device_builder(device_builder)

		vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
		if !testing.expect(t, vkb_device_err == nil, "Expected vkb_device_err to be nil") {
			log.errorf("%#v", vkb_device_err)
			return
		}
		defer vkb.destroy_device(vkb_device)

        // possible swapchain creation...
	}

	{
		selector := vkb.create_physical_device_selector(vkb_instance)
		defer vkb.destroy_physical_device_selector(selector)

		vkb.physical_device_selector_set_surface(selector, surface)
		vkb.physical_device_selector_add_required_extension(selector, vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME)
		vkb.physical_device_selector_set_minimum_version(selector, 1, 0)

		vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
		if !testing.expect(t, vkb_physical_device_err == nil, "Expected vkb_physical_device_err to be nil") {
			log.errorf("%#v", vkb_physical_device_err)
			return
		}
		defer vkb.destroy_physical_device(vkb_physical_device)

		if !testing.expect(t, vkb.physical_device_is_extension_present(
			vkb_physical_device, vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME)) { return }
		if !testing.expect(t, !vkb.physical_device_is_extension_present(
			vkb_physical_device, vk.KHR_16BIT_STORAGE_EXTENSION_NAME)) { return }

		if !testing.expect(t, vkb.physical_device_enable_extension_if_present(
			vkb_physical_device, vk.EXT_ROBUSTNESS_2_EXTENSION_NAME)) { return }
		if !testing.expect(t, !vkb.physical_device_enable_extension_if_present(
			vkb_physical_device, vk.KHR_16BIT_STORAGE_EXTENSION_NAME)) { return }

		extension_set_1 := []string{
			vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME,
            vk.EXT_ROBUSTNESS_2_EXTENSION_NAME }
        extension_set_2 := []string{
        	vk.KHR_16BIT_STORAGE_EXTENSION_NAME,
            vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME }
        if !testing.expect(t, vkb.physical_device_enable_extensions_if_present(
			vkb_physical_device, extension_set_1)) { return }
        if !testing.expect(t, !vkb.physical_device_enable_extensions_if_present(
			vkb_physical_device, extension_set_2)) { return }

        device_builder := vkb.create_device_builder(vkb_physical_device)
		defer vkb.destroy_device_builder(device_builder)

        vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
		if !testing.expect(t, vkb_device_err == nil, "Expected vkb_device_err to be nil") {
			log.errorf("%#v", vkb_device_err)
			return
		}
		defer vkb.destroy_device(vkb_device)
	}

	{
		instance_builder1 := vkb.create_instance_builder()
	    defer vkb.destroy_instance_builder(instance_builder1)
	    vkb.instance_builder_use_default_debug_messenger(instance_builder1)

	    vkb_instance1, vkb_instance1_err := vkb.instance_builder_build(instance_builder1)
		if !testing.expect(t, vkb_instance1_err == nil, "Expected vkb_instance1_err to be nil") {
				log.errorf("%#v", vkb_instance1_err)
				return
		}
		defer vkb.destroy_instance(vkb_instance1)

	    instance_builder2 := vkb.create_instance_builder()
	    defer vkb.destroy_instance_builder(instance_builder2)
	    vkb.instance_builder_use_default_debug_messenger(instance_builder2)

	    vkb_instance2, vkb_instance2_err := vkb.instance_builder_build(instance_builder2)
		if !testing.expect(t, vkb_instance2_err == nil, "Expected vkb_instance2_err to be nil") {
				log.errorf("%#v", vkb_instance2_err)
				return
		}
		defer vkb.destroy_instance(vkb_instance2)
	}
}

@test
instance_configuration :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	{
		builder := vkb.create_instance_builder()
	    defer vkb.destroy_instance_builder(builder)
	    vkb.instance_builder_use_default_debug_messenger(builder)

	    vkb.instance_builder_request_validation_layers(builder)
	    vkb.instance_builder_set_app_name(builder, "test app")
	    vkb.instance_builder_set_app_version(builder, 1, 0, 0)
	    vkb.instance_builder_set_engine_name(builder, "engine_name")
	    vkb.instance_builder_set_engine_version(builder, 9, 9, 9)
	    vkb.instance_builder_set_debug_callback(builder, proc "system" (
			messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
			messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
			pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
			pUserData: rawptr,
		) -> b32 {
			context = runtime.default_context()
            log.errorf("[%s: %s](user defined)\n%s",
            	messageSeverity, messageTypes, pCallbackData.pMessage)
			return false
		})

		vkb_instance, vkb_instance_err := vkb.instance_builder_build(builder)
		if !testing.expect(t, vkb_instance_err == nil, "Expected vkb_instance_err to be nil") {
				log.errorf("%#v", vkb_instance_err)
				return
		}
		defer vkb.destroy_instance(vkb_instance)
	}

	{
		builder := vkb.create_instance_builder()
	    defer vkb.destroy_instance_builder(builder)
	    vkb.instance_builder_use_default_debug_messenger(builder)

	    vkb.instance_builder_request_validation_layers(builder)
	    vkb.instance_builder_require_api_version(builder, 1, 0, 34)
	    vkb.instance_builder_use_default_debug_messenger(builder)
	    vkb.instance_builder_add_validation_feature_enable(builder, .GPU_ASSISTED)
	    vkb.instance_builder_add_validation_feature_disable(builder, .OBJECT_LIFETIMES)
	    vkb.instance_builder_add_validation_disable(builder, .SHADERS)

	    vkb_instance, vkb_instance_err := vkb.instance_builder_build(builder)
		if !testing.expect(t, vkb_instance_err == nil, "Expected vkb_instance_err to be nil") {
				log.errorf("%#v", vkb_instance_err)
				return
		}
		defer vkb.destroy_instance(vkb_instance)
	}
}

@test
headless_vulkan :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	{
	    vkb_instance, vkb_instance_ok := get_headless_instance(t)
	    if !vkb_instance_ok { return }
		defer vkb.destroy_instance(vkb_instance)

		selector := vkb.create_physical_device_selector(vkb_instance)
		defer vkb.destroy_physical_device_selector(selector)

		vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
		if !testing.expect(t, vkb_physical_device_err == nil, "Expected vkb_physical_device_err to be nil") {
			log.errorf("%#v", vkb_physical_device_err)
			return
		}
		defer vkb.destroy_physical_device(vkb_physical_device)

		device_builder := vkb.create_device_builder(vkb_physical_device)
		defer vkb.destroy_device_builder(device_builder)

        vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
		if !testing.expect(t, vkb_device_err == nil, "Expected vkb_device_err to be nil") {
			log.errorf("%#v", vkb_device_err)
			return
		}
		defer vkb.destroy_device(vkb_device)
	}
}

@test
device_configuration :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	vkb_instance, vkb_instance_ok := get_instance(t, 1)
    if !vkb_instance_ok { return }
	defer vkb.destroy_instance(vkb_instance)

    basic_surface_details := create_basic_surface_details()
    surface := vk_mock_get_new_surface(basic_surface_details)

    selector := vkb.create_physical_device_selector(vkb_instance)
	defer vkb.destroy_physical_device_selector(selector)

	vkb.physical_device_selector_set_minimum_version(selector, 1, 1)
	vkb.physical_device_selector_set_surface(selector, surface)

	vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
	if !testing.expect(t, vkb_physical_device_err == nil, "Expected vkb_physical_device_err to be nil") {
		log.errorf("%#v", vkb_physical_device_err)
		return
	}
	defer vkb.destroy_physical_device(vkb_physical_device)

	// Custom queue setup
	{
		queue_descriptions: [dynamic]vkb.Custom_Queue_Description
		defer delete(queue_descriptions)

		queue_families := vkb.physical_device_get_queue_families(vkb_physical_device)

		for &family, i in queue_families {
			if .GRAPHICS in family.queueFlags {
				priorities := make([]f32, family.queueCount)
				for &p in priorities { p = 1.0 }

				append(&queue_descriptions, vkb.Custom_Queue_Description{
					index = u32(i),
					priorities = priorities,
				})
			}
		}

		if vkb.physical_device_has_dedicated_compute_queue(vkb_physical_device) {
			for &family, i in queue_families {
				if .COMPUTE in family.queueFlags &&
				   .GRAPHICS not_in family.queueFlags &&
				   .TRANSFER not_in family.queueFlags {
					priorities := make([]f32, family.queueCount)
					for &p in priorities { p = 1.0 }

					append(&queue_descriptions, vkb.Custom_Queue_Description{
						index = u32(i),
						priorities = priorities,
					})
				}
			}
		} else if vkb.physical_device_has_separate_compute_queue(vkb_physical_device) {
			for &family, i in queue_families {
				if .COMPUTE in family.queueFlags &&
				   .GRAPHICS not_in family.queueFlags {
					priorities := make([]f32, family.queueCount)
					for &p in priorities { p = 1.0 }

					append(&queue_descriptions, vkb.Custom_Queue_Description{
						index = u32(i),
						priorities = priorities,
					})
				}
			}
		}

		device_builder := vkb.create_device_builder(vkb_physical_device)
		defer vkb.destroy_device_builder(device_builder)

		vkb.device_builder_custom_queue_setup(device_builder, queue_descriptions[:])

		device, device_err := vkb.device_builder_build(device_builder)
		if !testing.expect(t, device_err == nil, "Expected device_err to be nil") {
			log.errorf("%#v", device_err)
			return
		}
		defer vkb.destroy_device(device)
	}

	// VkPhysicalDeviceFeatures2 in pNext Chain
	{
		shader_draw_features := vk.PhysicalDeviceShaderDrawParameterFeatures{
			sType = .PHYSICAL_DEVICE_SHADER_DRAW_PARAMETER_FEATURES,
		}

		device_builder := vkb.create_device_builder(vkb_physical_device)
		defer vkb.destroy_device_builder(device_builder)

		vkb.device_builder_add_pnext(device_builder, &shader_draw_features)

		device, device_err := vkb.device_builder_build(device_builder)
		if !testing.expect(t, device_err == nil, "Expected device_err to be nil") {
			log.errorf("%#v", device_err)
			return
		}
		defer vkb.destroy_device(device)
	}
}

@test
physical_device_version :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	mock.instance_api_version = vk.API_VERSION_1_4
	mock.physical_devices_details[0].properties.apiVersion = vk.API_VERSION_1_1
	mock.physical_devices_details[0].properties.deviceID = 1

	vk_mock_add_basic_physical_device()
	mock.physical_devices_details[1].properties.apiVersion = vk.API_VERSION_1_4
	mock.physical_devices_details[1].properties.deviceID = 4

	instance_builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(instance_builder)

	vkb.instance_builder_set_headless(instance_builder)
	vkb.instance_builder_require_api_version(instance_builder, 1, 4, 0)

	instance, instance_err := vkb.instance_builder_build(instance_builder)
	if !testing.expect(t, instance_err == nil, "Expected instance_err to be nil") {
		log.errorf("%#v", instance_err)
		return
	}
	defer vkb.destroy_instance(instance)

	// Test 1.1 version selection
	{
		phys_device_selector := vkb.create_physical_device_selector(instance)
		defer vkb.destroy_physical_device_selector(phys_device_selector)

		vkb.physical_device_selector_set_minimum_version(phys_device_selector, 1, 1)

		phys_device_1_1, err := vkb.physical_device_selector_select(phys_device_selector)
		if !testing.expect(t, err == nil, "Expected err to be nil for 1.1") {
			log.errorf("%#v", err)
			return
		}

		if !testing.expect_value(t, phys_device_1_1.properties.deviceID, 1) { return }
	}

	// Test 1.4 version selection
	{
		phys_device_selector := vkb.create_physical_device_selector(instance)
		defer vkb.destroy_physical_device_selector(phys_device_selector)

		vkb.physical_device_selector_set_minimum_version(phys_device_selector, 1, 4)

		phys_device_1_4, err := vkb.physical_device_selector_select(phys_device_selector)
		if !testing.expect(t, err == nil, "Expected err to be nil for 1.4") {
			log.errorf("%#v", err)
			return
		}

		testing.expect_value(t, phys_device_1_4.properties.deviceID, 4)
	}
}

@test
physical_device_version_lower_than_instance :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	mock.instance_api_version = vk.API_VERSION_1_1
	mock.physical_devices_details[0].properties.apiVersion = vk.API_VERSION_1_1
	mock.physical_devices_details[0].properties.deviceID = 1

	vk_mock_add_basic_physical_device()
	mock.physical_devices_details[1].properties.apiVersion = vk.API_VERSION_1_4
	mock.physical_devices_details[1].properties.deviceID = 4

	// Build instance with minimum version
	instance_builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(instance_builder)

	vkb.instance_builder_set_headless(instance_builder)
	vkb.instance_builder_require_api_version(instance_builder, 1, 4, 0)
	vkb.instance_builder_set_minimum_instance_version(instance_builder, 1, 1, 0)

	instance, instance_err := vkb.instance_builder_build(instance_builder)
	if !testing.expect(t, instance_err == nil, "Expected instance_err to be nil") {
		log.errorf("%#v", instance_err)
		return
	}
	defer vkb.destroy_instance(instance)

	// Test 1.1 version selection
	{
		phys_device_selector := vkb.create_physical_device_selector(instance)
		defer vkb.destroy_physical_device_selector(phys_device_selector)

		vkb.physical_device_selector_set_minimum_version(phys_device_selector, 1, 1)

		phys_device_1_1, err := vkb.physical_device_selector_select(phys_device_selector)
		if !testing.expect(t, err == nil, "Expected err to be nil for 1.1") {
			log.errorf("%#v", err)
			return
		}

		testing.expect_value(t, phys_device_1_1.properties.deviceID, 1)
	}

	// Test 1.4 version selection
	{
		phys_device_selector := vkb.create_physical_device_selector(instance)
		defer vkb.destroy_physical_device_selector(phys_device_selector)

		vkb.physical_device_selector_set_minimum_version(phys_device_selector, 1, 4)

		phys_device_1_4, err := vkb.physical_device_selector_select(phys_device_selector)
		if !testing.expect(t, err == nil, "Expected err to be nil for 1.4") {
			log.errorf("%#v", err)
			return
		}

		testing.expect_value(t, phys_device_1_4.properties.deviceID, 4)
	}
}

@test
select_all_physical_devices :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	mock.instance_api_version = vk.API_VERSION_1_1
	mock.physical_devices_details[0].properties.apiVersion = vk.API_VERSION_1_1

	message := "mocking_gpus_for_fun_and_profit"
	copy(mock.physical_devices_details[0].properties.deviceName[:], transmute([]byte)message)

	instance, instance_err := get_instance(t, 1)
	if !instance_err { return }
	defer vkb.destroy_instance(instance)

	basic_surface_details := create_basic_surface_details()
    surface := vk_mock_get_new_surface(basic_surface_details)

    // Select all devices
	phys_device_selector := vkb.create_physical_device_selector_with_surface(instance, surface)
	defer vkb.destroy_physical_device_selector(phys_device_selector)

	phys_devices, devices_err := vkb.physical_device_selector_select_devices(phys_device_selector)
	if !testing.expect(t, devices_err == nil, "Expected devices_err to be nil") {
		log.errorf("%#v", devices_err)
		return
	}
	defer delete(phys_devices)

	if !testing.expect(t, len(phys_devices) > 0,
		"Expected device list to be non-empty") { return }

	if !testing.expect(t, len(phys_devices[0].name) > 0,
		"Expected device name to be non-empty") { return }

	if !testing.expect(t, phys_devices[0].name == message,
		"Expected device name to be equal to default") { return }

	phys_device_names, names_err := vkb.physical_device_selector_select_device_names(phys_device_selector)
	if !testing.expect(t, names_err == nil, "Expected names_err to be nil") {
		log.errorf("%#v", names_err)
		return
	}
	defer delete(phys_device_names)

	if !testing.expect(t, len(phys_device_names) > 0,
		"Expected device names list to be non-empty") { return }

	if !testing.expect(t, len(phys_device_names[0]) > 0,
		"Expected device name to be non-empty") { return }

	if !testing.expect(t, phys_devices[0].name == message,
		"Expected device name to be equal to default") { return }

	device_builder := vkb.create_device_builder(phys_devices[0])
	defer vkb.destroy_device_builder(device_builder)

	device, device_err := vkb.device_builder_build(device_builder)
	if !testing.expect(t, device_err == nil, "Expected device_err to be nil") {
		log.errorf("%#v", device_err)
		return
	}
	defer vkb.destroy_device(device)
}

@test
select_physical_devices_by_type :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	// Add 4 more physical devices (1 form init, total 5)
	for _ in 0..< 4 {
		vk_mock_add_basic_physical_device()
	}

	// Set device types
	for i in 0..< 5 {
		mock.physical_devices_details[i].properties.deviceID = u32(i)
		mock.physical_devices_details[i].properties.deviceType = vk.PhysicalDeviceType(i)
	}

	instance, instance_err := get_instance(t, 1)
	if !instance_err { return }
	defer vkb.destroy_instance(instance)

	basic_surface_details := create_basic_surface_details()
    surface := vk_mock_get_new_surface(basic_surface_details)

    // Test each device type preference
	for i in 0..<5 {
		// Test single device selection
		{
			phys_device_selector := vkb.create_physical_device_selector_with_surface(instance, surface)
			defer vkb.destroy_physical_device_selector(phys_device_selector)

			vkb.physical_device_selector_prefer_gpu_device_type(phys_device_selector, vkb.Preferred_Device_Type(i))

			phys_dev, err := vkb.physical_device_selector_select(phys_device_selector)
			if !testing.expect(t, err == nil, "Expected err to be nil") {
				log.errorf("%#v", err)
				continue
			}

			if !testing.expect_value(t, phys_dev.properties.deviceID, u32(i)) { return }
		}

		// Test multiple device selection
		{
			phys_device_selector := vkb.create_physical_device_selector_with_surface(instance, surface)
			defer vkb.destroy_physical_device_selector(phys_device_selector)

			vkb.physical_device_selector_prefer_gpu_device_type(phys_device_selector, vkb.Preferred_Device_Type(i))

			vector, err := vkb.physical_device_selector_select_devices(phys_device_selector)
			if !testing.expect(t, err == nil, "Expected err to be nil") {
				log.errorf("%#v", err)
				continue
			}
			defer delete(vector)

			if !testing.expect_value(t, len(vector), 5) { return }
			if !testing.expect_value(t, vector[0].properties.deviceID, u32(i)) { return }
		}
	}
}

@test
loading_dispatch_table :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	instance, instance_err := get_headless_instance(t, 1)
	if !instance_err { return }
	defer vkb.destroy_instance(instance)

	// Select first device unconditionally
	phys_device_selector := vkb.create_physical_device_selector(instance)
	defer vkb.destroy_physical_device_selector(phys_device_selector)

	vkb.physical_device_selector_select_first_device_unconditionally(phys_device_selector)

	phys_dev, phys_err := vkb.physical_device_selector_select(phys_device_selector)
	if !testing.expect(t, phys_err == nil, "Expected phys_err to be nil") {
		log.errorf("%#v", phys_err)
		return
	}

	// Build device
	device_builder := vkb.create_device_builder(phys_dev)
	defer vkb.destroy_device_builder(device_builder)

	device, device_err := vkb.device_builder_build(device_builder)
	if !testing.expect(t, device_err == nil, "Expected device_err to be nil") {
		log.errorf("%#v", device_err)
		return
	}
	defer vkb.destroy_device(device)

	// Create a fence to test dispatch table
	info := vk.FenceCreateInfo{
		sType = .FENCE_CREATE_INFO,
	}

	fence: vk.Fence
	vk.CreateFence(device.device, &info, nil, &fence)
	testing.expect(t, fence != 0, "Expected fence to be non-nil")
	defer vk.DestroyFence(device.device, fence, nil)
}

@test
system_info_check_instance_api_version :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	vk_mock_init()

	mock.instance_api_version = vk.API_VERSION_1_2

	system_info, info_err := vkb.get_system_info()
	if !testing.expect(t, info_err == nil, "Expected info_err to be nil") {
		log.errorf("%#v", info_err)
		return
	}

	// Test version availability
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, vk.MAKE_VERSION(1, 0, 0)),
		"Expected 1.0.0 to be available") { return }
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, vk.MAKE_VERSION(1, 1, 0)),
		"Expected 1.1.0 to be available") { return }
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, vk.MAKE_VERSION(1, 2, 0)),
		"Expected 1.2.0 to be available") { return }
	if !testing.expect(t, !vkb.system_info_is_instance_version_available(system_info, vk.MAKE_VERSION(1, 3, 0)),
		"Expected 1.3.0 to NOT be available") { return }
	if !testing.expect(t, !vkb.system_info_is_instance_version_available(system_info, vk.MAKE_VERSION(1, 4, 0)),
		"Expected 1.4.0 to NOT be available") { return }

	// Test with major/minor
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, 1, 0),
		"Expected 1.0 to be available") { return }
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, 1, 1),
		"Expected 1.1 to be available") { return }
	if !testing.expect(t, vkb.system_info_is_instance_version_available(system_info, 1, 2),
		"Expected 1.2 to be available") { return }
	if !testing.expect(t, !vkb.system_info_is_instance_version_available(system_info, 1, 3),
		"Expected 1.3 to NOT be available") { return }
	if !testing.expect(t, !vkb.system_info_is_instance_version_available(system_info, 1, 4),
		"Expected 1.4 to NOT be available") { return }
}
