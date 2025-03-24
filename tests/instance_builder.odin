package vkb_test

import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

@(test)
test_instance_builder :: proc(t: ^testing.T) {
	// Test case 1: Basic instance creation with defaults
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		testing.expect(t, build_ok, "Expected successful instance creation with defaults")
		testing.expect(t, instance != nil, "Instance should not be nil")
		testing.expect(t, instance.handle != nil, "Instance handle should not be nil")
		testing.expect(
			t,
			instance.api_version == vk.API_VERSION_1_0,
			"Default API version should be 1.0",
		)
	}

	// Test case 2: Instance with custom app and engine info
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_set_app_name(&builder, "TestApp")
		vkb.instance_set_engine_name(&builder, "TestEngine")
		vkb.instance_set_app_versioned(&builder, 1, 2, 3)
		vkb.instance_set_engine_versioned(&builder, 4, 5, 6)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		testing.expect(t, build_ok, "Expected successful instance creation with custom info")
		testing.expect(
			t,
			instance.api_version == vk.API_VERSION_1_0,
			"API version should still be 1.0",
		)
	}

	// Test case 3: Instance with required API version
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_require_api_versioned(&builder, 1, 1, 0)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		if build_ok {
			testing.expect(
				t,
				instance.api_version >= vk.API_VERSION_1_1,
				"API version should be at least 1.1",
			)
		}
	}

	// Test case 4: Instance with validation layers requested
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_request_validation_layers(&builder)
		vkb.instance_use_default_debug_messenger(&builder)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		testing.expect(t, build_ok, "Expected successful instance creation with validation")
		if build_ok && builder.info.validation_layers_available {
			testing.expect(
				t,
				instance.debug_messenger != 0,
				"Debug messenger should be created when validation is available",
			)
		}
	}

	// Test case 5: Headless instance
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_set_headless(&builder)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		testing.expect(t, build_ok, "Expected successful headless instance creation")
		testing.expect(t, instance.headless, "Instance should be marked as headless")
	}

	// Test case 6: Instance with custom extension
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_enable_extension(&builder, vk.KHR_SURFACE_EXTENSION_NAME)

		instance, build_ok := vkb.build_instance(&builder)
		testing.expect(t, build_ok, "Failed to build an instance")
		defer vkb.destroy_instance(instance)

		testing.expect(t, build_ok, "Expected successful instance creation with surface extension")
	}

	// Test case 7: Instance with unavailable extension (should fail)
	{
		builder, ok := vkb.init_instance_builder()
		testing.expect(t, ok, "Failed to initialize instance builder")
		defer vkb.destroy_instance_builder(&builder)

		vkb.instance_enable_extension(&builder, "VK_NON_EXISTENT_EXTENSION")

		_, build_ok := vkb.build_instance(&builder)

		testing.expect(
			t,
			build_ok == false,
			"Expected failure when requiring non-existent extension",
		)
	}
}
