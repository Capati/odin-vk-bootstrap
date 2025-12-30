package vkbootstrap

// Core
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"

// Vendor
import vk "vendor:vulkan"

General_Error_Kind :: enum {
	Vulkan_Unavailable,
	Vulkan_Error,
}

General_Error :: struct {
	kind:    General_Error_Kind,
	result:  vk.Result,
	message: string,
}

Instance_Error_Kind :: enum {
	Vulkan_Unavailable,
	Vulkan_Version_Unavailable,
	Vulkan_Version_1_1_Unavailable,
	Vulkan_Version_1_2_Unavailable,
	Vulkan_Version_1_3_Unavailable,
	Vulkan_Version_1_4_Unavailable,
	Failed_Create_Instance,
	Failed_Create_Debug_Messenger,
	Requested_Layers_Not_Present,
	Requested_Extensions_Not_Present,
	Windowing_Extensions_Not_Present,
}

Instance_Error :: struct {
	kind:    Instance_Error_Kind,
	result:  vk.Result,
	message: string,
}

Physical_Device_Error_Kind :: enum {
	No_Surface_Provided,
	Failed_Enumerate_Physical_Devices,
	No_Physical_Devices_Found,
	No_Suitable_Device,
}

Physical_Device_Error :: struct {
	kind:                  Physical_Device_Error_Kind,
	result:                vk.Result,
	message:               string,
	unsuitability_reasons: []string,
}

Queue_Error_Kind :: enum {
	Present_Unavailable,
	Graphics_Unavailable,
	Compute_Unavailable,
	Transfer_Unavailable,
	Queue_Index_Out_Of_Range,
	Invalid_Queue_Family_Index,
}

Queue_Error :: struct {
	kind:    Queue_Error_Kind,
	result:  vk.Result,
	message: string,
}

Device_Error_Kind :: enum {
	Failed_Create_Device,
	VkFeatures2_Pnext_Chain,
}

Device_Error :: struct {
	kind:    Device_Error_Kind,
	result:  vk.Result,
	message: string,
}

Swapchain_Error_Kind :: enum {
	Surface_Handle_Not_Provided,
	Failed_Query_Surface_Support_Details,
	Failed_Create_Swapchain,
	Failed_Get_Swapchain_Images,
	Failed_Create_Swapchain_Image_Views,
	Required_Min_Image_Count_Too_Low,
	Required_Usage_Not_Supported,
}

Swapchain_Error :: struct {
	kind:    Swapchain_Error_Kind,
	result:  vk.Result,
	message: string,
}

Surface_Support_Error_Kind :: enum {
	Surface_Handle_Null,
	Failed_Get_Surface_Capabilities,
	Failed_Enumerate_Surface_Formats,
	Failed_Enumerate_Present_Modes,
	No_Suitable_Desired_Format,
}

Surface_Support_Error :: struct {
	kind:    Surface_Support_Error_Kind,
	result:  vk.Result,
	message: string,
}

Error :: union {
	General_Error,
	Instance_Error,
	Physical_Device_Error,
	Queue_Error,
	Device_Error,
	Swapchain_Error,
	Surface_Support_Error,
}

// =============================================================================
// System Info
// =============================================================================


// VK_LAYER_KHRONOS_validation
VALIDATION_LAYER_NAME :: "VK_LAYER_KHRONOS_validation"

// Gathers useful information about the available vulkan capabilities, like layers and
// instance extensions. Use this for enabling features conditionally, ie if you would like
// an extension but can use a fallback if it isn't supported but need to know if support
// is available first.
System_Info :: struct {
	available_layers:            map[string]vk.LayerProperties,
	available_layer_names:       []string,

	available_extensions:        map[string]vk.ExtensionProperties,
	available_extension_names:   []string,

	validation_layers_available: bool,
	debug_utils_available:       bool,
	instance_api_version:        u32,

	// Internal
	arena:                       mem.Arena,
	arena_buf:                   []byte,
	allocator:                   runtime.Allocator,
}

@(require_results)
get_system_info :: proc(
	fp_get_instance_proc_addr: vk.ProcGetInstanceProcAddr = nil,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	info: ^System_Info,
	err: Error,
) {
	// When using externally provided function pointers we assume the loader is available,
	// otherwise, the Vulkan library is loaded
	if !load_library(fp_get_instance_proc_addr, loc) {
		err = General_Error {
			kind = .Vulkan_Unavailable,
			message = "Failed to load Vulkan library",
		}
		return
	}

	context.allocator = allocator

	arena: mem.Arena
	arena_buf := make([]byte, 64 * mem.Kilobyte, allocator)
	defer if err != nil { delete(arena_buf) }
	mem.arena_init(&arena, arena_buf)

	arena_allocator := mem.arena_allocator(&arena)

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	layer_count: u32
	vk_check(vk.EnumerateInstanceLayerProperties(
		&layer_count, nil,
	), "Failed to enumerate instance layer properties count", loc) or_return

	available_layers := make(map[string]vk.LayerProperties, layer_count, allocator)
	available_layer_names := make([dynamic]string, 0, layer_count, allocator)

	validation_layers_available: bool
	if layer_count > 0 {
		layers := make([]vk.LayerProperties, layer_count, ta)
		vk_check(vk.EnumerateInstanceLayerProperties(
			&layer_count, raw_data(layers),
		), "Failed to enumerate instance layer properties", loc) or_return

		// Add layers to map
		for &layer in layers {
			layer_name := strings.clone(byte_arr_str(&layer.layerName), arena_allocator)
			available_layers[layer_name] = layer
			append(&available_layer_names, layer_name)

			if layer_name == VALIDATION_LAYER_NAME {
				validation_layers_available = true
			}
		}
	}

	// Enumerate global extensions
	extension_count: u32
	vk_check(vk.EnumerateInstanceExtensionProperties(
		nil, &extension_count, nil,
	), "Failed to enumerate instance extension properties count", loc) or_return

	available_extensions := make(
		map[string]vk.ExtensionProperties,
		int(extension_count),
		allocator,
	)
	available_extension_names := make(
		[dynamic]string,
		0,
		int(extension_count),
		allocator,
	)

	debug_utils_available: bool
	if extension_count > 0 {
		global_extensions := make([]vk.ExtensionProperties, extension_count, ta)
		vk_check(vk.EnumerateInstanceExtensionProperties(
			nil,
			&extension_count,
			raw_data(global_extensions),
		), "Failed to enumerate instance extension properties", loc) or_return

		// Add global extensions to map
		for &ext in global_extensions {
			ext_name := strings.clone(byte_arr_str(&ext.extensionName), arena_allocator)
			available_extensions[ext_name] = ext
			append(&available_extension_names, ext_name)

			if ext_name == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				debug_utils_available = true
			}
		}
	}

	// Enumerate layer-specific extensions
	for _, &layer in available_layers {
		layer_ext_count: u32
		vk_check(vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_ext_count,
			nil,
		), "Failed to enumerate layer extension properties count", loc) or_return

		if layer_ext_count == 0 {
			continue
		}

		layer_extensions := make([]vk.ExtensionProperties, layer_ext_count, ta)
		vk_check(vk.EnumerateInstanceExtensionProperties(
			cstring(&layer.layerName[0]),
			&layer_ext_count,
			raw_data(layer_extensions),
		), "Failed to enumerate layer extension properties", loc) or_return

		// Add unique layer extensions to map
		for &ext in layer_extensions {
			ext_name := byte_arr_str(&ext.extensionName)

			// Only add if not already in map
			if ext_name not_in available_extensions {
				ext_name_key := strings.clone(byte_arr_str(&ext.extensionName), arena_allocator)
				available_extensions[ext_name_key] = ext
				append(&available_extension_names, ext_name_key)
			}

			// Check for debug utils
			if !debug_utils_available && ext_name == vk.EXT_DEBUG_UTILS_EXTENSION_NAME {
				debug_utils_available = true
			}
		}
	}

	// Query current instance version
	instance_api_version : u32 = vk.API_VERSION_1_0
	// Instance implementation may be too old to support EnumerateInstanceVersion. We need
	// to check the function pointer before calling it, if the function doesn't exist,
	// then the instance version must be 1.0.
	if vk.EnumerateInstanceVersion != nil {
		res := vk.EnumerateInstanceVersion(&instance_api_version)
		if res != .SUCCESS {
			instance_api_version = vk.API_VERSION_1_0
		}
	}

	slice.sort(available_layer_names[:])
	slice.sort(available_extension_names[:])

	info = new_clone(System_Info {
		available_layers            = available_layers,
		available_layer_names       = available_layer_names[:],
		available_extension_names   = available_extension_names[:],
		available_extensions        = available_extensions,
		validation_layers_available = validation_layers_available,
		debug_utils_available       = debug_utils_available,
		instance_api_version        = instance_api_version,
		arena                       = arena,
		arena_buf                   = arena_buf,
		allocator                   = allocator,
	}, allocator)
	assert(info != nil, "Failed to allocate System_Info", loc)

	return
}

destroy_system_info :: proc(
	self: ^System_Info,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert(self != nil, "Invalid System_Info", loc)
	context.allocator = allocator
	delete(self.arena_buf)
	delete(self.available_layers)
	delete(self.available_extensions)
	delete(self.available_layer_names)
	delete(self.available_extension_names)
	free(self)
}

// Returns `true` if a layer is available.
system_info_is_layer_available :: proc(self: ^System_Info, layer_name: string) -> bool {
	return layer_name in self.available_layers
}

// Returns `true` if all layers are available.
system_info_is_layers_available_string :: proc(self: ^System_Info, required_layers: []string) -> bool {
	for required in required_layers {
		if required not_in self.available_layers {
			return false
		}
	}
	return true
}

// Returns `true` if all layers are available.
system_info_is_layers_available_cstring :: proc(self: ^System_Info, required_layers: []cstring) -> bool {
	for required in required_layers {
		if string(required) not_in self.available_layers {
			return false
		}
	}
	return true
}

// Returns `true` if all layers are available.
system_info_is_layers_available :: proc {
	system_info_is_layers_available_string,
	system_info_is_layers_available_cstring,
}

// Returns a list view of available layer names.
system_info_get_layer_names :: proc(self: ^System_Info) -> []string {
	return  self.available_layer_names
}

// Returns `true` if an extension is available.
system_info_is_extension_available :: proc(self: ^System_Info, extension_name: string) -> bool {
	return extension_name in self.available_extensions
}

// Returns `true` if all extensions are available.
system_info_is_extensions_available_string :: proc(self: ^System_Info, required_extensions: []string) -> bool {
	for required in required_extensions {
		if required not_in self.available_extensions {
			return false
		}
	}
	return true
}

// Returns `true` if all extensions are available.
system_info_is_extensions_available_cstring :: proc(self: ^System_Info, required_extensions: []cstring) -> bool {
	for required in required_extensions {
		if string(required) not_in self.available_extensions {
			return false
		}
	}
	return true
}

// Returns `true` if all extensions are available.
system_info_is_extensions_available :: proc {
	system_info_is_extensions_available_string,
	system_info_is_extensions_available_cstring,
}

// Returns a list view of available extension names.
system_info_get_extension_names :: proc(self: ^System_Info) -> []string {
	return  self.available_extension_names
}

// Get layer properties by name.
system_info_get_layer :: proc(
	self: ^System_Info,
	layer_name: string,
) -> (
	layer: vk.LayerProperties,
	ok: bool,
) #optional_ok {
	layer, ok = self.available_layers[layer_name]
	return
}

// Get extension properties by name.
system_info_get_extension :: proc(
	self: ^System_Info,
	extension_name: string,
) -> (
	extension: vk.ExtensionProperties,
	ok: bool,
) #optional_ok {
	extension, ok = self.available_extensions[extension_name]
	return
}

// Returns `true` if the Instance API Version is greater than or equal to the specified version.
system_info_is_instance_version_available_value :: proc(
	self: ^System_Info,
	major_api_version, minor_api_version: u32,
) -> bool {
	return self.instance_api_version >= vk.MAKE_VERSION(major_api_version, minor_api_version, 0)
}

// Returns `true` if the Instance API Version is greater than or equal to the specified version.
//
// Should be constructed with `vk.MAKE_VERSION`.
system_info_is_instance_version_available_values :: proc(self: ^System_Info, api_version: u32) -> bool {
	return self.instance_api_version >= api_version
}

// Returns `true` if the Instance API Version is greater than or equal to the specified version.
system_info_is_instance_version_available :: proc {
	system_info_is_instance_version_available_value,
	system_info_is_instance_version_available_values,
}

// =============================================================================
// Instance Builder
// =============================================================================

Instance_Builder :: struct {
	// vk.ApplicationInfo
	app_name:                     string,
	engine_name:                  string,
	application_version:          u32,
	engine_version:               u32,
	minimum_instance_version:     u32,
	required_api_version:         u32,

	// vk.InstanceCreateInfo
	layers:                       [dynamic]string,
	extensions:                   [dynamic]string,
	flags:                        vk.InstanceCreateFlags,
	layer_settings:               [dynamic]vk.LayerSettingEXT,

	// Debug callback
	debug_callback:               vk.ProcDebugUtilsMessengerCallbackEXT,
	debug_message_severity:       vk.DebugUtilsMessageSeverityFlagsEXT,
	debug_message_type:           vk.DebugUtilsMessageTypeFlagsEXT,
	debug_user_data_pointer:      rawptr,

	// Validation features
	disabled_validation_checks:   [dynamic]vk.ValidationCheckEXT,
	enabled_validation_features:  [dynamic]vk.ValidationFeatureEnableEXT,
	disabled_validation_features: [dynamic]vk.ValidationFeatureDisableEXT,

	// Custom allocator
	allocation_callbacks:         ^vk.AllocationCallbacks,

	// Flags
	request_validation_layers:    bool,
	enable_validation_layers:     bool,
	use_debug_messenger:          bool,
	headless_context:             bool,

	// Internal
	get_instance_proc_addr:       vk.ProcGetInstanceProcAddr,
	allocator:                    runtime.Allocator,
	initialized:                  bool,
}

instance_builder_make_default :: proc(
	allocator := context.allocator,
	loc := #caller_location,
) -> ^Instance_Builder {
	out := new_clone(Instance_Builder{
		allocator = allocator,
		initialized = true,
	}, allocator)
	instance_builder_init_default(out, allocator)
	return out
}

instance_builder_make_with_proc_addr :: proc(
	get_instance_proc_addr: vk.ProcGetInstanceProcAddr,
	allocator := context.allocator,
	loc := #caller_location,
) -> ^Instance_Builder {
	assert(get_instance_proc_addr != nil, loc = loc)
	out := new_clone(Instance_Builder{
		get_instance_proc_addr = get_instance_proc_addr,
		allocator = allocator,
		initialized = true,
	}, allocator)
	instance_builder_init_default(out, allocator)
	return out
}

instance_builder_init_default :: proc(self: ^Instance_Builder, allocator: runtime.Allocator) {
	self.required_api_version = vk.API_VERSION_1_0
	self.debug_message_severity = { .WARNING, .ERROR }
	self.debug_message_type = { .GENERAL, .VALIDATION, .PERFORMANCE }
	self.layers.allocator = allocator
	self.extensions.allocator = allocator
	self.layer_settings.allocator = allocator
	self.disabled_validation_checks.allocator = allocator
	self.enabled_validation_features.allocator = allocator
	self.disabled_validation_features.allocator = allocator
}

create_instance_builder :: proc {
	instance_builder_make_default,
	instance_builder_make_with_proc_addr,
}

destroy_instance_builder :: proc(self: ^Instance_Builder, loc := #caller_location) {
	assert(self != nil, loc = loc)
	context.allocator = self.allocator
	delete(self.layers)
	delete(self.extensions)
	delete(self.layer_settings)
	delete(self.disabled_validation_checks)
	delete(self.enabled_validation_features)
	delete(self.disabled_validation_features)
	free(self)
}

@(require_results)
instance_builder_build :: proc(
	self: ^Instance_Builder,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	instance: ^Instance,
	err: Error,
) {
	assert(self != nil, loc = loc)
	assert(self.initialized, "Instance builder not initialized", loc)

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	info, _ := get_system_info(self.get_instance_proc_addr, allocator = ta)

	instance_version: u32 = vk.API_VERSION_1_0

	// Only check Vulkan version if we have specific version requirements
	if self.minimum_instance_version > vk.API_VERSION_1_0 || self.required_api_version > vk.API_VERSION_1_0 {
		// Check if we can query the Vulkan version at all
		if vk.EnumerateInstanceVersion != nil {
			// Should always return .SUCCESS
			if res := vk.EnumerateInstanceVersion(&instance_version); res != .SUCCESS {
				if self.required_api_version > 0 || self.minimum_instance_version > 0 {
					err = Instance_Error {
						.Vulkan_Unavailable, res, "Vulkan version unavailable",
					}
					return
				}
			}
		}

		// Verify the queried version meets our requirements
		if vk.EnumerateInstanceVersion == nil || // Can't query version at all
		   (self.minimum_instance_version > 0 && instance_version < self.minimum_instance_version) ||
		   (self.minimum_instance_version == 0 && instance_version < self.required_api_version) {
			// Determine which version to show in the error message
			version_error := self.minimum_instance_version == 0 \
				? self.required_api_version : self.minimum_instance_version

			// Generate specific error message based on the minor version component
			if VK_VERSION_MINOR(version_error) == 4 {
				err = Instance_Error {
					.Vulkan_Version_1_4_Unavailable, .ERROR_INITIALIZATION_FAILED, "Vulkan version 1.4 unavailable",
				}
				return
			} else if VK_VERSION_MINOR(version_error) == 3 {
				err = Instance_Error {
					.Vulkan_Version_1_3_Unavailable, .ERROR_INITIALIZATION_FAILED, "Vulkan version 1.3 unavailable",
				}
				return
			} else if VK_VERSION_MINOR(version_error) == 2 {
				err = Instance_Error {
					.Vulkan_Version_1_2_Unavailable, .ERROR_INITIALIZATION_FAILED, "Vulkan version 1.2 unavailable",
				}
				return
			} else if VK_VERSION_MINOR(version_error) == 1 {
				err = Instance_Error {
					.Vulkan_Version_1_1_Unavailable, .ERROR_INITIALIZATION_FAILED, "Vulkan version 1.1 unavailable",
				}
				return
			} else {
				err = Instance_Error {
					.Vulkan_Unavailable, .ERROR_INITIALIZATION_FAILED, "Vulkan version unavailable",
				}
				return
			}
		}
	}

	// The API version to use is set by required_api_version, unless it isn't set, then it
	// comes from minimum_instance_version
	api_version : u32 = vk.API_VERSION_1_0
	if self.required_api_version > vk.API_VERSION_1_0 {
		api_version = self.required_api_version
	} else if self.minimum_instance_version > 0 {
		api_version = self.minimum_instance_version
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		engineVersion      = self.engine_version,
		apiVersion         = api_version,
		applicationVersion = self.application_version,
	}
	app_info.pApplicationName =
		self.app_name != "" ? strings.clone_to_cstring(self.app_name, ta) : nil
	app_info.pEngineName =
		self.engine_name != "" ? strings.clone_to_cstring(self.engine_name, ta) : nil

	extensions := make([dynamic]cstring, ta)
	layers := make([dynamic]cstring, ta)

	for ext in self.extensions {
		append(&extensions, strings.clone_to_cstring(ext, ta))
	}
	if self.debug_callback != nil && self.use_debug_messenger && info.debug_utils_available {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}
	properties2_ext_enabled: bool
	if api_version < vk.API_VERSION_1_1 &&
			system_info_is_extension_available(info, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME) {
		properties2_ext_enabled = true
		append(&extensions, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
	}

	if len(self.layer_settings) > 0 {
		append(&extensions, vk.EXT_LAYER_SETTINGS_EXTENSION_NAME)
	}

	when ODIN_OS == .Darwin || #config(VK_KHR_portability_enumeration, false) {
		portability_enumeration_support: bool
		if is_extension_available(&info, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) {
			portability_enumeration_support = true
			append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
		}
	}

	if !self.headless_context {
		if system_info_is_extension_available(info, vk.KHR_SURFACE_EXTENSION_NAME) {
			append(&extensions, vk.KHR_SURFACE_EXTENSION_NAME)
		} else {
			err = Instance_Error {
				.Windowing_Extensions_Not_Present, .ERROR_INITIALIZATION_FAILED, "Required windowing extension not present!",
			}
			return
		}

		add_window_ext :: proc(
			info: ^System_Info,
			extension_name: cstring,
			extensions: ^[dynamic]cstring,
		) -> bool {
			if system_info_is_extension_available(info, string(extension_name)) {
				append(extensions, extension_name)
				return true
			}
			return false
		}

		when ODIN_OS == .Windows {
			added_window_exts := add_window_ext(
				info, vk.KHR_WIN32_SURFACE_EXTENSION_NAME, &extensions)
		} else when ODIN_OS == .Linux {
			added_window_exts := add_window_ext(
				info, vk.KHR_XCB_SURFACE_EXTENSION_NAME, &extensions)
			added_window_exts = add_window_ext(
				info, vk.KHR_XLIB_SURFACE_EXTENSION_NAME, &extensions) || added_window_exts
			added_window_exts = add_window_ext(
				info, vk.KHR_WAYLAND_SURFACE_EXTENSION_NAME, &extensions) || added_window_exts
		} else when ODIN_OS == .Darwin {
			added_window_exts := add_window_ext(
				info, vk.EXT_METAL_SURFACE_EXTENSION_NAME, &extensions)
		} else {
			#panic("Unsupported platform!")
		}

		if !added_window_exts {
			err = Instance_Error {
				.Windowing_Extensions_Not_Present, .ERROR_INITIALIZATION_FAILED, "Required windowing extension not present!",
			}
			return
		}
	}

	if !system_info_is_extensions_available(info, extensions[:]) {
		err = Instance_Error {
			.Requested_Extensions_Not_Present, .ERROR_INITIALIZATION_FAILED, "Requested extensions not present",
		}
		return
	}

	for layer in self.layers {
		append(&layers, strings.clone_to_cstring(layer, ta))
	}

	if self.enable_validation_layers || (self.request_validation_layers && info.validation_layers_available) {
		append(&layers, VALIDATION_LAYER_NAME)
	}

	if !system_info_is_layers_available(info, layers[:]) {
		err = Instance_Error {
			.Requested_Layers_Not_Present, .ERROR_INITIALIZATION_FAILED, "Requested layers not present",
		}
		return
	}

	pnext_chain := make([dynamic]^vk.BaseOutStructure, ta)

	messenger_create_info: vk.DebugUtilsMessengerCreateInfoEXT
	if self.use_debug_messenger {
		messenger_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
		messenger_create_info.pNext = nil
		messenger_create_info.messageSeverity = self.debug_message_severity
		messenger_create_info.messageType = self.debug_message_type
		messenger_create_info.pfnUserCallback = self.debug_callback
		messenger_create_info.pUserData = self.debug_user_data_pointer
		append(&pnext_chain, cast(^vk.BaseOutStructure)&messenger_create_info)
	}

	features: vk.ValidationFeaturesEXT
	if (len(self.enabled_validation_features) != 0 || len(self.disabled_validation_features) > 0) {
		features.sType = .VALIDATION_FEATURES_EXT
		features.pNext = nil
		features.enabledValidationFeatureCount = u32(len(self.enabled_validation_features))
		features.pEnabledValidationFeatures = raw_data(self.enabled_validation_features[:])
		features.disabledValidationFeatureCount = u32(len(self.disabled_validation_features))
		features.pDisabledValidationFeatures = raw_data(self.disabled_validation_features[:])
		append(&pnext_chain, cast(^vk.BaseOutStructure)&features)
	}

	checks: vk.ValidationFlagsEXT
	if (len(self.disabled_validation_checks) != 0) {
		checks.sType = .VALIDATION_FLAGS_EXT
		checks.pNext = nil
		checks.disabledValidationCheckCount = u32(len(self.disabled_validation_checks))
		checks.pDisabledValidationChecks = raw_data(self.disabled_validation_checks[:])
		append(&pnext_chain, cast(^vk.BaseOutStructure)&checks)
	}

	layer_settings: vk.LayerSettingsCreateInfoEXT
	if len(self.layer_settings) > 0 {
		layer_settings.sType = .LAYER_SETTINGS_CREATE_INFO_EXT
		layer_settings.pNext = nil
		layer_settings.settingCount = u32(len(self.layer_settings))
		layer_settings.pSettings = raw_data(self.layer_settings[:])
		append(&pnext_chain, cast(^vk.BaseOutStructure)&layer_settings)
	}

	instance_create_info := vk.InstanceCreateInfo{
		sType                   = .INSTANCE_CREATE_INFO,
		flags                   = self.flags,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
	}

	when ODIN_OS == .Darwin || #config(VK_KHR_portability_enumeration, false) {
		if portability_enumeration_support {
			instance_create_info.flags += { .ENUMERATE_PORTABILITY_KHR }
		}
	}

	setup_pnext_chain(&instance_create_info, &pnext_chain)

	vk_instance: vk.Instance
	vk_check(vk.CreateInstance(
		&instance_create_info, self.allocation_callbacks, &vk_instance,
	), "vk.CreateInstance failed", loc) or_return

	// Load the rest of the functions with our instance
	vk.load_proc_addresses(vk_instance)

	vk_debug_messenger: vk.DebugUtilsMessengerEXT
	if self.use_debug_messenger {
		debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			pNext           = nil,
			messageSeverity = self.debug_message_severity,
			messageType     = self.debug_message_type,
			pfnUserCallback = self.debug_callback,
			pUserData       = self.debug_user_data_pointer,
		}

		vk_check(vk.CreateDebugUtilsMessengerEXT(
			vk_instance,
			&debug_utils_create_info,
			self.allocation_callbacks,
			&vk_debug_messenger,
		), "vk.CreateDebugUtilsMessengerEXT failed", loc) or_return
	}

	instance = new_clone(Instance{
		instance                = vk_instance,
		debug_messenger         = vk_debug_messenger,
		headless                = self.headless_context,
		properties2_ext_enabled = properties2_ext_enabled,
		allocation_callbacks    = self.allocation_callbacks,
		instance_version        = instance_version,
		api_version             = api_version,
		allocator               = allocator,
	}, allocator)

	return
}

// Sets the name of the application. Defaults to "" if none is provided.
instance_builder_set_app_name :: proc(self: ^Instance_Builder, app_name: string) {
	self.app_name = app_name
}

// Sets the name of the engine. Defaults to "" if none is provided.
instance_builder_set_engine_name :: proc(self: ^Instance_Builder, engine_name: string) {
	self.engine_name = engine_name
}

// Sets the version of the application.
//
// Should be constructed with `vk.MAKE_VERSION`.
instance_builder_set_app_version_value :: proc(self: ^Instance_Builder, app_version: u32) {
	self.application_version = app_version
}

// Sets the (major, minor, patch) version of the application.
instance_builder_set_app_version_values :: proc(self: ^Instance_Builder, major, minor, patch: u32) {
	self.application_version = vk.MAKE_VERSION(major, minor, patch)
}

// Sets the version of the application.
instance_builder_set_app_version :: proc {
	instance_builder_set_app_version_value,
	instance_builder_set_app_version_values,
}

// Sets the version of the engine.
//
// Should be constructed with `vk.MAKE_VERSION`.
instance_builder_set_engine_version_value :: proc(self: ^Instance_Builder, engine_version: u32) {
	self.engine_version = engine_version
}

// Sets the (major, minor, patch) version of the engine.
instance_builder_set_engine_version_values :: proc(
	self: ^Instance_Builder,
	major, minor, patch: u32,
) {
	self.engine_version = vk.MAKE_VERSION(major, minor, patch)
}

// Sets the version of the engine.
instance_builder_set_engine_version :: proc {
	instance_builder_set_engine_version_value,
	instance_builder_set_engine_version_values,
}

// Require a vulkan API version. Will fail to create if this version isn't available.
//
// Should be constructed with `vk.MAKE_VERSION`.
instance_builder_require_api_version_value :: proc(
	self: ^Instance_Builder,
	required_api_version: u32,
) {
	self.required_api_version = required_api_version
}

// Sets the (major, minor, patch) for the required api version. Will fail to create if
// this version isn't available.
instance_builder_require_api_version_values :: proc(
	self: ^Instance_Builder,
	major, minor, patch: u32,
) {
	self.required_api_version = vk.MAKE_VERSION(major, minor, patch)
}

// Require a vulkan API version.
instance_builder_require_api_version :: proc {
	instance_builder_require_api_version_value,
	instance_builder_require_api_version_values,
}

// Overrides required API version for instance creation. Will fail to create if this
// version isn't available.
//
// Should be constructed with `vk.MAKE_VERSION`.
instance_builder_set_minimum_instance_version_value :: proc(
	self: ^Instance_Builder,
	minimum_instance_version: u32,
) {
	self.minimum_instance_version = minimum_instance_version
}

// Sets the (major, minor, patch) to overrides required API version for instance creation.
// Will fail to create if this version isn't available.
instance_builder_set_minimum_instance_version_values :: proc(
	self: ^Instance_Builder,
	major, minor, patch: u32,
) {
	self.minimum_instance_version = vk.MAKE_VERSION(major, minor, patch)
}

// Overrides required API version for instance creation.
instance_builder_set_minimum_instance_version :: proc {
	instance_builder_set_minimum_instance_version_value,
	instance_builder_set_minimum_instance_version_values,
}

// Adds a layer to be enabled.
//
// Will fail to create an instance if the layer isn't available.
instance_builder_enable_layer :: proc(self: ^Instance_Builder, layer_name: string) {
	append(&self.layers, layer_name)
}

// Add layers to be enabled.
//
// Will fail to create an instance if the layer aren't available.
instance_builder_enable_layers :: proc(self: ^Instance_Builder, layers: []string) {
	if len(layers) == 0 { return }
	for ext in layers {
		append(&self.layers, ext)
	}
}

// Adds an extension to be enabled.
//
// Will fail to create an instance if the extension isn't available.
instance_builder_enable_extension :: proc(self: ^Instance_Builder, extension_name: string) {
	if len(extension_name) == 0 { return }
	append(&self.extensions, extension_name)
}

// Add extensions to be enabled.
//
// Will fail to create an instance if the extension aren't available.
instance_builder_enable_extensions :: proc(self: ^Instance_Builder, extensions: []string) {
	if len(extensions) == 0 { return }
	for ext in extensions {
		append(&self.extensions, ext)
	}
}

// Enables the validation layers.
//
// Will fail to create an instance if the validation layers aren't available.
instance_builder_enable_validation_layers :: proc(
	self: ^Instance_Builder,
	enable_validation: bool = true,
) {
	self.enable_validation_layers = enable_validation
}

// Checks if the validation layers are available and loads them if they are.
instance_builder_request_validation_layers :: proc(
	self: ^Instance_Builder,
	enable_validation: bool = true,
) {
	self.request_validation_layers = enable_validation
}

// Default debug messenger.
//
// Feel free to copy-paste it into your own code, change it as needed, then call
// `instance_set_debug_callback()` to use that instead.
default_debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.eprintfln("[%v]: %s", messageTypes, pCallbackData.pMessage)
	return false // Applications must return false here
}

// Use a default debug callback that prints to `os.stderr`.
instance_builder_use_default_debug_messenger :: proc(self: ^Instance_Builder) {
	self.use_debug_messenger = true
	self.debug_callback = default_debug_callback
}

// Provide a user defined debug callback.
instance_builder_set_debug_callback :: proc(
	self: ^Instance_Builder,
	callback: vk.ProcDebugUtilsMessengerCallbackEXT,
) {
	self.use_debug_messenger = true
	self.debug_callback = callback
}

// Sets the void* to use in the debug messenger - only useful with a custom callback
instance_builder_set_debug_callback_user_data_pointer :: proc(
	self: ^Instance_Builder,
	user_data_pointer: rawptr,
) {
	self.debug_user_data_pointer = user_data_pointer
}

// Headless Mode does not load the required extensions for presentation. Defaults to `true`.
instance_builder_set_headless :: proc(self: ^Instance_Builder, headless: bool = true) {
	self.headless_context = headless
}

// Set what message severity is needed to trigger the callback.
instance_builder_set_debug_messenger_severity :: proc(
	self: ^Instance_Builder,
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
) {
	self.debug_message_severity = severity
}

// Add a message severity to the list that triggers the callback.
instance_builder_add_debug_messenger_severity :: proc(
	self: ^Instance_Builder,
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
) {
	self.debug_message_severity += severity
}

// Set what message type triggers the callback.
instance_builder_set_debug_messenger_type :: proc(
	self: ^Instance_Builder,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
) {
	self.debug_message_type = type
}

// Add a message type to the list of that triggers the callback.
instance_builder_add_debug_messenger_type :: proc(
	self: ^Instance_Builder,
	type: vk.DebugUtilsMessageTypeFlagsEXT,
) {
	self.debug_message_type += type
}

// Disable some validation checks.
//
// Checks: All, and Shaders
instance_builder_add_validation_disable :: proc(
	self: ^Instance_Builder,
	check: vk.ValidationCheckEXT,
) {
	append(&self.disabled_validation_checks, check)
}

// Enables optional parts of the validation layers.
//
// Parts: best practices, gpu assisted, and gpu assisted reserve binding slot.
instance_builder_add_validation_feature_enable :: proc(
	self: ^Instance_Builder,
	enable: vk.ValidationFeatureEnableEXT,
) {
	append(&self.enabled_validation_features, enable)
}

// Disables sections of the validation layers.
//
// Options: All, shaders, thread safety, api parameters, object lifetimes, core checks,
// and unique handles.
instance_builder_add_validation_feature_disable :: proc(
	self: ^Instance_Builder,
	disable: vk.ValidationFeatureDisableEXT,
) {
	append(&self.disabled_validation_features, disable)
}

// Provide custom allocation callbacks.
instance_builder_set_allocation_callbacks :: proc(
	self: ^Instance_Builder,
	callbacks: ^vk.AllocationCallbacks,
) {
	self.allocation_callbacks = callbacks
}

// Set a setting on a requested layer via `vk.EXT_layer_settings`.
instance_builder_add_layer_setting :: proc(self: ^Instance_Builder, setting: vk.LayerSettingEXT) {
	append(&self.layer_settings, setting)
}

// Set many settings on a requested layer via `vk.EXT_layer_settings`.
instance_builder_add_layer_settings :: proc(self: ^Instance_Builder, settings: []vk.LayerSettingEXT) {
	append(&self.layer_settings, ..settings)
}

// =============================================================================
// Instance
// =============================================================================

Instance :: struct {
	instance               : vk.Instance,
	debug_messenger        : vk.DebugUtilsMessengerEXT,
	allocation_callbacks   : ^vk.AllocationCallbacks,
	get_instance_proc_addr : vk.ProcGetInstanceProcAddr,
	get_device_proc_addr   : vk.ProcGetDeviceProcAddr,
	instance_version       : u32,
	api_version            : u32,
	headless               : bool,
	properties2_ext_enabled: bool,
	allocator              : runtime.Allocator,
}

// Destroy the surface created from this instance.
destroy_surface :: proc(self: ^Instance, surface: vk.SurfaceKHR, loc := #caller_location) {
	assert(self != nil && self.instance != nil, "Invalid Instance", loc)
	assert(surface != 0, "Invalid Surface", loc)
	vk.DestroySurfaceKHR(self.instance, surface, self.allocation_callbacks)
}

// Destroy the instance and the debug messenger.
destroy_instance :: proc(self: ^Instance, loc := #caller_location) {
	assert(self != nil && self.instance != nil, "Invalid Instance", loc)
	if self.debug_messenger != 0 {
		vk.DestroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, nil)
	}
	vk.DestroyInstance(self.instance, nil)
	free(self, self.allocator)
}

// =============================================================================
// Physical device selector
// =============================================================================

Preferred_Device_Type :: enum {
	Other,
	Integrated,
	Discrete,
	Virtual_gpu,
	Cpu,
}

Unsuitability_Reasons :: struct {
	reasons:   [dynamic]string,
	arena:     mem.Arena,
	arena_buf: []byte,
}

Physical_Device_Selector :: struct {
	// Instance info
	instance:                  struct {
		handle:                  vk.Instance,
		surface:                 vk.SurfaceKHR,
		version:                 u32,
		headless:                bool,
		properties2_ext_enabled: bool,
	},

	// Selection criteria
	criteria:                  struct {
		name:                             string,
		preferred_type:                   Preferred_Device_Type,
		allow_any_type:                   bool,
		require_present:                  bool,
		require_dedicated_transfer_queue: bool,
		require_dedicated_compute_queue:  bool,
		require_separate_transfer_queue:  bool,
		require_separate_compute_queue:   bool,
		required_mem_size:                vk.DeviceSize,
		required_extensions:              [dynamic]string,
		required_version:                 u32,
		required_features:                vk.PhysicalDeviceFeatures,
		required_features2:               vk.PhysicalDeviceFeatures2,
		extended_features_chain:          [dynamic]Generic_Feature,
		defer_surface_initialization:     bool,
		use_first_gpu_unconditionally:    bool,
		enable_portability_subset:        bool,
	},

	// Unsuitability reasons
	unsuitability_reasons:     [dynamic]string,
	unsuitability_arena:       mem.Arena,
	unsuitability_arena_buf:   []byte,

	// Internal
	allocator:                 runtime.Allocator,
}

physical_device_selector_default :: proc(
	self: ^Physical_Device_Selector,
	instance: ^Instance,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) {
	// Instance information
	self.instance = {
		handle                  = instance.instance,
		surface                 = surface,
		version                 = instance.instance_version,
		headless                = instance.headless,
		properties2_ext_enabled = instance.properties2_ext_enabled,
	}

	// Physical device criteria
	self.criteria = {
		preferred_type            = .Discrete,
		allow_any_type            = true,
		require_present           = !instance.headless,
		required_version          = instance.api_version,
		enable_portability_subset = true,
	}

	// Internal
	self.allocator = allocator

	// Physical device criteria (set allocator's)
	self.criteria.required_extensions.allocator = allocator
	self.criteria.extended_features_chain.allocator = allocator
}

// Requires a `vkb.Instance` to construct, needed to pass instance creation info.
create_physical_device_selector_default :: proc(
	instance: ^Instance,
	allocator := context.allocator,
) -> ^Physical_Device_Selector {
	out := new(Physical_Device_Selector, allocator)
	physical_device_selector_default(out, instance, 0, allocator)
	out.unsuitability_arena_buf = make([]byte, 64 * mem.Kilobyte, allocator)
	mem.arena_init(&out.unsuitability_arena, out.unsuitability_arena_buf)
	return out
}

// Requires a `vkb.Instance` to construct, needed to pass instance creation info,
// optionally specify the surface here.
create_physical_device_selector_with_surface :: proc(
	instance: ^Instance,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) -> ^Physical_Device_Selector {
	out := new(Physical_Device_Selector, allocator)
	physical_device_selector_default(out, instance, surface, allocator)
	return out
}

// Requires a `vkb.Instance` to construct, needed to pass instance creation info.
create_physical_device_selector :: proc {
	create_physical_device_selector_default,
	create_physical_device_selector_with_surface,
}

destroy_physical_device_selector :: proc(self: ^Physical_Device_Selector) {
	context.allocator = self.allocator
	delete(self.unsuitability_arena_buf)
	delete(self.criteria.required_extensions)
	delete(self.criteria.extended_features_chain)
	free(self)
}

// Return all devices which are considered suitable - intended for applications
// which want to let the user pick the physical device.
//
// NOTE: The returned slice is allocated with the given allocator, but the physical
// devices need to be destroyed with `destroy_physical_device`.
physical_device_selector_select_devices :: proc(
	self: ^Physical_Device_Selector,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	devices: []^Physical_Device,
	err: Error,
) {
	if self.criteria.require_present && !self.criteria.defer_surface_initialization {
		if self.instance.surface == 0 {
			err = Physical_Device_Error {
				.No_Surface_Provided, .ERROR_INITIALIZATION_FAILED, "Present is required, but no surface is provided", {},
			}
			return
		}
	}

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	// Get the vk.PhysicalDevice handles on the system
	physical_device_count: u32
	vk_check(vk.EnumeratePhysicalDevices(
		self.instance.handle, &physical_device_count, nil,
	), "Failed to enumerate physical devices count", loc) or_return

	vk_physical_devices := make([]vk.PhysicalDevice, physical_device_count, ta)
	vk_check(vk.EnumeratePhysicalDevices(
		self.instance.handle, &physical_device_count, raw_data(vk_physical_devices),
	), "Failed to enumerate physical devices", loc) or_return

	// Handle first GPU selection separately
	// if this option is set, always return only the first physical device found
	if self.criteria.use_first_gpu_unconditionally && len(vk_physical_devices) > 0 {
		devices = make([]^Physical_Device, 1, allocator)

		physical_device := physical_device_selector_populate_device_details(
			self,
			vk_physical_devices[0],
			self.criteria.extended_features_chain[:],
			allocator,
			loc,
		) or_return

		physical_device_selector_fill_criteria(self, physical_device)

		devices[0] = physical_device

		return
	}

	suitable := make([dynamic]^Physical_Device, ta)
	partial := make([dynamic]^Physical_Device, ta)

	for vk_physical_device in vk_physical_devices {
		physical_device := physical_device_selector_populate_device_details(
			self,
			vk_physical_device,
			self.criteria.extended_features_chain[:],
			allocator,
			loc,
		) or_return

		physical_device.suitable = physical_device_selector_is_device_suitable(self, physical_device)

		switch physical_device.suitable {
		case .Yes:
			append(&suitable, physical_device)
		case .Partial:
			append(&partial, physical_device)
		case .No:
			destroy_physical_device(physical_device)
		}
	}

	total_suitable := len(suitable)
	total_partial := len(partial)

	// No suitable devices found
	if total_suitable == 0 && total_partial == 0 {
		err = Physical_Device_Error {
			kind = .No_Suitable_Device,
			result = .ERROR_INITIALIZATION_FAILED,
			message = "No suitable device found",
			unsuitability_reasons = self.unsuitability_reasons[:],
		}
		return
	}

	out := make([dynamic]^Physical_Device, allocator)
	reserve(&out, total_suitable + total_partial)

	// Add suitable devices first, then partial
	append(&out, ..suitable[:])
	append(&out, ..partial[:])

	// Make the physical device ready to be used to create a Device from it
	for &pd in out {
		physical_device_selector_fill_criteria(self, pd)
	}

	return out[:], nil
}

physical_device_selector_select :: proc(
	self: ^Physical_Device_Selector,
	allocator := context.allocator,
) -> (
	physical_device: ^Physical_Device,
	err: Error,
) {
	selected_devices := physical_device_selector_select_devices(self, allocator) or_return
	defer delete(selected_devices, allocator)

	total_devices := len(selected_devices)
	physical_device = selected_devices[0]

	// Destroy the remaining physical devices...
	if total_devices > 1 {
		for i in 1 ..< total_devices {
			destroy_physical_device(selected_devices[i])
		}
	}

	return
}

// Return the names of all devices which are considered suitable - intended for
// applications which want to let the user pick the physical device.
//
// NOTE: The returned slice and all strings are allocated with the given allocator.
physical_device_selector_select_device_names :: proc(
	self: ^Physical_Device_Selector,
	allocator := context.allocator,
) -> (
	names: []string,
	ok: Error,
) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	selected_devices := physical_device_selector_select_devices(self, ta) or_return

	names = make([]string, len(selected_devices), allocator)
	for &pd, i in selected_devices {
		names[i] = strings.clone(pd.name, allocator)
		destroy_physical_device(pd)
	}

	return
}

// Set the surface in which the physical device should render to.
//
// Be sure to set it if swapchain functionality is to be used.
physical_device_selector_set_surface :: proc(self: ^Physical_Device_Selector, surface: vk.SurfaceKHR) {
	self.instance.surface = surface
}

// Set the name of the device to select.
physical_device_selector_set_name :: proc(self: ^Physical_Device_Selector, name: string) {
	if len(name) > 0 {
		if len(self.criteria.name) > 0 {
			delete(self.criteria.name, self.allocator)
		}
		self.criteria.name = strings.clone(name, self.allocator)
	}
}

// Set the desired physical device type to select.
//
// Defaults to `Preferred_Device_Type.discrete`.
physical_device_selector_prefer_gpu_device_type :: proc(
	self: ^Physical_Device_Selector,
	type: Preferred_Device_Type = .Discrete,
) {
	self.criteria.preferred_type = type
}

// Allow selection of a gpu device type that isn't the preferred physical device type.
//
// Defaults to `true`.
physical_device_selector_allow_any_gpu_device_type :: proc(
	self: ^Physical_Device_Selector,
	allow_any_type := true,
) {
	self.criteria.allow_any_type = allow_any_type
}

// Require that a physical device supports presentation.
//
// Defaults to `true`.
physical_device_selector_require_present :: proc(self: ^Physical_Device_Selector, require := true) {
	self.criteria.require_present = require
}

// Require a queue family that supports transfer operations but not graphics nor compute.
physical_device_selector_require_dedicated_transfer_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_dedicated_transfer_queue = true
}

// Require a queue family that supports compute operations but not graphics nor transfer.
physical_device_selector_require_dedicated_compute_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_dedicated_compute_queue = true
}

// Require a queue family that supports transfer operations but not graphics.
physical_device_selector_require_separate_transfer_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_separate_transfer_queue = true
}

// Require a queue family that supports compute operations but not graphics.
physical_device_selector_require_separate_compute_queue :: proc(self: ^Physical_Device_Selector) {
	self.criteria.require_separate_compute_queue = true
}

// Require a memory heap from `vk.MEMORY_PROPERTY_DEVICE_LOCAL` with `size` memory available.
physical_device_selector_required_device_memory_size :: proc(
	self: ^Physical_Device_Selector,
	size: vk.DeviceSize,
) {
	self.criteria.required_mem_size = size
}

// Require a physical device which supports a specific extension.
physical_device_selector_add_required_extension :: proc(
	self: ^Physical_Device_Selector,
	extension: string,
) {
	append(&self.criteria.required_extensions, extension)
}

// Require a physical device which supports a set of extensions.
physical_device_selector_add_required_extensions :: proc(
	self: ^Physical_Device_Selector,
	extensions: []string,
) {
	for ext in extensions {
		append(&self.criteria.required_extensions, ext)
	}
}

// Require a physical device that supports the given minimum version of Vulkan.
physical_device_selector_set_minimum_version_value :: proc(
	self: ^Physical_Device_Selector,
	version: u32,
) {
	self.criteria.required_version = version
}

// Require a physical device that supports a minimum (major, minor) version of Vulkan.
physical_device_selector_set_minimum_version_values :: proc(
	self: ^Physical_Device_Selector,
	major, minor: u32,
) {
	self.criteria.required_version = vk.MAKE_VERSION(major, minor, 0)
}

physical_device_selector_set_minimum_version :: proc {
	physical_device_selector_set_minimum_version_value,
	physical_device_selector_set_minimum_version_values,
}

// By default `Physical_Device_Selector` enables the portability subset if available.
// This procedure disables that behavior.
physical_device_selector_disable_portability_subset :: proc(self: ^Physical_Device_Selector) {
	self.criteria.enable_portability_subset = false
}

// Require a physical device which supports the features in `vk.PhysicalDeviceFeatures`.
physical_device_selector_set_required_features :: proc(
	self: ^Physical_Device_Selector,
	features: vk.PhysicalDeviceFeatures,
) {
	self.criteria.required_features = features
}

// Require a physical device which supports a specific set of general/extension features.
//
// If this function is used, the user should not put their own `vk.PhysicalDeviceFeatures2` in
// the `pNext` chain of `vk.DeviceCreateInfo`.
physical_device_selector_add_required_extension_features :: proc(
	self: ^Physical_Device_Selector,
	feature: $T,
) {
	feature := feature
	generic := create_generic_features(&feature)
	append(&self.criteria.extended_features_chain, generic)
}

// Require a physical device which supports the features in `vk.PhysicalDeviceVulkan11Features`.
//
// Must have vulkan version 1.2 - This is due to the `vk.PhysicalDeviceVulkan11Features` struct being
// added in 1.2, not 1.1.
physical_device_selector_set_required_features_11 :: proc(
	self: ^Physical_Device_Selector,
	features_11: vk.PhysicalDeviceVulkan11Features,
) {
	features_11 := features_11
	features_11.sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
	physical_device_selector_add_required_extension_features(self, features_11)
}

// Require a physical device which supports the features in `vk.PhysicalDeviceVulkan12Features`.
//
// Must have vulkan version 1.2.
physical_device_selector_set_required_features_12 :: proc(
	self: ^Physical_Device_Selector,
	features_12: vk.PhysicalDeviceVulkan12Features,
) {
	features_12 := features_12
	features_12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	physical_device_selector_add_required_extension_features(self, features_12)
}

// Require a physical device which supports the features in `vk.PhysicalDeviceVulkan13Features`.
//
// Must have vulkan version 1.3.
physical_device_selector_set_required_features_13 :: proc(
	self: ^Physical_Device_Selector,
	features_13: vk.PhysicalDeviceVulkan13Features,
) {
	features_13 := features_13
	features_13.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES
	physical_device_selector_add_required_extension_features(self, features_13)
}

// Require a physical device which supports the features in `vk.PhysicalDeviceVulkan14Features`.
//
// Must have vulkan version 1.4.
physical_device_selector_set_required_features_14 :: proc(
	self: ^Physical_Device_Selector,
	features_14: vk.PhysicalDeviceVulkan14Features,
) {
	features_14 := features_14
	features_14.sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES
	physical_device_selector_add_required_extension_features(self, features_14)
}

// Used when surface creation happens after physical device selection.
//
// Warning: This disables checking if the physical device supports a given surface.
physical_device_selector_defer_surface_initialization :: proc(self: ^Physical_Device_Selector) {
	self.criteria.defer_surface_initialization = true
}

// Ignore all criteria and choose the first physical device that is available. Only
// use when: The first gpu in the list may be set by global user preferences and an
// application may wish to respect it.
physical_device_selector_select_first_device_unconditionally :: proc(
	self: ^Physical_Device_Selector,
	unconditionally := true,
) {
	self.criteria.use_first_gpu_unconditionally = unconditionally
}

@(private)
physical_device_selector_populate_device_details :: proc(
	self: ^Physical_Device_Selector,
	vk_phys_device: vk.PhysicalDevice,
	features_chain: []Generic_Feature,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> (
	pd: ^Physical_Device,
	err: Error,
) {
	pd = create_physical_device(self, vk_phys_device, allocator, loc)
	defer if err != nil { destroy_physical_device(pd) }

	pd_allocator := mem.arena_allocator(&pd.arena)

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	// Get device properties
	vk.GetPhysicalDeviceProperties(vk_phys_device, &pd.properties)

	// Set device name
	pd.name = strings.clone_from(byte_arr_str(&pd.properties.deviceName), pd_allocator)

	// Get the device queue families
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(vk_phys_device, &queue_family_count, nil)

	pd.queue_families = make([]vk.QueueFamilyProperties, int(queue_family_count), pd_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		vk_phys_device,
		&queue_family_count,
		raw_data(pd.queue_families),
	)

	// Get device features and memory properties
	vk.GetPhysicalDeviceFeatures(vk_phys_device, &pd.features)
	vk.GetPhysicalDeviceMemoryProperties(vk_phys_device, &pd.memory_properties)

	// Get supported device extensions
	property_count: u32
	vk_check(vk.EnumerateDeviceExtensionProperties(
		vk_phys_device, nil, &property_count, nil,
	), "Failed to enumerate device extensions properties count", loc) or_return

	available_extensions := make([]vk.ExtensionProperties, property_count, ta)
	vk_check(vk.EnumerateDeviceExtensionProperties(
		vk_phys_device, nil, &property_count, raw_data(available_extensions),
	), "Failed to enumerate device extensions properties", loc) or_return

	pd.available_extensions = make([]string, property_count, pd_allocator)
	for &ext, i in available_extensions {
		ext_name := byte_arr_str(&ext.extensionName)
		pd.available_extensions[i] = strings.clone(ext_name, pd_allocator)
	}

	// We use binary search later to optimize the query, this requires data to be sorted
	slice.sort(pd.available_extensions)

	// Same value as the non-KHR version
	pd.features2.sType = .PHYSICAL_DEVICE_FEATURES_2
	pd.properties2_ext_enabled = self.instance.properties2_ext_enabled

	instance_is_1_1 := self.instance.version >= vk.API_VERSION_1_1
	if len(features_chain) > 0 && (instance_is_1_1 || self.instance.properties2_ext_enabled) {
		// Setup the pNext chain
		local_features := generic_features_setup_pnext_chain(features_chain)

		// Query the features
		if (instance_is_1_1) {
			vk.GetPhysicalDeviceFeatures2(vk_phys_device, &local_features)
		} else {
			vk.GetPhysicalDeviceFeatures2KHR(vk_phys_device, &local_features)
		}

		// The results are now in the features_chain, we can now compare
		// requested vs supported features later
	}

	return
}

@(private)
physical_device_selector_fill_criteria :: proc(
	self: ^Physical_Device_Selector,
	physical_device: ^Physical_Device,
) {
	physical_device.features = self.criteria.required_features

	reserve(&physical_device.extended_features_chain, len(self.criteria.extended_features_chain))
	append(&physical_device.extended_features_chain, ..self.criteria.extended_features_chain[:])

	portability_ext_available: bool
	if self.criteria.enable_portability_subset {
		// Check if portability subset extension is available
		for &extension in physical_device.available_extensions {
			if extension == vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME {
				portability_ext_available = true
				break
			}
		}
	}

	clear(&physical_device.extensions_to_enable)

	// Add required extensions first
	if len(self.criteria.required_extensions) > 0 {
		append(&physical_device.extensions_to_enable, ..self.criteria.required_extensions[:])
	}

	// Add portability subset if available
	if portability_ext_available {
		append(&physical_device.extensions_to_enable, vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME)
	}

	// Sort for quick lookup
	slice.sort(physical_device.extensions_to_enable[:])
}

@(private)
physical_device_selector_is_device_suitable :: proc(
	self: ^Physical_Device_Selector,
	pd: ^Physical_Device,
) -> (
	suitable: Physical_Device_Suitable,
) {
	suitable = .Yes

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = self.allocator == context.temp_allocator)

	mem.arena_free_all(&self.unsuitability_arena)
	reasons_alloc := mem.arena_allocator(&self.unsuitability_arena)

	// Check if physical device name match criteria
	if len(self.criteria.name) > 0 && self.criteria.name != pd.name {
		append(&self.unsuitability_reasons,
			fmt.aprintf("Device name [%s] doesn't match requested name [%s]",
				pd.name,
				self.criteria.name,
				allocator = reasons_alloc))
		return .No
	}

	if self.criteria.required_version > pd.properties.apiVersion {
		supported_major := VK_VERSION_MAJOR(pd.properties.apiVersion)
		supported_minor := VK_VERSION_MINOR(pd.properties.apiVersion)

		required_major := VK_VERSION_MAJOR(self.criteria.required_version)
		required_minor := VK_VERSION_MINOR(self.criteria.required_version)

		append(&self.unsuitability_reasons,
			fmt.aprintf("API version [%d.%d] is lower than required version [%d.%d]",
				supported_major,
				supported_minor,
				required_major,
				required_minor,
				allocator = reasons_alloc))

		return .No
	}

	dedicated_compute :=
		get_dedicated_queue_index(
			pd.queue_families, {.COMPUTE}, {.TRANSFER}) != vk.QUEUE_FAMILY_IGNORED

	dedicated_transfer :=
		get_dedicated_queue_index(
			pd.queue_families, {.TRANSFER}, {.COMPUTE}) != vk.QUEUE_FAMILY_IGNORED

	separate_compute :=
		get_separate_queue_index(
			pd.queue_families, {.COMPUTE}, {.TRANSFER}) != vk.QUEUE_FAMILY_IGNORED

	separate_transfer :=
		get_separate_queue_index(
			pd.queue_families, {.TRANSFER}, {.COMPUTE}) != vk.QUEUE_FAMILY_IGNORED

	present_queue :=
		get_present_queue_index(
			pd.physical_device, self.instance.surface, pd.queue_families) != vk.QUEUE_FAMILY_IGNORED

	if self.criteria.require_dedicated_compute_queue && !dedicated_compute {
		append(&self.unsuitability_reasons, "No dedicated compute queue")
		return .No
	}

	if self.criteria.require_dedicated_transfer_queue && !dedicated_transfer {
		append(&self.unsuitability_reasons, "No dedicated transfer queue")
		return .No
	}

	if self.criteria.require_separate_compute_queue && !separate_compute {
		append(&self.unsuitability_reasons, "No separate compute queue")
		return .No
	}

	if self.criteria.require_separate_transfer_queue && !separate_transfer {
		append(&self.unsuitability_reasons, "No separate transfer queue")
		return .No
	}

	if self.criteria.require_present && !present_queue && !self.criteria.defer_surface_initialization {
		append(&self.unsuitability_reasons, "No queue capable of present operations")
		return .No
	}

	unsupported_extensions := find_unsupported_extensions_in_list(
		pd.available_extensions,
		self.criteria.required_extensions[:],
		ta,
	)

	if len(unsupported_extensions) > 0 {
		for unsupported_ext in unsupported_extensions {
			append(&self.unsuitability_reasons,
				fmt.aprintf("Device extension [%s] not supported",
					unsupported_ext,
					allocator = reasons_alloc))
		}
		return .No
	}

	if !self.criteria.defer_surface_initialization && self.criteria.require_present {
		// Supported formats
		format_count: u32
		if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
			pd.physical_device,
			self.instance.surface,
			&format_count,
			nil,
		); res != .SUCCESS {
			append(&self.unsuitability_reasons,
				fmt.aprintf("vk.GetPhysicalDeviceSurfaceFormatsKHR returned error code [%s]",
					res,
					allocator = reasons_alloc))
			return .No
		}

		// Supported present modes
		present_mode_count: u32
		if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
			pd.physical_device,
			self.instance.surface,
			&present_mode_count,
			nil,
		); res != .SUCCESS {
			append(&self.unsuitability_reasons,
				fmt.aprintf("vk.GetPhysicalDeviceSurfacePresentModesKHR returned error code [%s]",
					res,
					allocator = reasons_alloc))
			return .No
		}
	}

	preferred_type := cast(vk.PhysicalDeviceType)self.criteria.preferred_type
	if pd.properties.deviceType != preferred_type {
		if self.criteria.allow_any_type {
			suitable = .Partial
		} else {
			append(&self.unsuitability_reasons,
				fmt.aprintf("Device type [%v] is not of preferred type [%s]",
					pd.properties.deviceType,
					preferred_type,
					allocator = reasons_alloc))
			return .No
		}
	}

	unsupported_features := find_unsupported_features_in_list(
		self.criteria.required_features,
		pd.features,
		self.criteria.extended_features_chain[:],
		pd.extended_features_chain[:],
		ta,
	)

	if len(unsupported_features) > 0 {
		for unsupported_feat in unsupported_features {
			append(&self.unsuitability_reasons,
				fmt.aprintf("Device feature [%s] not supported",
					unsupported_feat,
					allocator = reasons_alloc))
		}
		return .No
	}

	// Check required memory size
	for i: u32 = 0; i < pd.memory_properties.memoryHeapCount; i += 1 {
		if .DEVICE_LOCAL in pd.memory_properties.memoryHeaps[i].flags {
			if pd.memory_properties.memoryHeaps[i].size < self.criteria.required_mem_size {
				append(&self.unsuitability_reasons,
					"Did not contain a Device Local memory heap with enough size")
				return .No
			}
		}
	}

	return
}

// -----------------------------------------------------------------------------
// Physical Device
// -----------------------------------------------------------------------------

Physical_Device_Suitable :: enum {
	Yes,
	Partial,
	No,
}

Physical_Device :: struct {
	// Properties
	name:                         string,
	physical_device:              vk.PhysicalDevice,
	surface:                      vk.SurfaceKHR,
	features:                     vk.PhysicalDeviceFeatures,
	properties:                   vk.PhysicalDeviceProperties,
	memory_properties:            vk.PhysicalDeviceMemoryProperties,

	// For use when build the Device
	instance_version:             u32,
	extensions_to_enable:         [dynamic]string,
	available_extensions:         []string,
	queue_families:               []vk.QueueFamilyProperties,
	extended_features_chain:      [dynamic]Generic_Feature,
	features2:                    vk.PhysicalDeviceFeatures2,
	defer_surface_initialization: bool,
	properties2_ext_enabled:      bool,
	suitable:                     Physical_Device_Suitable,

	// Internal
	allocator:                    runtime.Allocator,
	arena_buf:                    []byte,
	arena:                        mem.Arena,
}

@(private)
create_physical_device :: proc(
	selector: ^Physical_Device_Selector,
	vk_phys_device: vk.PhysicalDevice,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> (
	pd: ^Physical_Device,
) {
	pd = new_clone(Physical_Device{
		physical_device              = vk_phys_device,
		surface                      = selector.instance.surface,
		defer_surface_initialization = selector.criteria.defer_surface_initialization,
		instance_version             = selector.instance.version,
		allocator                    = allocator,
	}, allocator)
	assert(pd != nil, "Failed to allocate a Physical Device object")

	// Initialize an arena allocator primarily to clone the device extensions strings
	// Typical devices commonly expose 200-350 extensions
	pd.arena_buf = make([]byte, 64 * mem.Kilobyte, allocator)
	mem.arena_init(&pd.arena, pd.arena_buf)

	pd.extensions_to_enable.allocator = allocator
	pd.extended_features_chain.allocator = allocator

	return
}

destroy_physical_device :: proc(self: ^Physical_Device, loc := #caller_location) {
	assert(self != nil && self.physical_device != nil, "Invalid Physical Device", loc)
	context.allocator = self.allocator
	delete(self.arena_buf)
	delete(self.extensions_to_enable)
	delete(self.extended_features_chain)
	free(self)
}

// Has a queue family that supports compute operations but not graphics nor transfer.
physical_device_has_dedicated_compute_queue :: proc(self: ^Physical_Device) -> bool {
	return get_dedicated_queue_index(
		self.queue_families, { .COMPUTE }, { .TRANSFER }) != vk.QUEUE_FAMILY_IGNORED
}

// Has a queue family that supports transfer operations but not graphics.
physical_device_has_separate_compute_queue :: proc(self: ^Physical_Device) -> bool {
	return get_separate_queue_index(
		self.queue_families, { .COMPUTE }, { .TRANSFER }) != vk.QUEUE_FAMILY_IGNORED
}

// Has a queue family that supports transfer operations but not graphics nor compute.
physical_device_has_dedicated_transfer_queue :: proc(self: ^Physical_Device) -> bool {
	return get_dedicated_queue_index(
		self.queue_families, { .TRANSFER }, { .COMPUTE }) != vk.QUEUE_FAMILY_IGNORED
}

// Has a queue family that supports transfer operations but not graphics.
physical_device_has_separate_transfer_queue :: proc(self: ^Physical_Device) -> bool {
	return get_separate_queue_index(
		self.queue_families, { .TRANSFER }, { .COMPUTE }) != vk.QUEUE_FAMILY_IGNORED
}

// Advanced: Get the `vk.QueueFamilyProperties` of the device if special queue setup is needed.
physical_device_get_queue_families :: proc(self: ^Physical_Device) -> []vk.QueueFamilyProperties {
	return self.queue_families
}

// Find a queue family that supports the required flags, preferring dedicated queues.
physical_device_find_queue_family_index :: proc(
	self: ^Physical_Device,
	flags: vk.QueueFlags,
) -> (
	index: u32,
) {
	// Helper to find a dedicated queue family
	find_dedicated_queue_family_index :: proc(
		props: []vk.QueueFamilyProperties,
		require: vk.QueueFlags,
		avoid: vk.QueueFlags,
	) -> u32 {
		for &prop, i in props {
			is_suitable := (prop.queueFlags >= require)
			is_dedicated := (prop.queueFlags & avoid) == {}

			if prop.queueCount > 0 && is_suitable && is_dedicated {
				return u32(i)
			}
		}
		return vk.QUEUE_FAMILY_IGNORED
	}

	// Try to find dedicated compute queue (no graphics)
	if .COMPUTE in flags {
		q := find_dedicated_queue_family_index(
			self.queue_families,
			flags,
			{.GRAPHICS},
		)
		if q != vk.QUEUE_FAMILY_IGNORED {
			return q
		}
	}

	// Try to find dedicated transfer queue (no graphics)
	if .TRANSFER in flags {
		q := find_dedicated_queue_family_index(
			self.queue_families,
			flags,
			{.GRAPHICS},
		)
		if q != vk.QUEUE_FAMILY_IGNORED {
			return q
		}
	}

	// Fall back to any suitable queue (no avoidance)
	return find_dedicated_queue_family_index(self.queue_families, flags, {})
}

// Query the list of extensions which should be enabled.
//
// Note: Returns a view of the internal slice.
physical_device_get_extensions :: proc(self: ^Physical_Device) -> []string {
	return self.extensions_to_enable[:]
}

// Query the list of extensions which the physical device supports.
//
// Note: Returns a view of the internal slice.
physical_device_get_available_extensions :: proc(self: ^Physical_Device) -> []string {
	return self.available_extensions[:]
}

// Returns true if an extension should be enabled on the device.
physical_device_is_extension_present :: proc(self: ^Physical_Device, ext: string) -> (found: bool) {
	_, found = slice.binary_search(self.available_extensions[:], ext)
	return
}

// If the given extension is present, make the extension be enabled on the device.
//
// Returns `true` the extension is present.
physical_device_enable_extension_if_present :: proc(
	self: ^Physical_Device,
	extension: string,
) -> (
	ok: bool,
) {
	if ok = physical_device_is_extension_present(self, extension); ok {
		append(&self.extensions_to_enable, extension)
	}
	return
}

// If all the given extensions are present, make all the extensions be enabled on the device.
//
// Returns `true` if all the extensions are present.
physical_device_enable_extensions_if_present :: proc(
	self: ^Physical_Device,
	extensions: []string,
) -> (
	ok: bool,
) {
	for ext in extensions {
		if !physical_device_is_extension_present(self, ext) {
			return
		}
	}

	append(&self.extensions_to_enable, ..extensions[:])

	return true
}

physical_device_get_supported_features :: proc(
	self: ^Physical_Device,
	features2: ^vk.PhysicalDeviceFeatures2,
) {
	instance_is_1_1 := self.instance_version >= vk.API_VERSION_1_1
	if !(instance_is_1_1 || !self.properties2_ext_enabled) {
		return
	}
	if (instance_is_1_1) {
		vk.GetPhysicalDeviceFeatures2(self.physical_device, features2)
	} else {
		vk.GetPhysicalDeviceFeatures2KHR(self.physical_device, features2)
	}
}

// If the features from `features_to_enable` are all present, make all of the
// features be enable on the device.
//
// Returns `true` if all the features are present.
physical_device_enable_features_if_present :: proc(
	self: ^Physical_Device,
	features_to_enable: vk.PhysicalDeviceFeatures,
) -> (
	ok: bool,
) {
	actual_pdf: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(self.physical_device, &actual_pdf)
	if ok = check_features_10(features_to_enable, actual_pdf); ok {
		merge_features(&self.features, features_to_enable)
	}
	return
}

// If the features from the provided features struct are all present, make all of
// the features be enable on the device.
//
// Returns `true` if all of the features are present.
physical_device_enable_extension_features_if_present :: proc(
	self: ^Physical_Device,
	features: $T,
	loc := #caller_location,
) -> (
	supported: bool,
) {
	features := features

	query_features := T {
		sType = features.sType,
	}

	features_generic := create_generic_features(&features, loc)
	local_features := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &query_features,
	}

	instance_is_1_1 := self.instance_version >= vk.API_VERSION_1_1
	if !(instance_is_1_1 || !self.properties2_ext_enabled) {
		return false
	}

	// Query supported features
	if instance_is_1_1 {
		vk.GetPhysicalDeviceFeatures2(self.physical_device, &local_features)
	} else {
		vk.GetPhysicalDeviceFeatures2KHR(self.physical_device, &local_features)
	}

	supported_generic := create_generic_features(&query_features, loc)

	// Check if requested features are supported and merge values if any
	add_chain_blk: {
		if supported = generic_features_match(features_generic, supported_generic); supported {
			for &chain in self.extended_features_chain {
				if chain.pNext.sType == features.sType {
					merge_features(cast(^T)&chain.pNext, features)
					break add_chain_blk
				}
			}
			append(&self.extended_features_chain, features_generic)
		}
	}

	return
}

// Generic version that works with any feature struct
physical_device_enable_extensions_with_features :: proc(
	self: ^Physical_Device,
	extensions: []string,
	features: []$T,
	loc := #caller_location,
) -> (
	ok: bool,
) where intrinsics.type_has_field(T, "sType") {
	// Check all extensions present
	for ext in extensions {
		if !physical_device_is_extension_present(self, ext) {
			return false
		}
	}

	// Enable all features
	for feature in features {
		if !physical_device_enable_extension_features_if_present(self, feature, loc) {
			return false
		}
	}

	// Enable extensions
	append(&self.extensions_to_enable, ..extensions[:])

	return true
}

// -----------------------------------------------------------------------------
// Device builder
// -----------------------------------------------------------------------------

// For advanced device queue setup.
Custom_Queue_Description :: struct {
	index:      u32,
	priorities: []f32,
}

Device_Builder :: struct {
	// Physical device
	physical_device:      ^Physical_Device,

	// Info
	flags:                vk.DeviceCreateFlags,
	pnext_chain:          [dynamic]^vk.BaseOutStructure,
	queue_descriptions:   [dynamic]Custom_Queue_Description,
	allocation_callbacks: ^vk.AllocationCallbacks,

	// Internal
	allocator:            mem.Allocator,
}

@(require_results)
create_device_builder :: proc(
	physical_device: ^Physical_Device,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	builder: ^Device_Builder,
) {
	ensure(physical_device != nil, "Invalid Physical Device", loc)

	builder = new(Device_Builder, allocator)

	builder.allocator = allocator
	builder.physical_device = physical_device
	builder.pnext_chain.allocator = builder.allocator
	builder.queue_descriptions.allocator = builder.allocator

	return
}

destroy_device_builder :: proc(self: ^Device_Builder, loc := #caller_location) {
	assert(self != nil, "Invalid Device Builder", loc)
	context.allocator = self.allocator
	delete(self.queue_descriptions)
	delete(self.pnext_chain)
	free(self)
}

@(require_results)
device_builder_build :: proc(
	self: ^Device_Builder,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	device: ^Device,
	err: Error,
) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	queue_descriptions := make([dynamic]Custom_Queue_Description, ta)

	if len(self.queue_descriptions) == 0 {
		for i in 0 ..< len(self.physical_device.queue_families) {
			append(&queue_descriptions, Custom_Queue_Description{ u32(i), { 1.0 } })
		}
	} else {
		append(&queue_descriptions, ..self.queue_descriptions[:])
	}

	queue_create_infos := make([dynamic]vk.DeviceQueueCreateInfo, ta)

	for &desc in queue_descriptions {
		queue_create_info: vk.DeviceQueueCreateInfo = {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = desc.index,
			queueCount       = u32(len(desc.priorities)),
			pQueuePriorities = raw_data(desc.priorities),
		}

		append(&queue_create_infos, queue_create_info)
	}

	// Enable all supported device extensions
	extensions_to_enable := make(
		[dynamic]cstring,
		0,
		len(self.physical_device.extensions_to_enable),
		ta,
	)

	for ext in self.physical_device.extensions_to_enable {
		append(&extensions_to_enable, strings.clone_to_cstring(ext, ta))
	}

	// Extension `VK_KHR_swapchain` is required to present surface
	if self.physical_device.surface != 0 || self.physical_device.defer_surface_initialization {
		append(&extensions_to_enable, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
	}

	final_pnext_chain := make([dynamic]^vk.BaseOutStructure, ta)
	device_create_info: vk.DeviceCreateInfo

	user_defined_phys_dev_features_2 := false
	for &next in self.pnext_chain {
		if next.sType == .PHYSICAL_DEVICE_FEATURES_2 {
			user_defined_phys_dev_features_2 = true
			break
		}
	}

	if user_defined_phys_dev_features_2 && len(self.physical_device.extended_features_chain) > 0 {
		err = Device_Error {
			kind = .VkFeatures2_Pnext_Chain,
			result = .ERROR_INITIALIZATION_FAILED,
			message = "Vulkan physical device features 2 in pNext chain while using " +
					  "add required extension features",
		}
		return
	}

	local_features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
	}

	if !user_defined_phys_dev_features_2 {
		if self.physical_device.instance_version > vk.API_VERSION_1_1 ||
		   self.physical_device.properties2_ext_enabled {
			local_features2.features = self.physical_device.features
			append(&final_pnext_chain, cast(^vk.BaseOutStructure)&local_features2)

			for &features_node in self.physical_device.extended_features_chain {
				append(&final_pnext_chain, cast(^vk.BaseOutStructure)&features_node.pNext)
			}
		} else {
			// Only set device_create_info.pEnabledFeatures when the pNext chain does not contain a
			// vk.PhysicalDeviceFeatures2 structure
			device_create_info.pEnabledFeatures = &self.physical_device.features
		}
	}

	for &pnext in self.pnext_chain {
		append(&final_pnext_chain, pnext)
	}

	setup_pnext_chain(&device_create_info, &final_pnext_chain, loc)

	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.flags = self.flags
	device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))
	device_create_info.pQueueCreateInfos = raw_data(queue_create_infos[:])
	device_create_info.enabledExtensionCount = u32(len(extensions_to_enable))
	device_create_info.ppEnabledExtensionNames = raw_data(extensions_to_enable[:])

	vk_device: vk.Device
	vk_check(vk.CreateDevice(
		self.physical_device.physical_device,
		&device_create_info,
		self.allocation_callbacks,
		&vk_device,
	), "Failed to create logical device", loc) or_return

	device = new_clone(Device{
		device               = vk_device,
		physical_device      = self.physical_device,
		surface              = self.physical_device.surface,
		allocation_callbacks = self.allocation_callbacks,
		instance_version     = self.physical_device.instance_version,
		allocator            = allocator,
	}, allocator)

	queue_families := make([]vk.QueueFamilyProperties, len(self.physical_device.queue_families), allocator)
	copy(queue_families, self.physical_device.queue_families[:])
	device.queue_families = queue_families

	vk.load_proc_addresses_device(vk_device)

	return
}

// Provide custom allocation callbacks.
device_builder_set_allocation_callbacks :: proc(
	self: ^Device_Builder,
	callbacks: ^vk.AllocationCallbacks,
) {
	self.allocation_callbacks = callbacks
}

// For Advanced Users: specify the exact list of `vk.DeviceQueueCreateInfo`'s needed
// for the application. If a custom queue setup is provided, getting the queues and
// queue indexes is up to the application.
device_builder_custom_queue_setup :: proc(
	self: ^Device_Builder,
	queue_descriptions: []Custom_Queue_Description,
) {
	clear(&self.queue_descriptions)
	append(&self.queue_descriptions, ..queue_descriptions)
}

// Add a structure to the `pNext` chain of `vk.DeviceCreateInfo`.
//
// The structure must be valid when `device_builder_build()` is called.
device_builder_add_pnext :: proc(self: ^Device_Builder, structure: ^$T) {
	append(&self.pnext_chain, cast(^vk.BaseOutStructure)structure)
}

// -----------------------------------------------------------------------------
// Device
// -----------------------------------------------------------------------------

Queue_Type :: enum {
	Present,
	Graphics,
	Compute,
	Transfer,
}

Device :: struct {
	device:               vk.Device,
	physical_device:      ^Physical_Device,
	surface:              vk.SurfaceKHR,
	queue_families:       []vk.QueueFamilyProperties,
	allocation_callbacks: ^vk.AllocationCallbacks,
	get_device_proc_addr: vk.ProcGetDeviceProcAddr,
	instance_version:     u32,

	// Internal
	allocator:            runtime.Allocator,
}

destroy_device :: proc(self: ^Device, loc := #caller_location) {
	assert(self != nil, "Invalid Device", loc)
	context.allocator = self.allocator
	vk.DestroyDevice(self.device, nil)
	delete(self.queue_families)
	free(self)
}

device_get_queue_index :: proc(device: ^Device, type: Queue_Type) -> (index: u32, err: Error) {
	index = vk.QUEUE_FAMILY_IGNORED
	switch type {
	case .Present:
		index = get_present_queue_index(
			device.physical_device.physical_device, device.surface, device.queue_families)
		if index == vk.QUEUE_FAMILY_IGNORED {
			err = Queue_Error {
				.Present_Unavailable, .ERROR_INITIALIZATION_FAILED, "Present unavailable",
			}
			return
		}
	case .Graphics:
		index = get_first_queue_index(device.queue_families, { .GRAPHICS })
		if index == vk.QUEUE_FAMILY_IGNORED {
			err = Queue_Error {
				.Graphics_Unavailable, .ERROR_INITIALIZATION_FAILED, "Graphics unavailable",
			}
			return
		}
	case .Compute:
		index = get_separate_queue_index(device.queue_families, { .COMPUTE }, { .TRANSFER })
		if index == vk.QUEUE_FAMILY_IGNORED {
			err = Queue_Error {
				.Compute_Unavailable, .ERROR_INITIALIZATION_FAILED, "Compute unavailable",
			}
			return
		}
	case .Transfer:
		index = get_separate_queue_index(device.queue_families, { .TRANSFER }, { .COMPUTE })
		if index == vk.QUEUE_FAMILY_IGNORED {
			err = Queue_Error {
				.Transfer_Unavailable, .ERROR_INITIALIZATION_FAILED, "Transfer unavailable",
			}
			return
		}
	case:
		err = Queue_Error {
			.Invalid_Queue_Family_Index, .ERROR_INITIALIZATION_FAILED, "Invalid queue family index",
		}
		return
	}

	return
}

device_get_dedicated_queue_index :: proc(device: ^Device, type: Queue_Type) -> (index: u32, err: Error) {
	index = vk.QUEUE_FAMILY_IGNORED
	#partial switch type {
	case .Compute:
		index = get_dedicated_queue_index(device.queue_families, { .COMPUTE }, { .TRANSFER })
		if index == vk.QUEUE_FAMILY_IGNORED {
			err = Queue_Error {
				.Compute_Unavailable, .ERROR_INITIALIZATION_FAILED, "Compute unavailable",
			}
			return
		}
	case .Transfer:
		index = get_dedicated_queue_index(device.queue_families, { .TRANSFER }, { .COMPUTE })
		err = Queue_Error {
			.Transfer_Unavailable, .ERROR_INITIALIZATION_FAILED, "Transfer unavailable",
		}
		return
	case:
		err = Queue_Error {
			.Invalid_Queue_Family_Index, .ERROR_INITIALIZATION_FAILED, "Invalid queue family index",
		}
		return
	}

	return
}

device_get_queue :: proc(device: ^Device, type: Queue_Type) -> (out_queue: vk.Queue, err: Error) {
	index := device_get_queue_index(device, type) or_return
	vk.GetDeviceQueue(device.device, index, 0, &out_queue)
	return
}

device_get_dedicated_queue :: proc(device: ^Device, type: Queue_Type) -> (out_queue: vk.Queue, err: Error) {
	index := device_get_dedicated_queue_index(device, type) or_return
	vk.GetDeviceQueue(device.device, index, 0, &out_queue)
	return
}

// -----------------------------------------------------------------------------
// Swapchain builder
// -----------------------------------------------------------------------------

Swapchain_Builder :: struct {
	physical_device:          vk.PhysicalDevice,
	device:                   vk.Device,
	pnext_chain:              [dynamic]^vk.BaseOutStructure,
	create_flags:             vk.SwapchainCreateFlagsKHR,
	surface:                  vk.SurfaceKHR,
	desired_formats:          [dynamic]vk.SurfaceFormatKHR,
	instance_version:         u32,
	desired_width:            u32,
	desired_height:           u32,
	array_layer_count:        u32,
	min_image_count:          u32,
	required_min_image_count: u32,
	image_usage_flags:        vk.ImageUsageFlags,
	graphics_queue_index:     u32,
	present_queue_index:      u32,
	pre_transform:            vk.SurfaceTransformFlagsKHR,
	composite_alpha:          vk.CompositeAlphaFlagsKHR,
	desired_present_modes:    [dynamic]vk.PresentModeKHR,
	clipped:                  bool,
	old_swapchain:            vk.SwapchainKHR,
	allocation_callbacks:     ^vk.AllocationCallbacks,

	// Internal
	allocator: runtime.Allocator,
}

@(private)
swapchain_builder_default_impl :: proc(
	device: ^Device,
	allocator := context.allocator,
	loc := #caller_location,
) -> ^Swapchain_Builder {
	builder := new_clone(Swapchain_Builder {
		physical_device   = device.physical_device.physical_device,
		device            = device.device,
		instance_version  = device.instance_version,
		desired_width     = 256,
		desired_height    = 256,
		array_layer_count = 1,
		image_usage_flags = { .COLOR_ATTACHMENT },
		composite_alpha   = { .OPAQUE },
		clipped           = true,
		allocator         = allocator,
	}, allocator)

	builder.pnext_chain.allocator = allocator
	builder.desired_formats.allocator = allocator
	builder.desired_present_modes.allocator = allocator

	return builder
}

create_swapchain_builder_default :: proc(
	device: ^Device,
	allocator := context.allocator,
) -> ^Swapchain_Builder {
	builder := swapchain_builder_default_impl(device, allocator)
	builder.surface = device.surface
	return builder
}

create_swapchain_builder_surface :: proc(
	device: ^Device,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
) -> ^Swapchain_Builder {
	builder := swapchain_builder_default_impl(device, allocator)
	builder.surface = surface
	return builder
}

create_swapchain_builder_queue_index :: proc(
	physical_device: ^Physical_Device,
	device: ^Device,
	surface: vk.SurfaceKHR,
	graphics_queue_index: u32,
	present_queue_index: u32,
	allocator := context.allocator,
) -> (
	builder: ^Swapchain_Builder,
) {
	builder = swapchain_builder_default_impl(device, allocator)
	builder.surface = surface

	if graphics_queue_index == vk.QUEUE_FAMILY_IGNORED ||
	   present_queue_index == vk.QUEUE_FAMILY_IGNORED {
		ta := context.temp_allocator
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

		// Get the device queue families
		queue_family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(
			physical_device.physical_device, &queue_family_count, nil)
		if queue_family_count == 0 {
			return
		}

		queue_families := make([]vk.QueueFamilyProperties, int(queue_family_count), ta)
		vk.GetPhysicalDeviceQueueFamilyProperties(
			physical_device.physical_device,
			&queue_family_count,
			raw_data(queue_families),
		)

		if graphics_queue_index == vk.QUEUE_FAMILY_IGNORED {
			builder.graphics_queue_index = get_first_queue_index(queue_families, {.GRAPHICS})
		}

		if present_queue_index == vk.QUEUE_FAMILY_IGNORED {
			builder.present_queue_index = get_present_queue_index(
				physical_device.physical_device,
				surface,
				queue_families,
			)
		}
	}

	return builder
}

create_swapchain_builder :: proc {
	create_swapchain_builder_default,
	create_swapchain_builder_surface,
	create_swapchain_builder_queue_index,
}

destroy_swapchain_builder :: proc(self: ^Swapchain_Builder, loc := #caller_location) {
	assert(self != nil, "Invalid Swapchain_Builder", loc)
	context.allocator = self.allocator
	delete(self.pnext_chain)
	delete(self.desired_formats)
	delete(self.desired_present_modes)
	free(self)
}

swapchain_builder_build :: proc(
	self: ^Swapchain_Builder,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	swapchain: ^Swapchain,
	err: Error,
) {
	assert(self != nil, "Invalid Swapchain_Builder", loc)

	if self.surface == 0 {
		err = Swapchain_Error {
			.Surface_Handle_Not_Provided, .ERROR_INITIALIZATION_FAILED, "Surface handle not provided",
		}
		return
	}

	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	desired_formats := make([dynamic]vk.SurfaceFormatKHR, ta)
	if len(self.desired_formats) == 0 {
		swapchain_builder_utils_add_desired_formats(&desired_formats)
	} else {
		append(&desired_formats, ..self.desired_formats[:])
	}

	desired_present_modes := make([dynamic]vk.PresentModeKHR, ta)
	if len(self.desired_present_modes) == 0 {
		swapchain_builder_utils_add_desired_present_modes(&desired_present_modes)
	} else {
		append(&desired_present_modes, ..self.desired_present_modes[:])
	}

	// Get surface support details (capabilities, formats and present modes)
	surface_support := swapchain_builder_utils_query_surface_support_details(
		self.physical_device,
		self.surface,
		ta,
	) or_return

	image_count := self.min_image_count
	if self.required_min_image_count >= 1 {
		if self.required_min_image_count < surface_support.capabilities.minImageCount {
			err = Swapchain_Error {
				.Required_Min_Image_Count_Too_Low, .ERROR_INITIALIZATION_FAILED, "Required min image count too low",
			}
		}
		image_count = self.required_min_image_count
	} else if (self.min_image_count == 0) {
		// We intentionally use minImageCount + 1 to maintain existing behavior,
		// even if it typically results in triple buffering on most systems.
		image_count = surface_support.capabilities.minImageCount + 1
	} else {
		image_count = self.min_image_count
		if image_count < surface_support.capabilities.minImageCount {
			image_count = surface_support.capabilities.minImageCount
		}
	}
	if surface_support.capabilities.maxImageCount > 0 && image_count > surface_support.capabilities.maxImageCount {
		image_count = surface_support.capabilities.maxImageCount
	}

	surface_format := swapchain_builder_utils_find_best_surface_format(
		&surface_support.formats,
		&desired_formats,
	)

	extent := swapchain_builder_utils_find_extent(
		surface_support.capabilities,
		self.desired_width,
		self.desired_height,
	)

	image_array_layers := self.array_layer_count
	if surface_support.capabilities.maxImageArrayLayers < self.array_layer_count {
		image_array_layers = surface_support.capabilities.maxImageArrayLayers
	}
	if self.array_layer_count == 0 { image_array_layers = 1 }

	present_mode := swapchain_builder_utils_find_present_mode(
		&surface_support.present_modes,
		&desired_present_modes,
	)

	// vk.SurfaceCapabilitiesKHR.supportedUsageFlags is only valid for some present modes. For
	// shared present modes, we should also check
	// vk.SharedPresentSurfaceCapabilitiesKHR.sharedPresentSupportedUsageFlags.
	is_unextended_present_mode: bool =
		(present_mode == .IMMEDIATE) ||
		(present_mode == .MAILBOX) ||
		(present_mode == .FIFO) ||
		(present_mode == .FIFO_RELAXED)

	if is_unextended_present_mode &&
		(self.image_usage_flags & surface_support.capabilities.supportedUsageFlags) != self.image_usage_flags {
		err = Swapchain_Error {
			.Required_Usage_Not_Supported, .ERROR_INITIALIZATION_FAILED, "Required usage not supported",
		}
		return
	}

	pre_transform := self.pre_transform
	if self.pre_transform == {} {
		pre_transform = surface_support.capabilities.currentTransform
	}

	swapchain_create_info: vk.SwapchainCreateInfoKHR = {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		flags            = self.create_flags,
		surface          = self.surface,
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = image_array_layers,
		imageUsage       = self.image_usage_flags,
		preTransform     = pre_transform,
		compositeAlpha   = self.composite_alpha,
		presentMode      = present_mode,
		clipped          = b32(self.clipped),
		oldSwapchain     = self.old_swapchain,
	}

	queue_family_indices: [Queue_Family_Indices]u32 = {
		.Graphics = self.graphics_queue_index, .Present  = self.present_queue_index,
	}

	current_queue_family_indices := []u32 {
		queue_family_indices[.Graphics], queue_family_indices[.Present],
	}

	if self.graphics_queue_index != self.present_queue_index {
		swapchain_create_info.imageSharingMode = .CONCURRENT
		swapchain_create_info.queueFamilyIndexCount = u32(len(current_queue_family_indices))
		swapchain_create_info.pQueueFamilyIndices = raw_data(current_queue_family_indices)
	} else {
		swapchain_create_info.imageSharingMode = .EXCLUSIVE
	}

	setup_pnext_chain(&swapchain_create_info, &self.pnext_chain)

	vk_swapchain: vk.SwapchainKHR
	vk_check(vk.CreateSwapchainKHR(
		self.device,
		&swapchain_create_info,
		self.allocation_callbacks,
		&vk_swapchain,
	), "vk.CreateSwapchainKHR failed", loc) or_return

	swapchain = new_clone(Swapchain {
		device                    = self.device,
		swapchain                 = vk_swapchain,
		image_format              = surface_format.format,
		color_space               = surface_format.colorSpace,
		image_usage_flags         = self.image_usage_flags,
		extent                    = extent,
		requested_min_image_count = image_count,
		present_mode              = present_mode,
		instance_version          = self.instance_version,
		allocation_callbacks      = self.allocation_callbacks,
		allocator                 = allocator,
	}, allocator)
	defer if err != nil { destroy_swapchain(swapchain) }

	images := swapchain_get_images(swapchain, allocator = ta) or_return
	swapchain.image_count = u32(len(images))

	return
}

swapchain_builder_utils_add_desired_formats :: proc(formats: ^[dynamic]vk.SurfaceFormatKHR) {
	append(formats, vk.SurfaceFormatKHR{format = .B8G8R8A8_SRGB, colorSpace = .SRGB_NONLINEAR})
	append(formats, vk.SurfaceFormatKHR{format = .R8G8B8A8_SRGB, colorSpace = .SRGB_NONLINEAR})
}

swapchain_builder_utils_add_desired_present_modes :: proc(
	present_modes: ^[dynamic]vk.PresentModeKHR,
) {
	append(present_modes, vk.PresentModeKHR.FIFO)
	append(present_modes, vk.PresentModeKHR.MAILBOX)
}

Surface_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

swapchain_builder_utils_query_surface_support_details :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	details: Surface_Support_Details,
	err: Error,
) {
	if surface == 0 {
		err = Surface_Support_Error {
			.Surface_Handle_Null, .ERROR_INITIALIZATION_FAILED, "Surface handle is null",
		}
		return
	}

	// Capabilities
	vk_check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		physical_device,
		surface,
		&details.capabilities,
	), "vk.GetPhysicalDeviceSurfaceCapabilitiesKHR failed", loc) or_return

	// Supported formats
	format_count: u32
	vk_check(vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device, surface, &format_count, nil,
	), "vk.GetPhysicalDeviceSurfaceFormatsKHR failed", loc) or_return

	details.formats = make([]vk.SurfaceFormatKHR, int(format_count), allocator)
	defer if err != nil { delete(details.formats) }

	vk_check(vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&format_count,
		raw_data(details.formats),
	), "vk.GetPhysicalDeviceSurfaceFormatsKHR failed", loc) or_return

	// Supported present modes
	present_mode_count: u32
	vk_check(vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		nil,
	), "vk.GetPhysicalDeviceSurfacePresentModesKHR failed", loc) or_return

	details.present_modes = make([]vk.PresentModeKHR, int(present_mode_count), allocator)
	defer if err != nil { delete(details.present_modes) }

	vk_check(vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&present_mode_count,
		raw_data(details.present_modes),
	), "vk.GetPhysicalDeviceSurfacePresentModesKHR", loc) or_return

	return
}

swapchain_builder_utils_find_best_surface_format :: proc(
	available_formats: ^[]vk.SurfaceFormatKHR,
	desired_formats: ^[dynamic]vk.SurfaceFormatKHR,
) -> vk.SurfaceFormatKHR {
	if surface_format, ok := swapchain_builder_utils_find_desired_surface_format(
		available_formats,
		desired_formats,
	); ok {
		return surface_format
	}

	// Use the first available format as a fallback if any desired formats aren't found
	return available_formats[0]
}

swapchain_builder_utils_find_desired_surface_format :: proc(
	available_formats: ^[]vk.SurfaceFormatKHR,
	desired_formats: ^[dynamic]vk.SurfaceFormatKHR,
) -> (
	format: vk.SurfaceFormatKHR,
	ok: bool,
) {
	for desired in desired_formats {
		for available in available_formats {
			// finds the first format that is desired and available
			if desired.format == available.format && desired.colorSpace == available.colorSpace {
				return desired, true
			}
		}
	}

	// if no desired format is available,
	// we report that no format is suitable to the user request
	return
}

swapchain_builder_utils_find_extent :: proc(
	capabilities: vk.SurfaceCapabilitiesKHR,
	desired_width, desired_height: u32,
) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	actual_extent: vk.Extent2D = {desired_width, desired_height}

	actual_extent.width = max(
		capabilities.minImageExtent.width,
		min(capabilities.maxImageExtent.width, actual_extent.width),
	)
	actual_extent.height = max(
		capabilities.minImageExtent.height,
		min(capabilities.maxImageExtent.height, actual_extent.height),
	)

	return actual_extent
}

swapchain_builder_utils_find_present_mode :: proc(
	available_resent_modes: ^[]vk.PresentModeKHR,
	desired_present_modes: ^[dynamic]vk.PresentModeKHR,
) -> vk.PresentModeKHR {
	#reverse for desired in desired_present_modes {
		for available in available_resent_modes {
			// finds the first present mode that is desired and available
			if (desired == available) {
				return desired
			}
		}
	}

	// Only present mode required, use as a fallback
	return .FIFO
}

// Set the oldSwapchain member of `vk.SwapchainCreateInfoKHR`.
// For use in rebuilding a swapchain.
swapchain_builder_set_old_swapchain_handle :: proc(self: ^Swapchain_Builder, old_swapchain: vk.SwapchainKHR) {
	self.old_swapchain = old_swapchain
}

// Set the oldSwapchain member of `vk.SwapchainCreateInfoKHR`.
// For use in rebuilding a swapchain.
swapchain_builder_set_old_swapchain_vkb :: proc(self: ^Swapchain_Builder, old_swapchain: ^Swapchain) {
	if old_swapchain != nil && old_swapchain.swapchain != 0 {
		self.old_swapchain = old_swapchain.swapchain
	}
}

// Set the oldSwapchain member of `vk.SwapchainCreateInfoKHR`.
// For use in rebuilding a swapchain.
swapchain_builder_set_old_swapchain :: proc {
	swapchain_builder_set_old_swapchain_handle,
	swapchain_builder_set_old_swapchain_vkb,
}

// Desired size of the swapchain. By default, the swapchain will use the size
// of the window being drawn to.
swapchain_builder_set_desired_extent :: proc(self: ^Swapchain_Builder, width, height: u32) {
	self.desired_width = width
	self.desired_height = height
}

// When determining the surface format, make this the first to be used if supported.
swapchain_builder_set_desired_format :: proc(self: ^Swapchain_Builder, format: vk.SurfaceFormatKHR) {
	inject_at(&self.desired_formats, 0, format)
}

// Add this swapchain format to the end of the list of formats selected from.
swapchain_builder_add_fallback_format :: proc(self: ^Swapchain_Builder, format: vk.SurfaceFormatKHR) {
	append(&self.desired_formats, format)
}

// Use the default swapchain formats. This is done if no formats are provided.
//
// Default surface format is `{ .B8G8R8A8_SRGB, .SRGB_NONLINEAR_KHR }`.
swapchain_builder_use_default_format_selection :: proc(self: ^Swapchain_Builder) {
	clear(&self.desired_formats)
	swapchain_builder_utils_add_desired_formats(&self.desired_formats)
}

// When determining the present mode, make this the first to be used if supported.
swapchain_builder_set_desired_present_mode :: proc(self: ^Swapchain_Builder, present_mode: vk.PresentModeKHR) {
	inject_at(&self.desired_present_modes, 0, present_mode)
}

// Add this present mode to the end of the list of present modes selected from.
swapchain_builder_add_fallback_present_mode :: proc(self: ^Swapchain_Builder, present_mode: vk.PresentModeKHR) {
	append(&self.desired_present_modes, present_mode)
}

// Use the default presentation mode. This is done if no present modes are provided.
//
// Default present modes: `MAILBOX` with fallback `FIFO`.
swapchain_builder_use_default_present_mode_selection :: proc(self: ^Swapchain_Builder) {
	clear(&self.desired_present_modes)
	swapchain_builder_utils_add_desired_present_modes(&self.desired_present_modes)
}

// Set the bitmask of the image usage for acquired swapchain images.
//
// If the surface capabilities cannot allow it, building the swapchain will result
// in the `Swapchain_Error.Required_Usage_Not_Supported` error.
swapchain_builder_set_image_usage_flags :: proc(self: ^Swapchain_Builder, usage_flags: vk.ImageUsageFlags) {
	self.image_usage_flags = usage_flags
}

// Add a image usage to the bitmask for acquired swapchain images.
swapchain_builder_add_image_usage_flags :: proc(self: ^Swapchain_Builder, usage_flags: vk.ImageUsageFlags) {
	self.image_usage_flags += usage_flags
}

// Use the default image usage bitmask values. This is the default if no image
// usages are provided.
//
// The default is `{ .COLOR_ATTACHMENT }`.
swapchain_builder_use_default_image_usage_flags :: proc(self: ^Swapchain_Builder) {
	self.image_usage_flags = { .COLOR_ATTACHMENT }
}

// Set the number of views in for multiview/stereo surface
swapchain_builder_set_image_array_layer_count :: proc(self: ^Swapchain_Builder, array_layer_count: u32) {
	self.array_layer_count = array_layer_count
}

// Sets the desired minimum image count for the swapchain.
//
// Note that the presentation engine is always free to create more images than
// requested. You may pass one of the values specified in the `Buffer_Mode` enum, or
// any integer value. For instance, if you pass `DOUBLE_BUFFERING`, the presentation
// engine is allowed to give you a double buffering setup, triple buffering, or
// more. This is up to the drivers.
swapchain_builder_set_desired_min_image_count :: proc(self: ^Swapchain_Builder, min_image_count: u32) {
	self.min_image_count = min_image_count
}

// Sets a required minimum image count for the swapchain.
//
// If the surface capabilities cannot allow it, building the swapchain will result
// in the `Swapchain_Error.Required_Min_Image_Count_Too_Low` error. Otherwise, the
// same observations from `set_desired_min_image_count()` apply. A value of 0 is
// specially interpreted as meaning "no requirement", and is the behavior by default.
swapchain_builder_set_required_min_image_count :: proc(self: ^Swapchain_Builder, required_min_image_count: u32) {
	self.required_min_image_count = required_min_image_count
}

// Set whether the Vulkan implementation is allowed to discard rendering operations
// that affect regions of the surface that are not visible.
//
// Default is `true`.
//
// Note: Applications should use the default of true if they do not expect to read
// back the content of presentable images before presenting them or after
// reacquiring them, and if their fragment shaders do not have any side effects
// that require them to run for all pixels in the presentable image.
swapchain_builder_set_clipped :: proc(self: ^Swapchain_Builder, clipped := true) {
	self.clipped = clipped
}

// Set the `vk.SwapchainCreateFlagsKHR`.
swapchain_builder_set_create_flags :: proc(self: ^Swapchain_Builder, create_flags: vk.SwapchainCreateFlagsKHR) {
	self.create_flags = create_flags
}

// Set the transform to be applied, like a 90 degree rotation. Default is no transform.
swapchain_builder_set_pre_transform_flags :: proc(self: ^Swapchain_Builder, pre_transform_flags: vk.SurfaceTransformFlagsKHR) {
	self.pre_transform = pre_transform_flags
}

// Set the alpha channel to be used with other windows in on the system.
//
// Default is `{ .OPAQUE }`.
swapchain_builder_set_composite_alpha_flags :: proc(self: ^Swapchain_Builder, composite_alpha_flags: vk.CompositeAlphaFlagsKHR ) {
	self.composite_alpha = composite_alpha_flags
}

// Add a structure to the pNext chain of `vk.SwapchainCreateInfoKHR`.
//
// The structure must be valid when `swapchain_builder_build()` is called.
swapchain_builder_add_pnext :: proc(self: ^Swapchain_Builder, structure: ^$T) {
	append(&self.pnext_chain, cast(^vk.BaseOutStructure)structure)
}

// Provide custom allocation callbacks.
swapchain_builder_set_allocation_callbacks :: proc(self: ^Swapchain_Builder, callbacks: ^vk.AllocationCallbacks) {
	self.allocation_callbacks = callbacks
}

// -----------------------------------------------------------------------------
// Swapchain
// -----------------------------------------------------------------------------

Queue_Family_Indices :: enum {
	Graphics,
	Present,
}

Swapchain :: struct {
	device:                    vk.Device,
	swapchain:                 vk.SwapchainKHR,
	image_count:               u32,
	image_format:              vk.Format,
	color_space:               vk.ColorSpaceKHR,
	image_usage_flags:         vk.ImageUsageFlags,
	extent:                    vk.Extent2D,
	requested_min_image_count: u32,
	present_mode:              vk.PresentModeKHR,
	instance_version:          u32,
	allocation_callbacks:      ^vk.AllocationCallbacks,
	allocator:                 runtime.Allocator,
}

create_swapchain_default_impl :: proc(device: ^Device) -> (swapchain: ^Swapchain) {
	swapchain = new_clone(Swapchain {
		color_space      = .SRGB_NONLINEAR,
		present_mode     = .IMMEDIATE,
		instance_version = device.instance_version,
		allocator        = device.allocator,
	}, device.allocator)
	return
}

destroy_swapchain :: proc(self: ^Swapchain, loc := #caller_location) {
	assert(self != nil, "Invalid Swapchain", loc)
	context.allocator = self.allocator
	if self.device != nil && self.swapchain != 0 {
		vk.DestroySwapchainKHR(self.device, self.swapchain, self.allocation_callbacks)
	}
	free(self)
}

//Returns a slice of `vk.Image` handles to the swapchain.
@(require_results)
swapchain_get_images :: proc(
	self: ^Swapchain,
	max_images: u32 = 0,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	images: []vk.Image,
	err: Error,
) {
	assert(self != nil, "Invalid Swapchain", loc)

	// Get the number of images in the swapchain
	image_count: u32 = 0
	vk_check(vk.GetSwapchainImagesKHR(
		self.device, self.swapchain, &image_count, nil,
	), "vk.GetSwapchainImagesKHR failed", loc) or_return

	// Limit the number of images if `max_images` is specified
	if max_images > 0 && image_count > max_images {
		image_count = max_images
	}

	// Allocate memory for the images
	images = make([]vk.Image, image_count, allocator)
	defer if err != nil { delete(images, allocator) }

	// Retrieve the actual images
	vk_check(vk.GetSwapchainImagesKHR(
		self.device,
		self.swapchain,
		&image_count,
		raw_data(images),
	), "vk.GetSwapchainImagesKHR", loc) or_return

	return
}

// Returns a slice of vk.ImageView's to the `vk.Image`'s of the swapchain.
swapchain_get_image_views :: proc(
	self: ^Swapchain,
	pNext: rawptr = nil,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	views: []vk.ImageView,
	err: Error,
) {
	ta := context.temp_allocator
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)

	images := swapchain_get_images(self, allocator = ta) or_return

	already_contains_image_view_usage := false
	pNext := pNext

	for pNext != nil {
		if (cast(^vk.BaseInStructure)pNext).sType == .IMAGE_VIEW_CREATE_INFO {
			already_contains_image_view_usage = true
			break
		}
		pNext = (cast(^vk.BaseInStructure)pNext).pNext
	}

	desired_flags := vk.ImageViewUsageCreateInfo {
		sType = .IMAGE_VIEW_USAGE_CREATE_INFO,
		pNext = pNext,
		usage = self.image_usage_flags,
	}

	// Total of images to create views
	images_len := len(images)

	// Create image views for each image
	views = make([]vk.ImageView, images_len, allocator)
	defer if err != nil {
		swapchain_destroy_image_views(self, views)
		delete(views, allocator)
	}

	for i in 0 ..< images_len {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
		}

		if self.instance_version >= vk.API_VERSION_1_1 && !already_contains_image_view_usage {
			create_info.pNext = &desired_flags
		} else {
			create_info.pNext = pNext
		}

		create_info.image = images[i]
		create_info.viewType = .D2
		create_info.format = self.image_format
		create_info.components = {
			r = .IDENTITY,
			g = .IDENTITY,
			b = .IDENTITY,
			a = .IDENTITY,
		}
		create_info.subresourceRange.aspectMask = {.COLOR}
		create_info.subresourceRange.baseMipLevel = 0
		create_info.subresourceRange.levelCount = 1
		create_info.subresourceRange.baseArrayLayer = 0
		create_info.subresourceRange.layerCount = 1

		vk_check(vk.CreateImageView(
			self.device,
			&create_info,
			self.allocation_callbacks,
			&views[i],
		), "vk.CreateImageView failed", loc) or_return
	}

	return
}

swapchain_destroy_image_views :: proc(self: ^Swapchain, views: []vk.ImageView, loc := #caller_location) {
	for view in views {
		assert(view != 0, "Invalid image view", loc)
		vk.DestroyImageView(self.device, view, self.allocation_callbacks)
	}
}

// -----------------------------------------------------------------------------
// Utils
// -----------------------------------------------------------------------------

@(require_results)
vk_check :: #force_inline proc(
	res: vk.Result,
	message := "Detected Vulkan error",
	loc := #caller_location,
) -> Error {
	if (res != .SUCCESS) {
		return General_Error {
			kind    = .Vulkan_Error,
			result  = res,
			message = message,
		}
	}
	return nil
}

byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

setup_pnext_chain :: proc(
	structure: ^$T,
	structs: ^[dynamic]^vk.BaseOutStructure,
	loc := #caller_location,
) {
	structure.pNext = nil
	if len(structs) == 0 {
		return
	}

	for i := 0; i < len(structs) - 1; i += 1 {
		out_structure: vk.BaseOutStructure
		mem.copy(&out_structure, structs[i], size_of(vk.BaseOutStructure))

		when ODIN_DEBUG {
			assert(out_structure.sType != .APPLICATION_INFO, loc = loc)
		}

		out_structure.pNext = cast(^vk.BaseOutStructure)structs[i + 1]
		mem.copy(structs[i], &out_structure, size_of(vk.BaseOutStructure))
	}

	out_structure: vk.BaseOutStructure
	mem.copy(&out_structure, structs[len(structs) - 1], size_of(vk.BaseOutStructure))
	out_structure.pNext = nil

	when ODIN_DEBUG {
		assert(out_structure.sType != .APPLICATION_INFO, loc = loc)
	}

	mem.copy(structs[len(structs) - 1], &out_structure, size_of(vk.BaseOutStructure))
	structure.pNext = structs[0]
}

// API_VERSION_1_0 :: (1<<22) | (0<<12) | (0)
// API_VERSION_1_1 :: (1<<22) | (1<<12) | (0)
// API_VERSION_1_2 :: (1<<22) | (2<<12) | (0)
API_VERSION_1_3 :: (0<<29) | (1<<22) | (3<<12) | (0)
// API_VERSION_1_4 :: (1<<22) | (4<<12) | (0)

MAKE_API_VERSION :: proc "contextless" (variant, major, minor, patch: u32) -> u32 {
	return (major<<29) | (major<<22) | (minor<<12) | (patch)
}

VK_VERSION_MAJOR :: proc(version: u32) -> u32 {
	return (version >> 22) & 0x7F
}

VK_VERSION_MINOR :: proc(version: u32) -> u32 {
	return (version >> 12) & 0x3FF
}

VK_VERSION_PATCH :: proc(version: u32) -> u32 {
	return version & 0xFFF
}

// Convert between Vulkan's bit-packed version to decimal "MMmmppp" format.
//
// `api_version` should be a value from the api or constructed with `vk.MAKE_VERSION`.
VK_API_VERSION_TO_DECIMAL :: proc(api_version: u32) -> u32 {
	major := VK_VERSION_MAJOR(api_version) * 1000000
	minor := VK_VERSION_MINOR(api_version) * 1000
	patch := VK_VERSION_PATCH(api_version)
	return major + minor + patch
}

// Assuming the total of bits from any extension feature.
FEATURES_BITS_FIELDS_CAPACITY :: 256

Generic_Feature :: struct {
	type:  typeid,
	pNext: Generic_Feature_pNext_Node,
}

/*
Example of generic feature structure:

	PhysicalDeviceVulkan12Features :: struct {
		sType:                    StructureType,
		pNext:                    rawptr,
		samplerMirrorClampToEdge: b32,
		drawIndirectCount:        b32,
		storageBuffer8BitAccess:  b32,
		...
*/
Generic_Feature_pNext_Node :: struct {
	sType:  vk.StructureType,
	pNext:  rawptr,
	fields: [FEATURES_BITS_FIELDS_CAPACITY]b32,
}

create_generic_features :: proc(features: ^$T, loc := #caller_location) -> (v: Generic_Feature) {
	v.type = T
	assert(size_of(T) <= size_of(Generic_Feature_pNext_Node),
		"Feature struct is too large for Generic_Feature_pNext_Node", loc)
	mem.copy(&v.pNext, features, size_of(T))
	return
}

// Check if all `requested` extension features bits is available.
generic_features_match :: proc(
	requested: Generic_Feature,
	supported: Generic_Feature,
	loc := #caller_location,
) -> bool {
	assert(requested.pNext.sType == supported.pNext.sType,
		"Non-matching sTypes in features nodes!", loc)
	assert(requested.type == supported.type, "Non-matching extension types!", loc)

	ti := runtime.type_info_base(type_info_of(requested.type))

	// Ensure it's a struct
	struct_info, is_struct := ti.variant.(runtime.Type_Info_Struct)
	assert(is_struct, "Generic_Feature type is not a struct", loc)

	field_count := min(struct_info.field_count, FEATURES_BITS_FIELDS_CAPACITY)
	assert(field_count > 2, "Invalid generic feature structure", loc)

	// Start at 2 to skip fields sType and pNext
	for i in 2 ..< field_count {
		// Check if the requested feature bit is not set, no need to compare
		if !requested.pNext.fields[i] { continue }
		// Check if the supported feature bit is NOT set
		if !supported.pNext.fields[i] {
			return false
		}
	}

	return true
}

// Setup the pNext chain for feature queries
generic_features_setup_pnext_chain :: proc(
	features_chain: []Generic_Feature,
) -> (
	features2: vk.PhysicalDeviceFeatures2,
) {
	if len(features_chain) == 0 {
		return
	}

	features2.sType = .PHYSICAL_DEVICE_FEATURES_2

	// Chain the features together
	// Each struct's pNext should point to the next struct
	for i in 0 ..< len(features_chain) - 1 {
		// Get pointer to the next struct in the chain
		features_chain[i].pNext.pNext = &features_chain[i + 1].pNext
	}

	// Set the last one's pNext to nil
	if len(features_chain) > 0 {
		features_chain[len(features_chain) - 1].pNext.pNext = nil
	}

	// Set features2.pNext to point to the first struct
	features2.pNext = &features_chain[0].pNext

	return
}

// Finds the first queue which supports the desired operations.
//
// Returns `vk.QUEUE_FAMILY_IGNORED` if none is found.
get_first_queue_index :: proc(
	families: []vk.QueueFamilyProperties,
	desired_flags: vk.QueueFlags,
) -> u32 {
	index := vk.QUEUE_FAMILY_IGNORED

	for f, queue_index in families {
		if (f.queueFlags & desired_flags) == desired_flags {
			return u32(queue_index)
		}
	}

	return index
}

// Finds the queue which is separate from the graphics queue and has the desired flag and not the
// undesired flag, but will select it if no better options are available compute support.
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
	vk_physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	families: []vk.QueueFamilyProperties,
) -> u32 {
	for _, queue_index in families {
		present_support: b32

		if surface != 0 {
			if vk.GetPhysicalDeviceSurfaceSupportKHR(
				   vk_physical_device,
				   cast(u32)queue_index,
				   surface,
				   &present_support,
			   ) != .SUCCESS {
				return vk.QUEUE_FAMILY_IGNORED
			}

			if present_support {
				return cast(u32)queue_index
			}
		}
	}

	return vk.QUEUE_FAMILY_IGNORED
}

check_device_extension_support :: proc(
	available_extensions: []string,
	required_extensions: []string,
) -> (
	supported: bool,
) {
	supported = true

	if len(required_extensions) == 0 {
		return true
	}

	if len(available_extensions) == 0 && len(required_extensions) > 0 {
		return false
	}

	required_loop: for req_ext in required_extensions {
		for avail_ext in available_extensions {
			if avail_ext == req_ext {
				continue required_loop
			}
		}
		supported = false
	}

	return
}

find_unsupported_extensions_in_list :: proc(
	available_extensions: []string,
	required_extensions: []string,
	allocator := context.allocator,
) -> []string {
	unavailable_extensions := make([dynamic]string, allocator)
	for req_ext in required_extensions {
		if _, found := slice.binary_search(available_extensions, req_ext); !found {
			append(&unavailable_extensions, req_ext)
		}
	}
	return unavailable_extensions[:]
}

// Check features 1.0.
check_features_10 :: proc(requested, supported: vk.PhysicalDeviceFeatures) -> (ok: bool) {
	supported := supported
	requested := requested
	ok = true

	requested_info := type_info_of(vk.PhysicalDeviceFeatures)

	#partial switch info in requested_info.variant {
	case runtime.Type_Info_Named:
		#partial switch field in info.base.variant {
		case runtime.Type_Info_Struct:
			for i in 0 ..< field.field_count {
				// name := field.names[i]
				offset := field.offsets[i]

				requested_value := (^b32)(uintptr(&requested) + offset)^
				supported_value := (^b32)(uintptr(&supported) + offset)^

				if requested_value && !supported_value {
					// log.warnf("[VKB] Feature [%s] requested but not supported", name)
					ok = false
				}
			}
		}
	case:
		unreachable()
	}

	return
}

// Merge in additional features in the current features.
merge_features :: proc(
	current: ^$T,
	merge_in: T,
	loc := #caller_location,
) {
	assert(current != nil, "Invalid current `PhysicalDeviceFeatures`", loc)

	merge_in := merge_in
	requested_info := type_info_of(T)

	#partial switch info in requested_info.variant {
	case runtime.Type_Info_Named:
		#partial switch field in info.base.variant {
		case runtime.Type_Info_Struct:
			for i in 0 ..< field.field_count {
				switch field.names[i] {
				case "sType", "pNext": continue /* preserve the chain */
				}

				assert(field.types[i].id == type_info_of(b32).id, "Invalid feature field", loc)

				offset := field.offsets[i]

				// Get pointers to the boolean values
				current_value_ptr := (^b32)(uintptr(current) + offset)
				merge_in_value := (^b32)(uintptr(&merge_in) + offset)^

				// OR operation: enable if enabled in either
				current_value_ptr^ = current_value_ptr^ || merge_in_value
			}
		}
	case:
		unreachable()
	}
}

check_device_features_support :: proc(
	requested: vk.PhysicalDeviceFeatures,
	supported: vk.PhysicalDeviceFeatures,
	extension_requested: []Generic_Feature,
	extension_supported: []Generic_Feature,
	loc := #caller_location,
) -> bool {
	check_features_10(requested, supported) or_return

	// Should only be false if extension_supported was unable to be filled out, due to the
	// physical device not supporting vk.GetPhysicalDeviceFeatures2 in any capacity.
	if len(extension_requested) != len(extension_supported) {
		return false
	}

	for i in 0 ..< len(extension_requested) {
		if !generic_features_match(extension_requested[i], extension_supported[i], loc) {
			return false
		}
	}

	return true
}

find_unsupported_features_in_list :: proc(
	requested: vk.PhysicalDeviceFeatures,
	supported: vk.PhysicalDeviceFeatures,
	extensions_requested: []Generic_Feature,
	extensions_supported: []Generic_Feature,
	allocator := context.allocator,
	loc := #caller_location,
) -> []string {
	unsupported_features := make([dynamic]string, allocator)

	supported := supported
	requested := requested

	requested_info := type_info_of(vk.PhysicalDeviceFeatures)

	#partial switch info in requested_info.variant {
	case runtime.Type_Info_Named:
		#partial switch field in info.base.variant {
		case runtime.Type_Info_Struct:
			for i in 0 ..< field.field_count {
				name := field.names[i]
				offset := field.offsets[i]

				requested_value := (^b32)(uintptr(&requested) + offset)^
				supported_value := (^b32)(uintptr(&supported) + offset)^

				if requested_value && !supported_value {
					append(&unsupported_features, name)
				}
			}
		}
	case:
		unreachable()
	}

	// Should only be false if extension_supported was unable to be filled out, due to the
	// physical device not supporting vk.GetPhysicalDeviceFeatures2 in any capacity.
	if len(extensions_requested) != len(extensions_supported) {
		return unsupported_features[:]
	}

	for i in 0 ..< len(extensions_requested) {
		extension_requested := &extensions_requested[i]
		extension_supported := &extensions_supported[i]

		assert(extension_requested != nil, "Invalid requested generic features", loc)
		assert(extension_supported != nil, "Invalid supported generic features", loc)
		assert(extension_requested.pNext.sType == extension_supported.pNext.sType,
			"Non-matching sTypes in features nodes!", loc)
		assert(extension_requested.type == extension_supported.type,
			"Non-matching extension types!", loc)

		ti := type_info_of(extension_requested.type)

		// Ensure it's a struct
		struct_info, is_struct := ti.variant.(runtime.Type_Info_Struct)
		assert(is_struct, "Generic_Feature type is not a struct", loc)

		field_count := min(struct_info.field_count, FEATURES_BITS_FIELDS_CAPACITY)
		assert(field_count > 2, "Invalid generic feature structure", loc)

		// Start at 2 to skip fields sType and pNext
		for i in 2 ..< field_count {
			// Check if the requested feature bit is not set, no need to compare
			if !extension_requested.pNext.fields[i] { continue }
			// Check if the supported feature bit is NOT set
			if !extension_supported.pNext.fields[i] {
				append(&unsupported_features, struct_info.names[i])
			}
		}
	}

	return unsupported_features[:]
}

// =============================================================================
// Load Vulkan Library
// =============================================================================

Vulkan_Library :: struct {
	get_instance_proc_addr: vk.ProcGetInstanceProcAddr,
	module:                 dynlib.Library,
	loaded:                 bool,
	init_mutex:             sync.Mutex,
}

@(private="file")
g_vklib: Vulkan_Library

@(require_results)
load_library :: proc(
	fp_get_instance_proc_addr: vk.ProcGetInstanceProcAddr = nil,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	sync.guard(&g_vklib.init_mutex)

	// Can immediately return if it has already been loaded
	if g_vklib.loaded {
		return true
	}

	if fp_get_instance_proc_addr != nil {
		g_vklib.get_instance_proc_addr = fp_get_instance_proc_addr
	} else {
		module: dynlib.Library
		loaded: bool

		when ODIN_OS == .Windows {
			module, loaded = dynlib.load_library("vulkan-1.dll")
		} else when ODIN_OS == .Darwin {
			module, loaded = dynlib.load_library("libvulkan.dylib", true)

			if !loaded {
				module, loaded = dynlib.load_library("libvulkan.1.dylib", true)
			}

			if !loaded {
				module, loaded = dynlib.load_library("libMoltenVK.dylib", true)
			}

			// Add support for using Vulkan and MoltenVK in a Framework. App store rules for iOS
			// strictly enforce no .dylib's. If they aren't found it just falls through
			if !loaded {
				module, loaded = dynlib.load_library("vulkan.framework/vulkan", true)
			}

			if !loaded {
				module, loaded = dynlib.load_library("MoltenVK.framework/MoltenVK", true)
				ta := context.temp_allocator
				runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
				_, found_lib_path := os.lookup_env("DYLD_FALLBACK_LIBRARY_PATH", ta)
				// modern versions of macOS don't search /usr/local/lib automatically contrary to
				// what man dlopen says Vulkan SDK uses this as the system-wide installation
				// location, so we're going to fallback to this if all else fails
				if !loaded && !found_lib_path {
					module, loaded = dynlib.load_library("/usr/local/lib/libvulkan.dylib", true)
				}
			}
		} else {
			module, loaded = dynlib.load_library("libvulkan.so.1", true)
			if !loaded {
				module, loaded = dynlib.load_library("libvulkan.so", true)
			}
		}

		if !loaded || module == nil {
			return
		}

		g_vklib.module = module
		if fp, found := dynlib.symbol_address(module, "vkGetInstanceProcAddr"); found {
			g_vklib.get_instance_proc_addr = auto_cast fp
		} else {
			return
		}
	}

	// Load the base vulkan procedures before we can start using them
	vk.load_proc_addresses_global(auto_cast g_vklib.get_instance_proc_addr)

	g_vklib.loaded = true

	return true
}

@(fini)
unload_library :: proc "contextless" () {
	if !g_vklib.loaded || g_vklib.module == nil {
		return
	}
	context = runtime.default_context()
	dynlib.unload_library(g_vklib.module)
	g_vklib.module = nil
}
