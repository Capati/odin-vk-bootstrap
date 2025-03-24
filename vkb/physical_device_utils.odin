package vk_bootstrap

// Core
import "base:runtime"

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

	required_loop: for req_ext in required_extensions {
		for &avail_ext in available_extensions {
			if cstring(&avail_ext.extensionName[0]) == req_ext {
				continue required_loop
			}
		}
		log_warnf("Required extension \x1b[33m%s\x1b[0m is not available", req_ext)
		supported = false
	}

	return
}

/* Check features 1.0. */
check_features_10 :: proc(requested, supported: vk.PhysicalDeviceFeatures) -> bool {
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
					log_warnf("Feature \x1b[33m%s\x1b[0m requested but not supported", name)
					return false
				}
			}
		}
	}

	return true
}

check_device_features_support :: proc(
	requested: vk.PhysicalDeviceFeatures,
	supported: vk.PhysicalDeviceFeatures,
	extension_requested: []Generic_Feature,
	extension_supported: []Generic_Feature,
) -> bool {
	check_features_10(requested, supported) or_return

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
