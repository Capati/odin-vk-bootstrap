package vk_bootstrap

// Vendor
import vk "vendor:vulkan"

// Finds the queue which is separate from the graphics queue and has the desired flag and
// not the  undesired flag, but will select it if no better options are available compute
// support.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_separate_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
	undesired_flags: vk.QueueFlags,
) -> u32 {
	index := vk.QUEUE_FAMILY_IGNORED

	for f, queue_index in families {
		if (f.queueFlags & desired_flags) != desired_flags {
			continue
		}

		if .GRAPHICS in f.queueFlags {
			continue
		}

		if (f.queueFlags & undesired_flags) == {} {
			return cast(u32)queue_index
		} else {
			index = cast(u32)queue_index
		}
	}

	return index
}

// Finds the first queue which supports only the desired flag (not graphics or transfer).
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_dedicated_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
	undesired_flags: vk.QueueFlags,
) -> u32 {
	for f, queue_index in families {
		if (f.queueFlags & desired_flags) != desired_flags {
			continue
		}

		if .GRAPHICS in f.queueFlags {
			continue
		}

		if (f.queueFlags & undesired_flags) != {} {
			continue
		}

		return cast(u32)queue_index
	}

	return vk.QUEUE_FAMILY_IGNORED
}

// Finds the first queue which supports presenting.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_present_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	vk_physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR = 0,
) -> u32 {
	for _, queue_index in families {
		present_support: b32 = false

		if surface != 0 {
			if vk.GetPhysicalDeviceSurfaceSupportKHR(
				   vk_physical_device,
				   cast(u32)queue_index,
				   surface,
				   &present_support,
			   ) !=
			   .SUCCESS {
				return vk.QUEUE_FAMILY_IGNORED
			}

			if bool(present_support) {
				return cast(u32)queue_index
			}
		}
	}

	return vk.QUEUE_FAMILY_IGNORED
}

@(private)
check_device_extension_support :: proc(
	available_extensions: ^[]vk.ExtensionProperties,
	desired_extensions: []cstring,
	allocator := context.allocator,
) -> (
	[]cstring,
	Error,
) {
	if len(desired_extensions) == 0 {
		return {}, nil
	}

	extensions_to_enable, make_err := make([dynamic]cstring, allocator)
	if make_err != nil do return {}, make_err

	for avail_ext in available_extensions {
		for req_ext in desired_extensions {
			if cstring(&avail_ext.extensionName[0]) == req_ext {
				append(&extensions_to_enable, req_ext)
				break
			}
		}
	}

	return extensions_to_enable[:], nil
}

check_device_features_support :: proc(
	supported: vk.PhysicalDeviceFeatures,
	requested: vk.PhysicalDeviceFeatures,
) -> bool {
	// TODO
	if requested.robustBufferAccess && !supported.robustBufferAccess do return false
	if requested.robustBufferAccess && !supported.robustBufferAccess do return false
	if requested.fullDrawIndexUint32 && !supported.fullDrawIndexUint32 do return false
	if requested.imageCubeArray && !supported.imageCubeArray do return false
	if requested.independentBlend && !supported.independentBlend do return false
	if requested.geometryShader && !supported.geometryShader do return false
	if requested.tessellationShader && !supported.tessellationShader do return false
	if requested.sampleRateShading && !supported.sampleRateShading do return false
	if requested.dualSrcBlend && !supported.dualSrcBlend do return false
	if requested.logicOp && !supported.logicOp do return false
	if requested.multiDrawIndirect && !supported.multiDrawIndirect do return false
	if requested.drawIndirectFirstInstance && !supported.drawIndirectFirstInstance do return false
	if requested.depthClamp && !supported.depthClamp do return false
	if requested.depthBiasClamp && !supported.depthBiasClamp do return false
	if requested.fillModeNonSolid && !supported.fillModeNonSolid do return false
	if requested.depthBounds && !supported.depthBounds do return false
	if requested.wideLines && !supported.wideLines do return false
	if requested.largePoints && !supported.largePoints do return false
	if requested.alphaToOne && !supported.alphaToOne do return false
	if requested.multiViewport && !supported.multiViewport do return false
	if requested.samplerAnisotropy && !supported.samplerAnisotropy do return false
	if requested.textureCompressionETC2 && !supported.textureCompressionETC2 do return false
	if requested.textureCompressionASTC_LDR && !supported.textureCompressionASTC_LDR do return false
	if requested.textureCompressionBC && !supported.textureCompressionBC do return false
	if requested.occlusionQueryPrecise && !supported.occlusionQueryPrecise do return false
	if requested.pipelineStatisticsQuery && !supported.pipelineStatisticsQuery do return false
	if requested.vertexPipelineStoresAndAtomics && !supported.vertexPipelineStoresAndAtomics do return false
	if requested.fragmentStoresAndAtomics && !supported.fragmentStoresAndAtomics do return false
	if requested.shaderTessellationAndGeometryPointSize && !supported.shaderTessellationAndGeometryPointSize do return false
	if requested.shaderImageGatherExtended && !supported.shaderImageGatherExtended do return false
	if requested.shaderStorageImageExtendedFormats && !supported.shaderStorageImageExtendedFormats do return false
	if requested.shaderStorageImageMultisample && !supported.shaderStorageImageMultisample do return false
	if requested.shaderStorageImageReadWithoutFormat && !supported.shaderStorageImageReadWithoutFormat do return false
	if requested.shaderStorageImageWriteWithoutFormat && !supported.shaderStorageImageWriteWithoutFormat do return false
	if requested.shaderUniformBufferArrayDynamicIndexing && !supported.shaderUniformBufferArrayDynamicIndexing do return false
	if requested.shaderSampledImageArrayDynamicIndexing && !supported.shaderSampledImageArrayDynamicIndexing do return false
	if requested.shaderStorageBufferArrayDynamicIndexing && !supported.shaderStorageBufferArrayDynamicIndexing do return false
	if requested.shaderStorageImageArrayDynamicIndexing && !supported.shaderStorageImageArrayDynamicIndexing do return false
	if requested.shaderClipDistance && !supported.shaderClipDistance do return false
	if requested.shaderCullDistance && !supported.shaderCullDistance do return false
	if requested.shaderFloat64 && !supported.shaderFloat64 do return false
	if requested.shaderInt64 && !supported.shaderInt64 do return false
	if requested.shaderInt16 && !supported.shaderInt16 do return false
	if requested.shaderResourceResidency && !supported.shaderResourceResidency do return false
	if requested.shaderResourceMinLod && !supported.shaderResourceMinLod do return false
	if requested.sparseBinding && !supported.sparseBinding do return false
	if requested.sparseResidencyBuffer && !supported.sparseResidencyBuffer do return false
	if requested.sparseResidencyImage2D && !supported.sparseResidencyImage2D do return false
	if requested.sparseResidencyImage3D && !supported.sparseResidencyImage3D do return false
	if requested.sparseResidency2Samples && !supported.sparseResidency2Samples do return false
	if requested.sparseResidency4Samples && !supported.sparseResidency4Samples do return false
	if requested.sparseResidency8Samples && !supported.sparseResidency8Samples do return false
	if requested.sparseResidency16Samples && !supported.sparseResidency16Samples do return false
	if requested.sparseResidencyAliased && !supported.sparseResidencyAliased do return false
	if requested.variableMultisampleRate && !supported.variableMultisampleRate do return false
	if requested.inheritedQueries && !supported.inheritedQueries do return false

	return true
}
