package vkb_test

import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

@(test)
device_features_support :: proc(t: ^testing.T) {
	{
		// Create requested and supported feature structs
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Set some features as requested
		requested.robustBufferAccess = true
		requested.fullDrawIndexUint32 = true

		// Set all features as supported
		supported.robustBufferAccess = true
		supported.fullDrawIndexUint32 = true
		supported.multiDrawIndirect = true

		// Test with empty extension arrays
		result := vkb.check_device_features_support(requested, supported, nil, nil)

		testing.expect(t, result, "Features should be supported")
	}

	{
		// Create requested and supported feature structs
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Request a feature that is not supported
		requested.robustBufferAccess = true
		requested.fullDrawIndexUint32 = true

		// Support only one of the requested features
		supported.robustBufferAccess = true
		supported.fullDrawIndexUint32 = false

		// Test with empty extension arrays
		result := vkb.check_device_features_support(requested, supported, nil, nil)

		testing.expect(t, !result, "Mismatched features should not be supported")
	}

	{
		// Basic features that all match
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Create extension features
		extension_requested: [2]vkb.Generic_Feature
		extension_supported: [2]vkb.Generic_Feature

		// Setup first extension feature - Vulkan 1.1 Features
		extension_requested[0].type = vk.PhysicalDeviceVulkan11Features
		extension_requested[0].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
		extension_requested[0].p_next.fields[0] = true // e.g., storageBuffer16BitAccess
		extension_requested[0].p_next.fields[1] = true // e.g., multiview

		extension_supported[0].type = vk.PhysicalDeviceVulkan11Features
		extension_supported[0].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
		extension_supported[0].p_next.fields[0] = true
		extension_supported[0].p_next.fields[1] = true

		// Setup second extension feature - Vulkan 1.2 Features
		extension_requested[1].type = vk.PhysicalDeviceVulkan12Features
		extension_requested[1].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
		extension_requested[1].p_next.fields[0] = true // e.g., samplerMirrorClampToEdge

		extension_supported[1].type = vk.PhysicalDeviceVulkan12Features
		extension_supported[1].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
		extension_supported[1].p_next.fields[0] = true
		extension_supported[1].p_next.fields[1] = true // Extra supported feature

		// Test with matching extension arrays
		result := vkb.check_device_features_support(
			requested,
			supported,
			extension_requested[:],
			extension_supported[:],
		)

		testing.expect(t, result, "Extension features should be supported")
	}

	{
		// Basic features that all match
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Create extension features
		extension_requested: [1]vkb.Generic_Feature
		extension_supported: [1]vkb.Generic_Feature

		extension_requested[0].type = vk.PhysicalDeviceVulkan12Features
		extension_requested[0].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2
		extension_requested[0].p_next.fields[5] = true // Request feature at index 5

		extension_supported[0].type = vk.PhysicalDeviceVulkan12Features
		extension_supported[0].p_next.sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2
		// Feature at index 5 is not supported

		// Test with unsupported extension features
		result := vkb.check_device_features_support(
			requested,
			supported,
			extension_requested[:],
			extension_supported[:],
		)

		testing.expect(t, !result, "Unsupported extension features should not be supported")
	}

	{
		// Basic features that all match
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Create extension features with different lengths
		extension_requested: [2]vkb.Generic_Feature
		extension_supported: [1]vkb.Generic_Feature

		// Setup the extension features
		extension_requested[0].type = vk.PhysicalDeviceVulkan12Features
		extension_requested[1].type = vk.PhysicalDeviceVulkan13Features

		extension_supported[0].type = vk.PhysicalDeviceVulkan12Features

		// Test with mismatched extension array lengths
		result := vkb.check_device_features_support(
			requested,
			supported,
			extension_requested[:],
			extension_supported[:],
		)

		testing.expect(t, !result, "Mismatched extension array lengths should not be supported")
	}

	{
		// Basic features that all match
		requested: vk.PhysicalDeviceFeatures
		supported: vk.PhysicalDeviceFeatures

		// Create empty extension arrays
		extension_requested: []vkb.Generic_Feature
		extension_supported: []vkb.Generic_Feature

		// Test with empty extension arrays
		result := vkb.check_device_features_support(
			requested,
			supported,
			extension_requested[:],
			extension_supported[:],
		)

		testing.expect(t, result, "Empty extension arrays should be supported")
	}
}
