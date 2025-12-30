# Odin vk-bootstrap

Inspired by [vk-bootstrap][] for C++, this is a utility library in [Odin Language][] that jump
starts initialization of Vulkan.

Read the [Getting Started](./docs/getting_started.md) guide for a quick start on using
`odin-vk-bootstrap`

## Basic Usage

Just copy the `vkbootstrap.odin` file to your project.

```odin
import "core:fmt"
import "vkb"
import vk "vendor:vulkan"

main :: proc() {
    builder := vkb.create_instance_builder()
    defer vkb.destroy_instance_builder(builder)

    // Require the minimum Vulkan api version 1.1
    vkb.instance_builder_require_api_version(&instance_builder, vk.API_VERSION_1_1)

    when ODIN_DEBUG {
        // Enable `VK_LAYER_KHRONOS_validation` layer
        vkb.instance_builder_enable_validation_layers(&instance_builder)

        // Enable debug reporting with a default messenger callback
        vkb.instance_builder_use_default_debug_messenger(&instance_builder)
    }

    vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder)
    if vkb_instance_err != nil {
        fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
        return
    }
    defer vkb.destroy_instance(vkb_instance)

    // Create a new physical device selector
    selector := vkb.create_physical_device_selector(vkb_instance)
    defer vkb.destroy_physical_device_selector(selector)

    // We want a GPU that can render to current Window surface
    vkb.physical_device_selector_set_surface(&selector, /* from user created window*/)

    // Require a vulkan 1.1 capable device
    vkb.physical_device_selector_set_minimum_version(&selector, vk.API_VERSION_1_1)

    // Try to select a suitable device
    vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
    if vkb_physical_device_err != nil {
        fmt.eprintfln("Failed to select physical device: %#v", vkb_physical_device_err)
        return
    }
    // In Vulkan you don't need to destroy a physical device, but here you need
    // to free some resources when the physical device was created.
    defer vkb.destroy_physical_device(vkb_physical_device)

    // Create a device builder
    device_builder := vkb.create_device_builder(vkb_physical_device)
    defer vkb.destroy_device_builder(device_builder)

    // Automatically propagate needed data from instance & physical device
    vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
    if vkb_device_err != nil {
        fmt.eprintfln("Failed to get logical device: %#v", vkb_device_err)
        return
    }

    // Get the graphics queue with a helper function
    graphics_queue, graphics_queue_err := vkb.device_get_queue(vkb_device, .Graphics)
    if graphics_queue_err != nil {
        fmt.eprintfln("Failed to get graphics queue: %#v", graphics_queue_err)
        return
    }
}
```

See [Triangle Example](./examples//triangle//triangle.odin) for an example that renders a triangle
to the screen.

[Odin Language]: https://odin-lang.org/
[vk-bootstrap]: https://github.com/charles-lunarg/vk-bootstrap/tree/main
