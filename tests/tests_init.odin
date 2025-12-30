package vkb_test

// Core
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import vkb "../"

@(test)
test_pnext_chain :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	// Test case 1: Empty chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure)

		vkb.setup_pnext_chain(&info, &chain)

		testing.expect(t, info.pNext == nil, "Expected pNext to be nil with empty chain")
	}

	// Test case 2: Single structure in chain
	{
		info := vk.InstanceCreateInfo{}
		chain := make([dynamic]^vk.BaseOutStructure)

		features := vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
		}
		append(&chain, cast(^vk.BaseOutStructure)&features)

		vkb.setup_pnext_chain(&info, &chain)

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
		chain := make([dynamic]^vk.BaseOutStructure)

		features := vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
		}
		checks := vk.ValidationFlagsEXT {
			sType = .VALIDATION_FLAGS_EXT,
		}

		append(&chain, cast(^vk.BaseOutStructure)&features)
		append(&chain, cast(^vk.BaseOutStructure)&checks)

		vkb.setup_pnext_chain(&info, &chain)

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
		chain := make([dynamic]^vk.BaseOutStructure)

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

		vkb.setup_pnext_chain(&info, &chain)

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
		chain := make([dynamic]^vk.BaseOutStructure)

		features := vk.PhysicalDeviceFeatures2 {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
		}
		append(&chain, cast(^vk.BaseOutStructure)&features)

		vkb.setup_pnext_chain(&device_info, &chain)

		testing.expect(
			t,
			device_info.pNext == cast(rawptr)&features,
			"Expected pNext to point to single structure with different base type",
		)
		testing.expect(t, features.pNext == nil, "Expected single structure's pNext to be nil")
	}
}

@(test)
test_queue_selection :: proc(t: ^testing.T) {
	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.TRANSFER}},
		}

		index := vkb.get_first_queue_index(families, {.GRAPHICS})
		testing.expect(t, index == 0, "Expected first queue with graphics support (index 0)")
	}

	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.TRANSFER}},
			{queueFlags = {.COMPUTE}},
		}

		index := vkb.get_first_queue_index(families, {.GRAPHICS})
		testing.expect(
			t,
			index == vk.QUEUE_FAMILY_IGNORED,
			"Expected QUEUE_FAMILY_IGNORED when no graphics queue found",
		)
	}

	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.COMPUTE}},
			{queueFlags = {.TRANSFER}},
		}

		index := vkb.get_separate_queue_index(families, {.COMPUTE}, {.TRANSFER})
		testing.expect(t, index == 1, "Expected separate compute queue without transfer (index 1)")
	}

	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.COMPUTE, .TRANSFER}},
		}

		index := vkb.get_separate_queue_index(families, {.COMPUTE}, {.TRANSFER})
		testing.expect(
			t,
			index == 1,
			"Expected fallback to compute queue with transfer when no better option (index 1)",
		)
	}

	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.COMPUTE}},
			{queueFlags = {.COMPUTE, .TRANSFER}},
		}

		index := vkb.get_dedicated_queue_index(families, {.COMPUTE}, {.TRANSFER})
		testing.expect(
			t,
			index == 1,
			"Expected dedicated compute queue without other capabilities (index 1)",
		)
	}

	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.COMPUTE, .TRANSFER}},
		}

		index := vkb.get_dedicated_queue_index(families, {.COMPUTE}, {.TRANSFER})
		testing.expect(
			t,
			index == vk.QUEUE_FAMILY_IGNORED,
			"Expected QUEUE_FAMILY_IGNORED when no dedicated compute queue found",
		)
	}

	{
		families := []vk.QueueFamilyProperties{}

		first_idx := vkb.get_first_queue_index(families, {.GRAPHICS})
		separate_idx := vkb.get_separate_queue_index(families, {.COMPUTE}, {.TRANSFER})
		dedicated_idx := vkb.get_dedicated_queue_index(families, {.COMPUTE}, {.TRANSFER})

		testing.expect(
			t,
			first_idx == vk.QUEUE_FAMILY_IGNORED,
			"get_first_queue_index should return IGNORED for empty array",
		)
		testing.expect(
			t,
			separate_idx == vk.QUEUE_FAMILY_IGNORED,
			"get_separate_queue_index should return IGNORED for empty array",
		)
		testing.expect(
			t,
			dedicated_idx == vk.QUEUE_FAMILY_IGNORED,
			"get_dedicated_queue_index should return IGNORED for empty array",
		)
	}
}

@(test)
test_check_features_10 :: proc(t: ^testing.T) {
	// Test case 1: Nothing requested
	{
		// Creating empty features (all false)
		requested := vk.PhysicalDeviceFeatures{}
		supported := vk.PhysicalDeviceFeatures{}

		result := vkb.check_features_10(requested, supported)
		testing.expect(t, result == true, "Expected true when nothing is requested")
	}

	// Test case 2: All requested features are supported
	{
		requested := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
		}

		supported := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
			robustBufferAccess = true, // Additional supported feature (not requested)
		}

		result := vkb.check_features_10(requested, supported)
		testing.expect(
			t,
			result == true,
			"Expected true when all requested features are supported",
		)
	}

	// Test case 3: Some requested features are not supported
	{
		requested := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
			multiViewport      = true, // This one is not supported
		}

		supported := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
		}

		result := vkb.check_features_10(requested, supported)
		testing.expect(
			t,
			result == false,
			"Expected false when some requested features are not supported",
		)
	}

	// Test case 4: All requested features are not supported
	{
		requested := vk.PhysicalDeviceFeatures {
			geometryShader     = true,
			tessellationShader = true,
		}

		// All false by default
		supported := vk.PhysicalDeviceFeatures{}

		result := vkb.check_features_10(requested, supported)
		testing.expect(
			t,
			result == false,
			"Expected false when none of the requested features are supported",
		)
	}

	// Test case 5: Mixed features (some true, some false)
	{
		requested := vk.PhysicalDeviceFeatures {
			geometryShader     = true, // Requested and supported
			tessellationShader = false, // Not requested
			multiViewport      = true, // Requested but not supported
		}

		supported := vk.PhysicalDeviceFeatures {
			geometryShader     = true, // Supported
			tessellationShader = true, // Supported but not requested
			multiViewport      = false, // Not supported
		}

		result := vkb.check_features_10(requested, supported)
		testing.expect(t, result == false, "Expected false with mixed feature support scenario")
	}

	// Test case 6: Edge case - all features requested and supported
	{
		// Create features with all fields set to true
		requested := vk.PhysicalDeviceFeatures {
			robustBufferAccess                      = true,
			fullDrawIndexUint32                     = true,
			imageCubeArray                          = true,
			independentBlend                        = true,
			geometryShader                          = true,
			tessellationShader                      = true,
			sampleRateShading                       = true,
			dualSrcBlend                            = true,
			logicOp                                 = true,
			multiDrawIndirect                       = true,
			drawIndirectFirstInstance               = true,
			depthClamp                              = true,
			depthBiasClamp                          = true,
			fillModeNonSolid                        = true,
			depthBounds                             = true,
			wideLines                               = true,
			largePoints                             = true,
			alphaToOne                              = true,
			multiViewport                           = true,
			samplerAnisotropy                       = true,
			textureCompressionETC2                  = true,
			textureCompressionASTC_LDR              = true,
			textureCompressionBC                    = true,
			occlusionQueryPrecise                   = true,
			pipelineStatisticsQuery                 = true,
			vertexPipelineStoresAndAtomics          = true,
			fragmentStoresAndAtomics                = true,
			shaderTessellationAndGeometryPointSize  = true,
			shaderImageGatherExtended               = true,
			shaderStorageImageExtendedFormats       = true,
			shaderStorageImageMultisample           = true,
			shaderStorageImageReadWithoutFormat     = true,
			shaderStorageImageWriteWithoutFormat    = true,
			shaderUniformBufferArrayDynamicIndexing = true,
			shaderSampledImageArrayDynamicIndexing  = true,
			shaderStorageBufferArrayDynamicIndexing = true,
			shaderStorageImageArrayDynamicIndexing  = true,
			shaderClipDistance                      = true,
			shaderCullDistance                      = true,
			shaderFloat64                           = true,
			shaderInt64                             = true,
			shaderInt16                             = true,
			shaderResourceResidency                 = true,
			shaderResourceMinLod                    = true,
			sparseBinding                           = true,
			sparseResidencyBuffer                   = true,
			sparseResidencyImage2D                  = true,
			sparseResidencyImage3D                  = true,
			sparseResidency2Samples                 = true,
			sparseResidency4Samples                 = true,
			sparseResidency8Samples                 = true,
			sparseResidency16Samples                = true,
			sparseResidencyAliased                  = true,
			variableMultisampleRate                 = true,
			inheritedQueries                        = true,
		}

		// Same for supported
		supported := requested

		result := vkb.check_features_10(requested, supported)
		testing.expect(
			t,
			result == true,
			"Expected true when all possible features are requested and supported",
		)
	}
}

// Helper procedure to create a test extension property
create_extension_property :: proc(name: string) -> vk.ExtensionProperties {
	ext: vk.ExtensionProperties

	// Copy the name into the extension struct (with null termination)
	bytes_copied := min(len(name), len(ext.extensionName) - 1)
	copy_slice(ext.extensionName[:bytes_copied], transmute([]u8)name[:bytes_copied])
	ext.extensionName[bytes_copied] = 0

	return ext
}

@(test)
test_check_device_extension_support :: proc(t: ^testing.T) {
	// Test case 1: No required extensions
	{
		available := []string {
			"VK_KHR_swapchain", "VK_KHR_surface",
		}
		required := []string{}

		result := vkb.check_device_extension_support(available, required)
		testing.expect(
			t,
			result == true,
			"Expected true when no required extensions are specified",
		)
	}

	// Test case 2: No available extensions
	{
		available := []string{}
		required := []string { "VK_KHR_swapchain" }

		result := vkb.check_device_extension_support(available, required)
		testing.expect(t, result == false, "Expected false when there are no available extensions")
	}

	// Test case 3: All required extensions are available
	{
		available := []string {
			"VK_KHR_swapchain",
			"VK_KHR_surface",
			"VK_EXT_debug_utils",
		}

		required := []string{"VK_KHR_swapchain", "VK_KHR_surface"}
		result := vkb.check_device_extension_support(available, required)
		testing.expect(
			t,
			result,
			"Expected true when all required extensions are available",
		)
	}

	// Test case 4: Some required extensions are missing
	{
		available := []string {
			"VK_KHR_swapchain",
			"VK_KHR_surface",
		}

		required := []string{"VK_KHR_swapchain", "VK_EXT_debug_utils"}
		result := vkb.check_device_extension_support(available, required)
		testing.expect(
			t,
			result == false,
			"Expected false when some required extensions are missing",
		)
	}

	// Test case 5: Edge case - empty extension names
	{
		available := []string {
			"",
			"VK_KHR_surface",
		}

		required := []string{""}
		result := vkb.check_device_extension_support(available, required)
		testing.expect(
			t,
			result == true,
			"Expected true when empty extension name is required and available",
		)
	}
}

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
		extension_requested[0].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
		extension_requested[0].pNext.fields[0] = true // e.g., storageBuffer16BitAccess
		extension_requested[0].pNext.fields[1] = true // e.g., multiview

		extension_supported[0].type = vk.PhysicalDeviceVulkan11Features
		extension_supported[0].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
		extension_supported[0].pNext.fields[0] = true
		extension_supported[0].pNext.fields[1] = true

		// Setup second extension feature - Vulkan 1.2 Features
		extension_requested[1].type = vk.PhysicalDeviceVulkan12Features
		extension_requested[1].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
		extension_requested[1].pNext.fields[0] = true // e.g., samplerMirrorClampToEdge

		extension_supported[1].type = vk.PhysicalDeviceVulkan12Features
		extension_supported[1].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
		extension_supported[1].pNext.fields[0] = true
		extension_supported[1].pNext.fields[1] = true // Extra supported feature

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
		extension_requested[0].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2
		extension_requested[0].pNext.fields[5] = true // Request feature at index 5

		extension_supported[0].type = vk.PhysicalDeviceVulkan12Features
		extension_supported[0].pNext.sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2
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
