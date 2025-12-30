package system_info

// Core
import "core:fmt"

// Local packages
import vkb "../../"

// Vendor
import vk "vendor:vulkan"

main :: proc() {
	// Get Vulkan system information
	info, info_err := vkb.get_system_info()
	if info_err != nil {
		fmt.eprintfln("Failed to get system info: %#v", info_err)
		return
	}
	defer vkb.destroy_system_info(info)

	instance_builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(instance_builder)

	// Check for a layer
    if vkb.system_info_is_layer_available(info, "VK_LAYER_LUNARG_api_dump") {
        vkb.instance_builder_enable_layer(instance_builder, "VK_LAYER_LUNARG_api_dump")
    }

	// Of course dedicated variable for validation
    if (info.validation_layers_available) {
		vkb.instance_builder_enable_validation_layers(instance_builder)
		// Validation needs to send errors via a callback, have vk-bootstrap do it
		vkb.instance_builder_use_default_debug_messenger(instance_builder)
    }

	// If you need an instance level extension
    if vkb.system_info_is_extension_available(info, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME) {
        vkb.instance_builder_enable_extension(
			instance_builder, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)
    }

	vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder)
	if vkb_instance_err != nil {
		fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
		return
	}
	defer vkb.destroy_instance(vkb_instance)

    // fancy app logic
}
