package vkb_test

// Core
import "core:testing"

// Vendor
import vk "vendor:vulkan"

// Local packages
import "../vkb"

@(test)
test_queue_selection :: proc(t: ^testing.T) {
	// Test case 1: get_first_queue_index - Basic graphics queue
	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.TRANSFER}},
		}

		index := vkb.get_first_queue_index(families, {.GRAPHICS})
		testing.expect(t, index == 0, "Expected first queue with graphics support (index 0)")
	}

	// Test case 2: get_first_queue_index - No matching queue
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

	// Test case 3: get_separate_queue_index - Separate compute queue
	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS, .COMPUTE}},
			{queueFlags = {.COMPUTE}},
			{queueFlags = {.TRANSFER}},
		}

		index := vkb.get_separate_queue_index(families, {.COMPUTE}, {.TRANSFER})
		testing.expect(t, index == 1, "Expected separate compute queue without transfer (index 1)")
	}

	// Test case 4: get_separate_queue_index - Fallback to suboptimal queue
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

	// Test case 5: get_dedicated_queue_index - Dedicated compute queue
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

	// Test case 6: get_dedicated_queue_index - No dedicated queue
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

	// Test case 7: get_present_queue_index - Basic present support
	// Note: This is a simplified test as actual Vulkan device interaction is required
	{
		families := []vk.QueueFamilyProperties {
			{queueFlags = {.GRAPHICS}},
			{queueFlags = {.COMPUTE}},
		}

		// Without actual device and surface, we can only test the no-surface case
		index := vkb.get_present_queue_index(families, nil)
		testing.expect(
			t,
			index == vk.QUEUE_FAMILY_IGNORED,
			"Expected QUEUE_FAMILY_IGNORED with null surface",
		)
	}

	// Test case 8: Empty families array
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
