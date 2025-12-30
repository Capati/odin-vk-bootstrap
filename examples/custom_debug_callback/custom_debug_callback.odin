package custom_debug_callback

// Core
import "base:runtime"
import "core:fmt"

// Local packages
import vkb "../../"

// Vendor
import vk "vendor:vulkan"

main :: proc() {
	builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(builder)

	vkb.instance_builder_request_validation_layers(builder)
	vkb.instance_builder_set_headless(builder)

	vkb.instance_builder_set_debug_callback(builder, proc "system" (
		messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
		messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
		pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
		pUserData: rawptr,
	) -> b32 {
		context = runtime.default_context()
		fmt.eprintfln("[%v]: %s", messageTypes, pCallbackData.pMessage)
        // Return false to move on, but return true for validation to skip passing down
        // the call to the driver
		return true
	})

	vkb_instance, vkb_instance_err := vkb.instance_builder_build(builder)
	if vkb_instance_err != nil {
		fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
		return
	}
	defer vkb.destroy_instance(vkb_instance)

	selector := vkb.create_physical_device_selector(vkb_instance)
	defer vkb.destroy_physical_device_selector(selector)

	vkb.physical_device_selector_add_required_extension(selector, vk.KHR_DRIVER_PROPERTIES_EXTENSION_NAME)

	vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
	if vkb_physical_device_err != nil {
		fmt.eprintfln("Failed to select physical device: %#v", vkb_physical_device_err)
		return
	}
	defer vkb.destroy_physical_device(vkb_physical_device)

	fmt.printfln("Selected device: %s", vkb_physical_device.name)

	device_builder := vkb.create_device_builder(vkb_physical_device)
	defer vkb.destroy_device_builder(device_builder)

	vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
	if vkb_device_err != nil {
		fmt.eprintfln("Failed to get logical device: %#v", vkb_device_err)
		return
	}
	defer vkb.destroy_device(vkb_device)

	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		usage = { .TRANSFER_SRC },
	}

	// Size must be greater than zero!!!
    // We might crash, I hope the validation will come to save us!
    buffer_info.size = 0

	my_buffer: vk.Buffer
    res := vk.CreateBuffer(vkb_device.device, &buffer_info, nil, &my_buffer)
    if res == .ERROR_VALIDATION_FAILED_EXT {
        // If we return true in our callback, the validation will block the function from
        // calling the driver and return back this vk.Result.
    }
}
