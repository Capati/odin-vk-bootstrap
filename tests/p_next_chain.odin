package vkb_test

// Core
import "base:runtime"
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

@(test)
test_p_next_chain :: proc(t: ^testing.T) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// Test case 1: Empty chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure, ta)

		vkb.setup_p_next_chain(&info, &chain)

		testing.expect(t, info.pNext == nil, "Expected pNext to be nil with empty chain")
	}

	// Test case 2: Single structure in chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure, ta)

		features := vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
		}
		append(&chain, cast(^vk.BaseOutStructure)&features)

		vkb.setup_p_next_chain(&info, &chain)

		testing.expect(
			t,
			info.pNext == cast(rawptr)&features,
			"Expected pNext to point to single structure",
		)
		testing.expect(t, features.pNext == nil, "Expected single structure's pNext to be nil")
	}

	// Test case 3: Two structures in chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure, ta)

		features := vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
		}
		checks := vk.ValidationFlagsEXT {
			sType = .VALIDATION_FLAGS_EXT,
		}

		append(&chain, cast(^vk.BaseOutStructure)&features)
		append(&chain, cast(^vk.BaseOutStructure)&checks)

		vkb.setup_p_next_chain(&info, &chain)

		testing.expect(
			t,
			info.pNext == cast(rawptr)&features,
			"Expected pNext to point to first structure",
		)
		testing.expect(
			t,
			features.pNext == cast(rawptr)&checks,
			"Expected first structure's pNext to point to second structure",
		)
		testing.expect(t, checks.pNext == nil, "Expected last structure's pNext to be nil")
	}

	// Test case 4: Multiple structures in chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure, ta)

		features := vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
		}
		checks := vk.ValidationFlagsEXT {
			sType = .VALIDATION_FLAGS_EXT,
		}
		messenger := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		}

		append(&chain, cast(^vk.BaseOutStructure)&features)
		append(&chain, cast(^vk.BaseOutStructure)&checks)
		append(&chain, cast(^vk.BaseOutStructure)&messenger)

		vkb.setup_p_next_chain(&info, &chain)

		testing.expect(
			t,
			info.pNext == cast(rawptr)&features,
			"Expected pNext to point to first structure",
		)
		testing.expect(
			t,
			features.pNext == cast(rawptr)&checks,
			"Expected first structure's pNext to point to second structure",
		)
		testing.expect(
			t,
			checks.pNext == cast(rawptr)&messenger,
			"Expected second structure's pNext to point to third structure",
		)
		testing.expect(t, messenger.pNext == nil, "Expected last structure's pNext to be nil")
	}

	// Test case 5: Different base structure type
	{
		device_info := vk.DeviceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure, ta)

		features := vk.PhysicalDeviceFeatures2 {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
		}
		append(&chain, cast(^vk.BaseOutStructure)&features)

		vkb.setup_p_next_chain(&device_info, &chain)

		testing.expect(
			t,
			device_info.pNext == cast(rawptr)&features,
			"Expected pNext to point to single structure with different base type",
		)
		testing.expect(t, features.pNext == nil, "Expected single structure's pNext to be nil")
	}
}
