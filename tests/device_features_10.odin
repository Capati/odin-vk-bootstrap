package vkb_test

// Core
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

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
