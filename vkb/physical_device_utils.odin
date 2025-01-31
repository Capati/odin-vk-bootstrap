package vk_bootstrap

// Core
import "base:runtime"
import "core:log"

// Vendor
import vk "vendor:vulkan"

check_device_extension_support :: proc(
	available_extensions: ^[]vk.ExtensionProperties,
	required_extensions: []cstring,
) -> (
	supported: bool,
) {
	supported = true

	if len(required_extensions) == 0 || len(available_extensions) == 0 {
		return true
	}

	for &avail_ext in available_extensions {
		for req_ext in required_extensions {
			if cstring(&avail_ext.extensionName[0]) != req_ext {
				log.warnf("Required extension \x1b[33m%s\x1b[0m is not available", req_ext)
				supported = false
			}
		}
	}

	return
}

check_device_features_support :: proc(
	supported: vk.PhysicalDeviceFeatures,
	requested: vk.PhysicalDeviceFeatures,
	extension_supported: ^[dynamic]Generic_Feature,
	extension_requested: ^[dynamic]Generic_Feature,
) -> bool {
	if requested.robustBufferAccess && !supported.robustBufferAccess {
		return false
	}
	if requested.fullDrawIndexUint32 && !supported.fullDrawIndexUint32 {
		return false
	}
	if requested.imageCubeArray && !supported.imageCubeArray {
		return false
	}
	if requested.independentBlend && !supported.independentBlend {
		return false
	}
	if requested.geometryShader && !supported.geometryShader {
		return false
	}
	if requested.tessellationShader && !supported.tessellationShader {
		return false
	}
	if requested.sampleRateShading && !supported.sampleRateShading {
		return false
	}
	if requested.dualSrcBlend && !supported.dualSrcBlend {
		return false
	}
	if requested.logicOp && !supported.logicOp {
		return false
	}
	if requested.multiDrawIndirect && !supported.multiDrawIndirect {
		return false
	}
	if requested.drawIndirectFirstInstance && !supported.drawIndirectFirstInstance {
		return false
	}
	if requested.depthClamp && !supported.depthClamp {
		return false
	}
	if requested.depthBiasClamp && !supported.depthBiasClamp {
		return false
	}
	if requested.fillModeNonSolid && !supported.fillModeNonSolid {
		return false
	}
	if requested.depthBounds && !supported.depthBounds {
		return false
	}
	if requested.wideLines && !supported.wideLines {
		return false
	}
	if requested.largePoints && !supported.largePoints {
		return false
	}
	if requested.alphaToOne && !supported.alphaToOne {
		return false
	}
	if requested.multiViewport && !supported.multiViewport {
		return false
	}
	if requested.samplerAnisotropy && !supported.samplerAnisotropy {
		return false
	}
	if requested.textureCompressionETC2 && !supported.textureCompressionETC2 {
		return false
	}
	if requested.textureCompressionASTC_LDR && !supported.textureCompressionASTC_LDR {
		return false
	}
	if requested.textureCompressionBC && !supported.textureCompressionBC {
		return false
	}
	if requested.occlusionQueryPrecise && !supported.occlusionQueryPrecise {
		return false
	}
	if requested.pipelineStatisticsQuery && !supported.pipelineStatisticsQuery {
		return false
	}
	if requested.vertexPipelineStoresAndAtomics && !supported.vertexPipelineStoresAndAtomics {
		return false
	}
	if requested.fragmentStoresAndAtomics && !supported.fragmentStoresAndAtomics {
		return false
	}
	if requested.shaderTessellationAndGeometryPointSize &&
	   !supported.shaderTessellationAndGeometryPointSize {
		return false
	}
	if requested.shaderImageGatherExtended && !supported.shaderImageGatherExtended {
		return false
	}
	if requested.shaderStorageImageExtendedFormats &&
	   !supported.shaderStorageImageExtendedFormats {
		return false
	}
	if requested.shaderStorageImageMultisample && !supported.shaderStorageImageMultisample {
		return false
	}
	if requested.shaderStorageImageReadWithoutFormat &&
	   !supported.shaderStorageImageReadWithoutFormat {
		return false
	}
	if requested.shaderStorageImageWriteWithoutFormat &&
	   !supported.shaderStorageImageWriteWithoutFormat {
		return false
	}
	if requested.shaderUniformBufferArrayDynamicIndexing &&
	   !supported.shaderUniformBufferArrayDynamicIndexing {
		return false
	}
	if requested.shaderSampledImageArrayDynamicIndexing &&
	   !supported.shaderSampledImageArrayDynamicIndexing {
		return false
	}
	if requested.shaderStorageBufferArrayDynamicIndexing &&
	   !supported.shaderStorageBufferArrayDynamicIndexing {
		return false
	}
	if requested.shaderStorageImageArrayDynamicIndexing &&
	   !supported.shaderStorageImageArrayDynamicIndexing {
		return false
	}
	if requested.shaderClipDistance && !supported.shaderClipDistance {
		return false
	}
	if requested.shaderCullDistance && !supported.shaderCullDistance {
		return false
	}
	if requested.shaderFloat64 && !supported.shaderFloat64 {
		return false
	}
	if requested.shaderInt64 && !supported.shaderInt64 {
		return false
	}
	if requested.shaderInt16 && !supported.shaderInt16 {
		return false
	}
	if requested.shaderResourceResidency && !supported.shaderResourceResidency {
		return false
	}
	if requested.shaderResourceMinLod && !supported.shaderResourceMinLod {
		return false
	}
	if requested.sparseBinding && !supported.sparseBinding {
		return false
	}
	if requested.sparseResidencyBuffer && !supported.sparseResidencyBuffer {
		return false
	}
	if requested.sparseResidencyImage2D && !supported.sparseResidencyImage2D {
		return false
	}
	if requested.sparseResidencyImage3D && !supported.sparseResidencyImage3D {
		return false
	}
	if requested.sparseResidency2Samples && !supported.sparseResidency2Samples {
		return false
	}
	if requested.sparseResidency4Samples && !supported.sparseResidency4Samples {
		return false
	}
	if requested.sparseResidency8Samples && !supported.sparseResidency8Samples {
		return false
	}
	if requested.sparseResidency16Samples && !supported.sparseResidency16Samples {
		return false
	}
	if requested.sparseResidencyAliased && !supported.sparseResidencyAliased {
		return false
	}
	if requested.variableMultisampleRate && !supported.variableMultisampleRate {
		return false
	}
	if requested.inheritedQueries && !supported.inheritedQueries {
		return false
	}

	// Should only be false if extension_supported was unable to be filled out, due to the
	// physical device not supporting vk.GetPhysicalDeviceFeatures2 in any capacity.
	if len(extension_requested) != len(extension_supported) {
		return false
	}

	total := len(extension_requested)
	for i in 0 ..< total {
		if !generic_features_match(&extension_requested[i], &extension_supported[i]) {
			return false
		}
	}

	return true
}
