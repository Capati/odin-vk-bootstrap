# Getting Started

`odin-vk-bootstrap` reduces the complexity of setting up a vulkan application by simplifying the three initial steps; **instance creation**, **Physical device selection**, and **device creation**.

## Enable Logging

You can create a logger to see debug messages (information, warnings and errors), do this before create the instance builder:

```odin
when ODIN_DEBUG {
    context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
    defer log.destroy_console_logger(context.logger)
}
```

## Instance Creation

Creating an instance with `odin-vk-bootstrap` uses the `vkb.init_instance_builder` procedure. Most builders do some work that can fail, you need to check before continue.

The builder can return a valid `Instance_Builder` variable and a possible error:

```odin
instance_builder, instance_builder_err := vkb.init_instance_builder()
if instance_builder_err != nil do return // error
// destroy the builder after the vulkan handle is created
defer vkb.destroy_instance_builder(&instance_builder)
```

When you ready to create an instance, call the procedure `vkb.build_instance`. You need to check for error because creating an instance may fail:

```odin
instance, instance_err := vkb.build_instance(&instance_builder)
if instance_err != nil do return // error
// When the application is finished with the vulkan, call `vkb.destroy_instance` to
// free internal data and destroy the wrapped `vk.Instance`
defer vkb.destroy_instance(instance)
```

The created `instance` is a pointer of a `vkb.Instance` that wraps the actual Vulkan `vk.Instance` handle in the filed `.ptr`. Later you can use that field to pass the `vk.Instance` to some vulkan function:

```odin
sdl.Vulkan_CreateSurface(window, instance.ptr, &surface)
```

This is enough to create a usable `vk.Instance` handle but many will want to customize it a bit. To configure instance creation, simply call the procedures  `vkb.instance_xxx` passing an `Instance_Builder`, do this before `vkb.build_instance()` is called.

The most common customization to instance creation is enabling the "Validation Layers", an invaluable tool for any vulkan application developer:

```odin
// Enable `VK_LAYER_KHRONOS_validation` layer
vkb.instance_request_validation_layers(&instance_builder)
```

The other common customization point is setting up the `Debug Messenger Callback`, the mechanism in which an application can control what and where the "Validation Layers" log its output:

```odin
default_debug_callback :: proc "system" (
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: rawptr,
) -> b32 {
    context = runtime.default_context()

    if message_severity == {.WARNING} {
        fmt.printf("WARNING: [%v]\n%s\n", message_types, p_callback_data.pMessage)
    } else if message_severity == {.ERROR} {
        fmt.printf("ERROR: [%v]\n%s\n", message_types, p_callback_data.pMessage)
    } else {
        fmt.printf("INFO: [%v]\n%s\n", message_types, p_callback_data.pMessage)
    }

    return false // Applications must return false here
}
```

Alternatively, `odin-vk-bootstrap` provides a 'default debug messenger' that prints to standard output (you need to create a logger):

```odin
// Enable debug reporting with a default messenger callback
vkb.instance_use_default_debug_messenger(&instance_builder)
```

To query the available layers and extensions, you can use the field `instance_builder.info` (type of `System_Info`) that was filled when the instance builder was created, or create one by calling `vkb.get_system_info()`. Then call `vkb.is_layer_available()` and `vkb.is_extension_available()` procedure to check for a layer or extensions before enabling it.

It also has booleans for if the validation layers are present and if the `VK_EXT_debug_utils` extension is available:

```odin
if vkb.is_layer_available(&instance_builder.info, "VK_LAYER_LUNARG_api_dump") {
    vkb.instance_enable_layer(&instance_builder, "VK_LAYER_LUNARG_api_dump")
}

if instance_builder.info.validation_layers_available {
    vkb.instance_enable_validation_layers(&instance_builder)
}
```

The `vkb.Instance` struct is meant to hold all the necessary instance level data to enable proper Physical Device selection. It also is meant for easy use into custom struct if so desired:

```odin
State :: struct {
    instance: ^vkb.Instance,
    ...
}
```

## Surface Creation

Presenting images to the screen Vulkan requires creating a surface, encapsulated in a `vk.SurfaceKHR` handle. Creating a surface is the responsibility of the windowing system, thus is out of scope for `odin-vk-bootstrap`. However, `odin-vk-bootstrap` does try to make the process as painless as possible by automatically enabling the correct windowing extensions in `vk.Instance` creation.

Windowing libraries which support Vulkan usually provide a way of getting the `vk.SurfaceKHR` handle for the window. These methods require a valid Vulkan instance, thus must be done after instance creation.

Examples for GLFW and SDL2 are listed below:

```odin
instance: vkb.Instance; //valid vkb.Instance
surface: vk.SurfaceKHR

// window is a valid library specific Window handle

// GLFW
err := glfw.CreateWindowSurface (instance.ptr, window, NULL, &surface)
if err != .SUCCESS { /* handle error */ }

// SDL2
// You need to create a window with the `.VULKAN` flag:
window_flags: sdl.WindowFlags = {.VULKAN, .ALLOW_HIGHDPI, .SHOWN}
...
// After window creation:
if !sdl.Vulkan_CreateSurface(window, instance.ptr, &surface) {
    // handle error
    return
}
```

## Physical Device Selection

Once a Vulkan instance has been created, the next step is to find a suitable GPU for the application to use. `odin-vk-bootstrap` provide the `vkb.Physical_Device_Selector` to streamline this process, it can be created using `vkb.init_physical_device_selector`.

Creating a `vkb.Physical_Device_Selector` requires a valid `vkb.Instance` to construct.

It follows the same pattern laid out by `vkb.Instance_Builder`.

```odin
selector := vkb.init_physical_device_selector(instance) or_return
defer vkb.destroy_physical_device_selector(&selector)

vkb.selector_set_surface(&selector, surface_handle)

physical_device, physical_device_err := vkb.select_physical_device(&selector)
if physical_device_err != nil do return // error
// In Vulkan you don't need to destroy a physical device, but here you need
// to free some resources when the physical device was created.
defer vkb.destroy_physical_device(physical_device)
```

To select a physical device, call `vkb.select_physical_device(&selector)`.

By default, this will prefer a discrete GPU.

The `vkb.Physical_Device_Selector` will look for the first device in the list that satisfied all the specified criteria, and if none is found, will return the first device that partially satisfies the criteria.

A "require" procedure indicate to `odin-vk-bootstrap` what features and capabilities are necessary for an application and what are simply preferred and will fail any `vk.PhysicalDevice` that doesn't satisfy the constraint. Some criteria options that doesn't satisfy the "desire" settings will make the `vk.PhysicalDevice` only 'partially satisfy'.

```odin
// Application cannot function without this extension
vkb.selector_add_required_extension(&selector, "VK_KHR_timeline_semaphore")
```

**Note**: Because `odin-vk-bootstrap` does not manage creating a `vk.SurfaceKHR` handle, it is explicitly passed into the `vkb.Physical_Device_Selector` for proper querying of surface support details. Unless the `vkb.instance_set_headless(&builder)` procedure was called, the physical device selector will emit `No_Surface_Provided` error. If an application does intend to present but cannot create a `vk.SurfaceKHR` handle before physical device selection, use `vkb.selector_defer_surface_initialization()` to disable the `No_Surface_Provided` error.

## Device Creation

Once a `vk.PhysicalDevice` has been selected, a `vk.Device` can be created. Facilitating that is the `vkb.Device_Builder`. Creation and usage follows the forms laid out by `vkb.Instance_Builder`.

```odin
device_builder, device_builder_err := vkb.init_device_builder(physical_device)
if device_builder_err != nil do return // error
defer vkb.destroy_device_builder(&device_builder)

device, device_err := vkb.build_device(&device_builder)
if device_err != nil do return // error
// To destroy a `vkb.Device`, call `vkb.destroy_device(device)`.
defer vkb.destroy_device(device)
 ```

The features and extensions used as selection criteria in `vkb.Physical_Device_Selector` automatically propagate into `vkb.Device_Builder`. Because of this, there is no way to enable features or extensions that were not specified during `vkb.Physical_Device_Selector`. This is by design as any feature or extension enabled in a device *must* have support from the `vk.PhysicalDevice` it is created with.

The common method to extend Vulkan functionality in existing API calls is to use the pNext chain. This is accounted for `Vk.Device` creation with the `device_builder_add_p_next` procedure. Note: Any structures added to the pNext chain must remain valid until `vkb.build_device()` is called:

```odin
descriptor_indexing_features := vk.PhysicalDeviceDescriptorIndexingFeatures{}
vkb.device_builder_add_p_next(&device_builder, &descriptor_indexing_features)
```

### Queues

By default, `vkb..Device_Builder` will enable one queue from each queue family available on the `Vk.PhysicalDevice`. This is done because in practice, most use cases only need a single queue from each family.

To get a `Vk.Queue` or the index of a `Vk.Queue`, use the `vkb.device_get_queue(Device, Queue_Type)` and `vkb.device_get_queue_index(Device, Queue_Type)` procedures. These will return the appropriate `Vk.Queue` or `u32` if they exist and were enabled, else they will return an error.

```odin
graphics_queue, graphics_queue_err := vkb.device_get_queue(device, .Graphics)
if graphics_queue_err != nil do return // error
```

Queue families represent a set of queues with similar operations, such as graphics, transfer, and compute. Because not all Vulkan hardware has queue families for each operation category, an application should be able to handle the presence or lack of certain queue families. For this reason the `vkb.device_get_dedicated_queue`  and `vkb.device_get_dedicated_queue_index` procedures exist to allow applications to easily know if there is a queue dedicated to a particular operation, such as compute or transfer operations.

#### Custom queue setup

If an application wishes to have more fine grained control over their queue setup, they should create a `slice` or a `dynamic array` of `vkb.Custom_Queue_Description` which describe the index and a `[]f32` of priorities.

When no custom queue description is given, use the procedure `vkb.device_builder_graphics_queue_has_priority(&device_builder, true)` to make graphics queue the priority from others queue.

But to build up such data as you wish, use the `vkb.physical_device_get_queue_families(physical_device)` procedure or access `physical_device.queue_families` to get a `[]vk.QueueFamilyProperties`.

For example

```odin
queue_descriptions: [dynamic]vkb.Custom_Queue_Description
for f, i in state.physical_device.queue_families {
    // Find the first queue family with graphics operations supported
    if .GRAPHICS in f.queueFlags {
        append(&queue_descriptions, vkb.Custom_Queue_Description{u32(i), {1.0}})
    }
}
```

Then call `vkb.device_builder_custom_queue_setup(&device_builder, queue_descriptions[:])`.

## Swapchain

Creating a swapchain follows the same form outlined by `vkb.Instance_Builder` and `vkb.Device_Builder`. Create the `vkb.Swapchain_Builder` by providing the `vkb.Device`, call the appropriate builder procedures, and call `vkb.build_swapchain(&swapchain_builder)`.

```odin
swapchain_builder, swapchain_builder_err := vkb.init_swapchain_builder(device)
if swapchain_builder_err != nil do return // error
defer vkb.destroy_swapchain_builder(&swapchain_builder)

swapchain, swapchain_err := vkb.build_swapchain(&swapchain_builder)
if swapchain_err != nil do return // error
// To destroy the swapchain, call `vkb.destroy_swapchain(swapchain)`
defer vkb.destroy_swapchain(swapchain)
```

By default, the swapchain will use the `.FORMAT_B8G8R8A8_SRGB` or `.FORMAT_R8G8B8A8_SRGB` image format with the color space `.COLOR_SPACE_SRGB_NONLINEAR_KHR`. The present mode will default to `.PRESENT_MODE_MAILBOX_KHR` if available and fallback to `.PRESENT_MODE_FIFO_KHR`. The image usage default flag is `{.COLOR_ATTACHMENT}`.

Recreating the swapchain is equivalent to creating a new swapchain but providing the old swapchain as a source. Be sure to not use the same `vk.SwapchainKHR` again as it expires when it is recycled after trying to create a new swapchain.

```odin
vkb.swapchain_builder_set_old_swapchain(&swapchain_builder, swapchain)
new_swapchain, swapchain_err := vkb.build_swapchain(&swapchain_builder)
if swapchain_err != nil {
    // If it failed to create a swapchain, the old swapchain handle is invalid.
    swapchain.ptr = 0
}
// Even though we recycled the previous swapchain, we need to free its resources.
vkb.destroy_swapchain(swapchain)
swapchain = new_swapchain
```
