package vkb_test

// Core
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

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
		available := []vk.ExtensionProperties {
			create_extension_property("VK_KHR_swapchain"),
			create_extension_property("VK_KHR_surface"),
		}
		required := []cstring{}

		result := vkb.check_device_extension_support(&available, required)
		testing.expect(
			t,
			result == true,
			"Expected true when no required extensions are specified",
		)
	}

	// Test case 2: No available extensions
	{
		available := []vk.ExtensionProperties{}
		required := []cstring{cstring("VK_KHR_swapchain")}

		result := vkb.check_device_extension_support(&available, required)
		testing.expect(t, result == false, "Expected false when there are no available extensions")
	}

	// Test case 3: All required extensions are available
	{
		available := []vk.ExtensionProperties {
			create_extension_property("VK_KHR_swapchain"),
			create_extension_property("VK_KHR_surface"),
			create_extension_property("VK_EXT_debug_utils"),
		}

		required := []cstring{"VK_KHR_swapchain", "VK_KHR_surface"}
		result := vkb.check_device_extension_support(&available, required)
		testing.expect(
			t,
			result == true,
			"Expected true when all required extensions are available",
		)
	}

	// Test case 4: Some required extensions are missing
	{
		available := []vk.ExtensionProperties {
			create_extension_property("VK_KHR_swapchain"),
			create_extension_property("VK_KHR_surface"),
		}

		required := []cstring{"VK_KHR_swapchain", "VK_EXT_debug_utils"}
		result := vkb.check_device_extension_support(&available, required)
		testing.expect(
			t,
			result == false,
			"Expected false when some required extensions are missing",
		)
	}

	// Test case 5: Edge case - empty extension names
	{
		available := []vk.ExtensionProperties {
			create_extension_property(""),
			create_extension_property("VK_KHR_surface"),
		}

		required := []cstring{""}
		result := vkb.check_device_extension_support(&available, required)
		testing.expect(
			t,
			result == true,
			"Expected true when empty extension name is required and available",
		)
	}
}
