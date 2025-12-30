package vkb_test

// Core
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

_ :: strings

// Vendor
import vk "vendor:vulkan"

// Local packages
import vkb "../"

Surface_Details :: struct {
	capabilities:    vk.SurfaceCapabilitiesKHR,
	surface_formats: [dynamic]vk.SurfaceFormatKHR,
	present_modes:   [dynamic]vk.PresentModeKHR,
}

Created_Device_Details :: struct {
    features:            vk.PhysicalDeviceFeatures,
    extensions:          []cstring,
    features_pNextChain: [dynamic]vkb.Generic_Feature,
}

Physical_Device_Details :: struct {
    properties:              vk.PhysicalDeviceProperties,
    features:                vk.PhysicalDeviceFeatures,
    memory_properties:       vk.PhysicalDeviceMemoryProperties,
    extensions:              [dynamic]vk.ExtensionProperties,
    queue_family_properties: [dynamic]vk.QueueFamilyProperties,
    features_pNextChain:     [dynamic]vkb.Generic_Feature,
    created_device_handles:  [dynamic]vk.Device,
    created_device_details:  [dynamic]Created_Device_Details,
}

Vulkan_Mock :: struct {
	instance_api_version:                    u32,
	instance_extensions:                     [dynamic]vk.ExtensionProperties,
	instance_layers:                         [dynamic]vk.LayerProperties,
	per_layer_instance_extension_properties: [dynamic][]vk.ExtensionProperties,
	per_layer_device_extension_properties:   [dynamic][]vk.ExtensionProperties,
	surface_handles:                         [dynamic]vk.SurfaceKHR,
	surface_details:                         [dynamic]Surface_Details,
	physical_device_handles:                 [dynamic]vk.PhysicalDevice,
	physical_devices_details:                [dynamic]Physical_Device_Details,
	created_image_view_count:                u32,
	fail_image_creation_on_iteration:        u32,
	should_save_api_version:                 bool,
	api_version_set_by_vkCreateInstance:     u32,

	// Internal
	ctx:                                     runtime.Context,
}

// TODO: Make mock thread safe to run in parallel
// Currently the tests need to run with `-define:ODIN_TEST_RANDOM_SEED=1`
@(thread_local)
mock: Vulkan_Mock

fill_out_count_pointer_pair :: proc "contextless" (data_arr: $A/[]$T, pCount: ^u32, pData: []T) -> vk.Result {
    if pCount == nil {
        return .ERROR_OUT_OF_HOST_MEMORY
    }

    if pData == nil {
        pCount^ = u32(len(data_arr))
        return .SUCCESS
    }

    amount_to_write := min(pCount^, u32(len(data_arr)))

    if amount_to_write > u32(len(pData)) {
        amount_to_write = u32(len(pData))
    }

    for i in 0 ..< amount_to_write {
        pData[i] = data_arr[i]
    }

    pCount^ = amount_to_write

    if amount_to_write < u32(len(data_arr)) {
        return .INCOMPLETE
    }

    return .SUCCESS
}

vk_mock_EnumerateInstanceVersion :: proc "system" (pApiVersion: ^u32) -> vk.Result {
    if pApiVersion == nil {
        return .ERROR_DEVICE_LOST
    }
    pApiVersion^ = mock.instance_api_version
    return .SUCCESS
}

vk_mock_EnumerateInstanceExtensionProperties :: proc "system" (
    pLayerName: cstring,
    pPropertyCount: ^u32,
    pProperties: [^]vk.ExtensionProperties,
) -> vk.Result {
	properties_slice :=
		pProperties != nil && pPropertyCount != nil ? pProperties[:pPropertyCount^] : nil
    if pLayerName != nil {
        for &instance_layer, i in mock.instance_layers {
            if byte_arr_str(&instance_layer.layerName) == string(pLayerName) {
                return fill_out_count_pointer_pair(
                	mock.per_layer_instance_extension_properties[i][:],
                	pPropertyCount,
                	properties_slice)
            }
        }
        // Layer not found, fill out with empty list
        return fill_out_count_pointer_pair(
        	[]vk.ExtensionProperties{}, pPropertyCount, properties_slice)
    }
    return fill_out_count_pointer_pair(
    	mock.instance_extensions[:], pPropertyCount, properties_slice)
}

vk_mock_EnumerateInstanceLayerProperties :: proc "system" (
	pPropertyCount: ^u32,
	pProperties: [^]vk.LayerProperties,
) -> vk.Result {
	properties_slice :=
		pProperties != nil && pPropertyCount != nil ? pProperties[:pPropertyCount^] : nil
    return fill_out_count_pointer_pair(mock.instance_layers[:], pPropertyCount, properties_slice)
}

vk_mock_CreateInstance :: proc "system" (
    pCreateInfo: ^vk.InstanceCreateInfo,
    pAllocator: ^vk.AllocationCallbacks,
    pInstance: ^vk.Instance,
) -> vk.Result {
    if pInstance == nil {
        return .ERROR_INITIALIZATION_FAILED
    }
    pInstance^ = vk.Instance(uintptr(0x0000ABCD))
    if pCreateInfo != nil && pCreateInfo.pApplicationInfo != nil && mock.should_save_api_version {
        mock.api_version_set_by_vkCreateInstance = pCreateInfo.pApplicationInfo.apiVersion
    }
    return .SUCCESS
}

vk_mock_DestroyInstance :: proc "system" (instance: vk.Instance, pAllocator: ^vk.AllocationCallbacks) {
}

vk_mock_CreateDebugUtilsMessengerEXT :: proc "system" (
	instance: vk.Instance,
	pCreateInfo: ^vk.DebugUtilsMessengerCreateInfoEXT,
	pAllocator: ^vk.AllocationCallbacks,
	pMessenger: ^vk.DebugUtilsMessengerEXT,
) -> vk.Result {
	if instance == nil {
        return .ERROR_INITIALIZATION_FAILED
    }
    pMessenger^ = vk.DebugUtilsMessengerEXT(0xDEBE0000DEBE0000)
    return .SUCCESS
}

vk_mock_DestroyDebugUtilsMessengerEXT :: proc "system" (
	instance: vk.Instance,
	messenger: vk.DebugUtilsMessengerEXT,
	pAllocator: ^vk.AllocationCallbacks,
) {
}

vk_mock_EnumeratePhysicalDevices :: proc "system" (
	instance: vk.Instance,
	pPhysicalDeviceCount: ^u32,
	pPhysicalDevices: [^]vk.PhysicalDevice,
) -> vk.Result {
	if instance == nil {
        return .ERROR_INITIALIZATION_FAILED
    }
	physical_devices_slice :=
		pPhysicalDevices != nil && pPhysicalDeviceCount != nil ? pPhysicalDevices[:pPhysicalDeviceCount^] : nil
    return fill_out_count_pointer_pair(
    	mock.physical_device_handles[:], pPhysicalDeviceCount, physical_devices_slice)
}

vk_mock_get_physical_device_details :: proc "contextless" (
	physicalDevice: vk.PhysicalDevice,
) -> ^Physical_Device_Details {
    for physical_device_handle, i in mock.physical_device_handles {
        if physical_device_handle == physicalDevice {
        	return &mock.physical_devices_details[i]
        }
    }
    panic_contextless("should never reach here!")
}

vk_mock_GetPhysicalDeviceFeatures :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pFeatures: [^]vk.PhysicalDeviceFeatures,
) {
    pFeatures[0] = vk_mock_get_physical_device_details(physicalDevice).features
}

vk_mock_GetPhysicalDeviceProperties :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pProperties: [^]vk.PhysicalDeviceProperties,
) {
    pProperties[0] = vk_mock_get_physical_device_details(physicalDevice).properties
}

vk_mock_GetPhysicalDeviceQueueFamilyProperties :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pQueueFamilyPropertyCount: ^u32,
	pQueueFamilyProperties: [^]vk.QueueFamilyProperties,
) {
	physical_device_details :=  vk_mock_get_physical_device_details(physicalDevice)
	properties_slice := pQueueFamilyProperties != nil && pQueueFamilyPropertyCount != nil \
			? pQueueFamilyProperties[:pQueueFamilyPropertyCount^] : nil
    fill_out_count_pointer_pair(
        physical_device_details.queue_family_properties[:], pQueueFamilyPropertyCount, properties_slice)
}

vk_mock_GetPhysicalDeviceMemoryProperties :: proc "system" (
    physicalDevice: vk.PhysicalDevice,
    pMemoryProperties: [^]vk.PhysicalDeviceMemoryProperties,
) {
    pMemoryProperties[0] = vk_mock_get_physical_device_details(physicalDevice).memory_properties
}

vk_mock_GetPhysicalDeviceFeatures2KHR :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pFeatures: [^]vk.PhysicalDeviceFeatures2,
) {
	phys_dev := vk_mock_get_physical_device_details(physicalDevice)
	pFeatures[0].features = phys_dev.features

	current := cast(^vk.BaseOutStructure)pFeatures[0].pNext
	for current != nil {
		for &features_pNext in phys_dev.features_pNextChain {
			structure_data: vk.BaseOutStructure
			mem.copy(&structure_data, &features_pNext.pNext, size_of(structure_data))
			if structure_data.sType == current.sType {
				next := current.pNext
				mem.copy(current, &features_pNext.pNext, size_of(features_pNext.pNext))
				current.pNext = next
				break
			}
		}
		current = cast(^vk.BaseOutStructure)&current.pNext
	}
}

vk_mock_GetPhysicalDeviceFeatures2 :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pFeatures: [^]vk.PhysicalDeviceFeatures2,
) {
    vk_mock_GetPhysicalDeviceFeatures2KHR(physicalDevice, pFeatures)
}

vk_mock_EnumerateDeviceExtensionProperties :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pLayerName: cstring,
	pPropertyCount: ^u32,
	pProperties: [^]vk.ExtensionProperties,
) -> vk.Result {
	properties_slice := pProperties != nil && pPropertyCount != nil  ? pProperties[:pPropertyCount^] : nil
    if pLayerName != nil {
    	for &instance_layer, i in mock.instance_layers {
    		layer_name := byte_arr_str(&instance_layer.layerName)
            if layer_name == string(pLayerName) {
                return fill_out_count_pointer_pair(
                	mock.per_layer_device_extension_properties[i], pPropertyCount, properties_slice)
            }
        }
        // Layer not found, fill out with empty list
        return fill_out_count_pointer_pair([]vk.ExtensionProperties{}, pPropertyCount, properties_slice)
    }
    return fill_out_count_pointer_pair(
    	vk_mock_get_physical_device_details(physicalDevice).extensions[:], pPropertyCount, properties_slice)
}

vk_mock_create_generic_feature_from_pNext :: proc(
	pNext: rawptr,
	sType: vk.StructureType,
) -> vkb.Generic_Feature {
	#partial switch sType {
	case .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES:
		return vkb.create_generic_features(cast(^vk.PhysicalDeviceDescriptorIndexingFeatures)pNext)
	case .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES:
		return vkb.create_generic_features(cast(^vk.PhysicalDeviceVulkan11Features)pNext)
	case .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES:
		return vkb.create_generic_features(cast(^vk.PhysicalDeviceVulkan12Features)pNext)
	case .PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES:
		return vkb.create_generic_features(cast(^vk.PhysicalDeviceSubgroupSizeControlFeatures)pNext)
	case:
		return {} // Return empty Generic_Feature
	}
}

vk_mock_CreateDevice :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	pCreateInfo: ^vk.DeviceCreateInfo,
	pAllocator: ^vk.AllocationCallbacks,
	pDevice: ^vk.Device,
) -> vk.Result {
	context = mock.ctx

    if physicalDevice == nil {
        return .ERROR_INITIALIZATION_FAILED
    }

    pDevice^ = vk.Device(uintptr(0x0000ABCD))
    physical_device_details := vk_mock_get_physical_device_details(physicalDevice)
    append(&physical_device_details.created_device_handles, pDevice^)

    new_feats: vk.PhysicalDeviceFeatures
    if pCreateInfo.pEnabledFeatures != nil {
        new_feats = pCreateInfo.pEnabledFeatures[0]
    }

    new_chain: [dynamic]vkb.Generic_Feature
    created_extensions := make([dynamic]cstring)

    for i in 0..< pCreateInfo.enabledExtensionCount {
		append(&created_extensions, pCreateInfo.ppEnabledExtensionNames[i])
	}

	pNext_chain := pCreateInfo.pNext
	for pNext_chain != nil {
		chain := cast(^vk.BaseOutStructure)pNext_chain
		next := chain.pNext

		new_feature := vk_mock_create_generic_feature_from_pNext(pNext_chain, chain.sType)
		if new_feature.type != {} {
			append(&new_chain, new_feature)
		}

		if chain.sType == .PHYSICAL_DEVICE_FEATURES_2 {
			features2 := cast(^vk.PhysicalDeviceFeatures2)pNext_chain
			new_feats = features2.features
		}

		pNext_chain = next
	}

    append(&physical_device_details.created_device_details, Created_Device_Details {
		features = new_feats,
		extensions = created_extensions[:],
		features_pNextChain = new_chain,
	})

    return .SUCCESS
}

vk_mock_GetPhysicalDeviceSurfaceSupportKHR :: proc "system" (
    physicalDevice: vk.PhysicalDevice,
    queueFamilyIndex: u32,
    surface: vk.SurfaceKHR,
    pSupported: ^b32,
) -> vk.Result {
	for i in 0 ..< len(mock.physical_device_handles) {
		if physicalDevice == mock.physical_device_handles[i] {
			if queueFamilyIndex >= u32(len(mock.physical_devices_details[i].queue_family_properties)) {
                return .ERROR_FORMAT_NOT_SUPPORTED
            }
		}
    }

    if surface != 0 && pSupported != nil {
		pSupported^ = true
    }

	return .SUCCESS
}

vk_mock_GetPhysicalDeviceSurfaceFormatsKHR :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	pSurfaceFormatCount: ^u32,
	pSurfaceFormats: [^]vk.SurfaceFormatKHR,
) -> vk.Result {
	for &surface_handle, i in mock.surface_handles {
		if surface_handle == surface {
			surface_formats_slice :=
				pSurfaceFormats == nil ? nil : pSurfaceFormats[:pSurfaceFormatCount^]
			return fill_out_count_pointer_pair(
				mock.surface_details[i].surface_formats[:],
				pSurfaceFormatCount,
				surface_formats_slice,
			)
		}
	}
	return .ERROR_SURFACE_LOST_KHR
}

vk_mock_GetPhysicalDeviceSurfacePresentModesKHR :: proc "system" (
	physicalDevice: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	pPresentModeCount: ^u32,
	pPresentModes: [^]vk.PresentModeKHR,
) -> vk.Result {
	for i in 0 ..< len(mock.surface_handles) {
        if mock.surface_handles[i] == surface {
			present_modes_slice :=
				pPresentModes == nil ? nil : pPresentModes[:pPresentModeCount^]
            return fill_out_count_pointer_pair(
            	mock.surface_details[i].present_modes[:],
            	pPresentModeCount,
            	present_modes_slice,
            )
        }
    }
    return .ERROR_SURFACE_LOST_KHR
}

vk_mock_GetInstanceProcAddr :: proc "system" (instance: vk.Instance, pName: cstring) -> vk.ProcVoidFunction {
	gpa_impl :: #force_inline proc "contextless" (pName, target_name: cstring) -> bool {
		return pName == target_name
	}

	switch {
	case gpa_impl(pName, "vkGetInstanceProcAddr"):
		return auto_cast vk_mock_GetInstanceProcAddr
	case gpa_impl(pName, "vkEnumerateInstanceVersion"):
		return auto_cast vk_mock_EnumerateInstanceVersion
	case gpa_impl(pName, "vkEnumerateInstanceExtensionProperties"):
		return auto_cast vk_mock_EnumerateInstanceExtensionProperties
	case gpa_impl(pName, "vkEnumerateInstanceLayerProperties"):
		return auto_cast vk_mock_EnumerateInstanceLayerProperties
	case gpa_impl(pName, "vkCreateInstance"):
		return auto_cast vk_mock_CreateInstance
	case gpa_impl(pName, "vkDestroyInstance"):
		return auto_cast vk_mock_DestroyInstance
	case gpa_impl(pName, "vkCreateDebugUtilsMessengerEXT"):
		return auto_cast vk_mock_CreateDebugUtilsMessengerEXT
	case gpa_impl(pName, "vkDestroyDebugUtilsMessengerEXT"):
		return auto_cast vk_mock_DestroyDebugUtilsMessengerEXT
	case gpa_impl(pName, "vkEnumeratePhysicalDevices"):
		return auto_cast vk_mock_EnumeratePhysicalDevices
	case gpa_impl(pName, "vkGetPhysicalDeviceFeatures"):
		return auto_cast vk_mock_GetPhysicalDeviceFeatures
	case gpa_impl(pName, "vkGetPhysicalDeviceProperties"):
		return auto_cast vk_mock_GetPhysicalDeviceProperties
	case gpa_impl(pName, "vkGetPhysicalDeviceQueueFamilyProperties"):
		return auto_cast vk_mock_GetPhysicalDeviceQueueFamilyProperties
	case gpa_impl(pName, "vkGetPhysicalDeviceMemoryProperties"):
		return auto_cast vk_mock_GetPhysicalDeviceMemoryProperties
	case gpa_impl(pName, "vkGetPhysicalDeviceFeatures2KHR"):
		return auto_cast vk_mock_GetPhysicalDeviceFeatures2KHR
	case gpa_impl(pName, "vkGetPhysicalDeviceFeatures2"):
		return auto_cast vk_mock_GetPhysicalDeviceFeatures2
	case gpa_impl(pName, "vkEnumerateDeviceExtensionProperties"):
		return auto_cast vk_mock_EnumerateDeviceExtensionProperties
	case gpa_impl(pName, "vkCreateDevice"):
		return auto_cast vk_mock_CreateDevice
	case gpa_impl(pName, "vkGetDeviceProcAddr"):
		return auto_cast vk_mock_GetDeviceProcAddr
	// case gpa_impl(pName, "vkGetDeviceQueue"):
	// 	return auto_cast vk_mock_GetDeviceQueue
	// case gpa_impl(pName, "vkDestroyDevice"):
	// 	return auto_cast vk_mock_DestroyDevice
	// case gpa_impl(pName, "vkDestroySurfaceKHR"):
	// 	return auto_cast vk_mock_DestroySurfaceKHR
	case gpa_impl(pName, "vkGetPhysicalDeviceSurfaceSupportKHR"):
		return auto_cast vk_mock_GetPhysicalDeviceSurfaceSupportKHR
	case gpa_impl(pName, "vkGetPhysicalDeviceSurfaceFormatsKHR"):
		return auto_cast vk_mock_GetPhysicalDeviceSurfaceFormatsKHR
	case gpa_impl(pName, "vkGetPhysicalDeviceSurfacePresentModesKHR"):
		return auto_cast vk_mock_GetPhysicalDeviceSurfacePresentModesKHR
	// case gpa_impl(pName, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"):
	// 	return auto_cast vk_mock_GetPhysicalDeviceSurfaceCapabilitiesKHR
	// case gpa_impl(pName, "vkCreateCommandPool"):
	// 	return auto_cast vk_mock_CreateCommandPool
	}

	return nil
}

vk_mock_DestroyDevice :: proc "system" (device: vk.Device, pAllocator: ^vk.AllocationCallbacks) {
}

vk_mock_CreateFence :: proc "system" (
	device: vk.Device,
    pCreateInfo: ^vk.FenceCreateInfo,
    pAllocator: ^vk.AllocationCallbacks,
    pFence: ^vk.Fence,
) -> vk.Result {
    pFence^ = vk.Fence(0x0000AAAC)
    return .SUCCESS
}

vk_mock_DestroyFence :: proc "system" (
    device: vk.Device,
    fence: vk.Fence,
    pAllocator: ^vk.AllocationCallbacks,
) {}

vk_mock_GetDeviceProcAddr :: proc "system" (device: vk.Device, pName: cstring) -> vk.ProcVoidFunction {
	gpa_impl :: #force_inline proc "contextless" (pName, target_name: cstring) -> bool {
		return pName == target_name
	}

	switch {
	case gpa_impl(pName, "vkGetDeviceProcAddr"):
		return auto_cast vk_mock_GetDeviceProcAddr
	case gpa_impl(pName, "vkDestroyDevice"):
		return auto_cast vk_mock_DestroyDevice
	case gpa_impl(pName, "vkGetDeviceQueue"):
		// return auto_cast vk_mock_GetDeviceQueue
	case gpa_impl(pName, "vkCreateCommandPool"):
		// return auto_cast vk_mock_CreateCommandPool
	case gpa_impl(pName, "vkCreateFence"):
		return auto_cast vk_mock_CreateFence
	case gpa_impl(pName, "vkDestroyFence"):
		return auto_cast vk_mock_DestroyFence
	case gpa_impl(pName, "vkCreateSwapchainKHR"):
		// return auto_cast vk_mock_CreateSwapchainKHR
	case gpa_impl(pName, "vkGetSwapchainImagesKHR"):
		// return auto_cast vk_mock_GetSwapchainImagesKHR
	case gpa_impl(pName, "vkCreateImageView"):
		// return auto_cast vk_mock_CreateImageView
	case gpa_impl(pName, "vkDestroyImageView"):
		// return auto_cast vk_mock_DestroyImageView
	case gpa_impl(pName, "vkDestroySwapchainKHR"):
		// return auto_cast vk_mock_DestroySwapchainKHR
	case gpa_impl(pName, "vkAcquireNextImageKHR"):
		// return auto_cast vk_mock_AcquireNextImageKHR
	}

	return nil
}

vk_mock_init :: proc() -> () {
	mock = {
		ctx = context,
	} // reset

	ensure(vkb.load_library(vk_mock_GetInstanceProcAddr))

	mock.instance_api_version = vk.API_VERSION_1_3
	mock.fail_image_creation_on_iteration = max(u32)

	add_extension_properties(&mock.instance_extensions, vk.KHR_SURFACE_EXTENSION_NAME)

	when ODIN_OS == .Windows {
		add_extension_properties(&mock.instance_extensions, vk.KHR_WIN32_SURFACE_EXTENSION_NAME)
	} else when ODIN_OS == .Linux {
		add_extension_properties(&mock.instance_extensions, vk.KHR_XCB_SURFACE_EXTENSION_NAME)
		add_extension_properties(&mock.instance_extensions, vk.KHR_XLIB_SURFACE_EXTENSION_NAME)
		add_extension_properties(&mock.instance_extensions, vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME)
	} else when ODIN_OS == .Darwin {
		add_extension_properties(&mock.instance_extensions, vk.EXT_METAL_SURFACE_EXTENSION_NAME)
	}

	add_extension_properties(&mock.instance_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

	vk_mock_add_basic_physical_device()
}

vk_mock_add_physical_device :: proc(details: Physical_Device_Details) {
	physical_device := vk.PhysicalDevice(0x22334455 + uintptr(len(mock.physical_device_handles)))
	append(&mock.physical_device_handles, physical_device)
	append(&mock.physical_devices_details, details)
}

vk_mock_add_layer :: proc(
	layer_properties: vk.LayerProperties,
	layer_instance_extensions: []vk.ExtensionProperties,
	layer_device_extensions: []vk.ExtensionProperties,
) {
	append(&mock.instance_layers, layer_properties)
	append(&mock.per_layer_instance_extension_properties, layer_instance_extensions)
	append(&mock.per_layer_instance_extension_properties, layer_device_extensions)
}

vk_mock_get_new_surface :: proc(details: Surface_Details) -> vk.SurfaceKHR {
	surface := vk.SurfaceKHR(0x123456789AB + len(mock.surface_handles))
	append(&mock.surface_handles, surface)
	append(&mock.surface_details, details)
	return surface
}

add_extension_properties :: proc(list: ^[dynamic]vk.ExtensionProperties, ext_name: string) {
	base_props: vk.ExtensionProperties
	init_extension_properties(&base_props, ext_name)
	append(list, base_props)
}

init_extension_properties :: proc(props: ^vk.ExtensionProperties, ext_name: string) {
	props^ = {}
	data := transmute([]u8)ext_name
	copy(props.extensionName[:], data[:])
}

vk_mock_add_basic_physical_device :: proc() -> ^Physical_Device_Details {
	physical_device_details: Physical_Device_Details
	add_extension_properties(&physical_device_details.extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
    physical_device_details.properties.apiVersion = vk.API_VERSION_1_3
    queue_family_properties: vk.QueueFamilyProperties
    queue_family_properties.queueCount = 1
    queue_family_properties.queueFlags = { .GRAPHICS, .COMPUTE, .TRANSFER }
    queue_family_properties.minImageTransferGranularity = { 1, 1, 1 }
    append(&physical_device_details.queue_family_properties, queue_family_properties)
    vk_mock_add_physical_device(physical_device_details)
    return &mock.physical_devices_details[len(mock.physical_devices_details)-1]
}

create_basic_surface_details :: proc() -> (details: Surface_Details) {
	append(&details.present_modes, vk.PresentModeKHR.FIFO)
	append(&details.surface_formats, vk.SurfaceFormatKHR{ .R8G8B8_SRGB, .SRGB_NONLINEAR })
    details.capabilities.minImageCount = 2
    details.capabilities.minImageExtent = { 600, 800 }
    details.capabilities.currentExtent = { 600, 800 }
    details.capabilities.supportedUsageFlags = { .COLOR_ATTACHMENT }
    return
}

destroy_surface_details :: proc(self: ^Surface_Details) {
	delete(self.present_modes)
	delete(self.surface_formats)
}

get_instance :: proc(t: ^testing.T, minor_version: u32 = 1) -> (instance: ^vkb.Instance, ok: bool) {
	builder := vkb.create_instance_builder()
    defer vkb.destroy_instance_builder(builder)
    vkb.instance_builder_request_validation_layers(builder)
    vkb.instance_builder_require_api_version(builder, 1, minor_version, 0)
    vkb_instance, vkb_instance_err := vkb.instance_builder_build(builder)
	if !testing.expect(t, vkb_instance_err == nil, "Expected vkb_instance_err to be nil") {
			fmt.eprintfln("%#v", vkb_instance_err)
			return
	}
    return vkb_instance, true
}

get_headless_instance :: proc(t: ^testing.T, minor_version: u32 = 1) -> (instance: ^vkb.Instance, ok: bool) {
	builder := vkb.create_instance_builder()
    defer vkb.destroy_instance_builder(builder)
    vkb.instance_builder_request_validation_layers(builder)
    vkb.instance_builder_require_api_version(builder, 1, minor_version, 0)
    vkb.instance_builder_set_headless(builder)
    vkb_instance, vkb_instance_err := vkb.instance_builder_build(builder)
	if !testing.expect(t, vkb_instance_err == nil, "Expected vkb_instance_err to be nil") {
			fmt.eprintfln("%#v", vkb_instance_err)
			return
	}
    return vkb_instance, true
}

byte_arr_str :: proc "contextless" (arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}
