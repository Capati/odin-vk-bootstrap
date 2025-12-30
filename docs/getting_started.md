# Getting Started

`odin-vk-bootstrap` reduces the complexity of setting up a Vulkan application by simplifying
the three initial steps; **instance creation**, **Physical device selection**, and **device
creation**.

## Instance Creation

Creating an instance with `odin-vk-bootstrap` uses the `vkb.create_instance_builder` procedure.

```odin
instance_builder := vkb.create_instance_builder()
// You can destroy the builder after the instance handle is created
defer vkb.destroy_instance_builder(instance_builder)
```

When you ready to create an instance, call the procedure `vkb.instance_builder_build`. You need to
check for error because creating an instance may fail:

```odin
vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder)
if vkb_instance_err != nil {
    fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
    return
}
// When the application is finished with the Vulkan, call `vkb.destroy_instance` to
// free internal data and destroy the wrapped `vk.Instance`
defer vkb.destroy_instance(vkb_instance)
```

The created `vkb_instance` is a pointer of a `vkb.Instance` that wraps the actual Vulkan
`vk.Instance` handle in the filed `.instance`. The `vkb.Instance` struct is meant to hold all the
necessary instance level data to enable proper Physical Device selection. It also is meant for easy
use into custom struct if so desired:

```odin
State :: struct {
    instance: ^vkb.Instance,
    ...
}
```

Later you can use the `.instance` field to pass the `vk.Instance` to some Vulkan function:

```odin
sdl.Vulkan_CreateSurface(window, vkb_instance.instance, &surface)
```

You can also use an arena allocator or any temporary allocator to manage the lifetime of builder
objects. This approach allows you to extract the underlying Vulkan handles and clean up the
intermediate vkb objects once initialization is complete.

```odin
// Use the default temporary allocator
ta := context.temp_allocator

builder := vkb.create_instance_builder(ta)
// defer vkb.destroy_instance_builder(builder)

vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder, ta)
if vkb_instance_err != nil {
    fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
    return
}
// defer vkb.destroy_instance(vkb_instance)

// Get the Vulkan handles
vk_instance := vkb_instance.instance
vk_debug_messenger := vkb.debug_messenger

// At this point, the vkb objects can be destroyed as you now own the Vulkan handles
```

This is also valid for other vkb objects, however, further API usage depends on vkb objects, which
should be destroyed only after all the initialization process has finished.

This is enough to create a usable `vk.Instance` handle but many will want to customize it a bit. To
configure instance creation, simply call the procedures  `vkb.instance_builder_xxx` passing an
`Instance_Builder`, do this before `vkb.instance_builder_build()` is called.

The most common customization to instance creation is enabling the "Validation Layers", an
invaluable tool for any Vulkan application developer:

```odin
// Enable `VK_LAYER_KHRONOS_validation` layer
vkb.instance_builder_request_validation_layers(instance_builder)
```

The other common customization point is setting up the `Debug Messenger Callback`, the
mechanism in which an application can control what and where the "Validation Layers" log its
output:

```odin
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
```

The previous procedure is the default debug messenger that prints to `os.stderr`. You can copy that
procedure and modify for your application, then set your own callback:

```odin
vkb.instance_builder_set_debug_callback(instance_builder, default_debug_callback)
```

To query the available layers and extensions, you can get the system info by calling
`vkb.get_system_info()`.

```odin
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
}
```

Then call `vkb.system_info_is_layer_available()` and `vkb.system_info_is_extension_available
()` procedure to check for a layer or extensions before enabling it.

```odin
if vkb.system_info_is_layer_available(info, "VK_LAYER_LUNARG_api_dump") {
    vkb.instance_enable_layer(instance_builder, "VK_LAYER_LUNARG_api_dump")
}
```

The `System_Info` also has booleans to check if the validation layers are present and if the
`VK_EXT_debug_utils` extension is available:

```odin
if info.validation_layers_available {
    vkb.instance_builder_request_validation_layers(instance_builder)
}
```

## Surface Creation

Presenting images to the screen Vulkan requires creating a surface, encapsulated in a
`vk.SurfaceKHR` handle. Creating a surface is the responsibility of the windowing system, thus is
out of scope for `odin-vk-bootstrap`. However, `odin-vk-bootstrap` does try to make the process as
painless as possible by automatically enabling the correct windowing extensions in instance
creation.

Windowing libraries which support Vulkan usually provide a way of getting the `vk.SurfaceKHR` handle
for the window. These methods require a valid Vulkan instance, thus must be done after instance
creation.

Examples for GLFW and SDL2 are listed below:

```odin
vkb_instance: vkb.Instance // Valid vkb.Instance
surface: vk.SurfaceKHR

// window is a valid library specific Window handle

// GLFW
err := glfw.CreateWindowSurface (vkb_instance.instance, window, nil, &surface)
if err != .SUCCESS { /* handle error */ }

// SDL2
// You need to create a window with the `.VULKAN` flag:
window_flags: sdl.WindowFlags = {.VULKAN, .ALLOW_HIGHDPI, .SHOWN}
...
// After window creation:
if !sdl.Vulkan_CreateSurface(window, vkb_instance.instance, &surface) {
    // handle error
    return
}
```

## Physical Device Selection

Once a Vulkan instance has been created, the next step is to find a suitable GPU for the
application to use. `odin-vk-bootstrap` provide the `vkb.Physical_Device_Selector` to
streamline this process, it can be created using `vkb.init_physical_device_selector`.

Creating a `vkb.Physical_Device_Selector` requires a valid `vkb.Instance` to construct.

It follows the same pattern laid out by `vkb.Instance_Builder`.

```odin
selector := vkb.create_physical_device_selector(vkb_instance)
defer vkb.destroy_physical_device_selector(selector)

vkb.physical_device_selector_set_surface(&selector, surface_handle)

vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
if vkb_physical_device_err != nil {
    fmt.eprintfln("Failed to select physical device: %#v", vkb_physical_device_err)
    return
}
// In Vulkan you don't need to destroy a physical device, but here you need
// to free some resources when the physical device was created.
defer vkb.destroy_physical_device(physical_device)
```

To select a physical device, call `vkb.physical_device_selector_select(&selector)`.

By default, this will prefer a discrete GPU.

The `vkb.Physical_Device_Selector` will look for the first device in the list that satisfied
all the specified criteria, and if none is found, will return the first device that partially
satisfies the criteria.

A "require" procedure indicate to `odin-vk-bootstrap` what features and capabilities are necessary
for an application and what are simply preferred and will fail any `vk.PhysicalDevice` that doesn't
satisfy the constraint. Some criteria options that doesn't satisfy the "desire" settings will make
the `vk.PhysicalDevice` only 'partially satisfy'.

```odin
// Application cannot function without this extension
vkb.physical_device_selector_add_required_extension(&selector, "VK_KHR_timeline_semaphore")
```

**Note**: Because `odin-vk-bootstrap` does not manage creating a `vk.SurfaceKHR` handle, it is
  explicitly passed into the `vkb.Physical_Device_Selector` for proper querying of surface support
  details. Unless the `vkb.instance_builder_set_headless(builder)` procedure was called, the
  physical device selector will emit `No_Surface_Provided` error. If an application does intend to
  present but cannot create a `vk.SurfaceKHR` handle before physical device selection, use
  `vkb.physical_device_selector_defer_surface_initialization()` to disable the
  `No_Surface_Provided` error.

## Device Creation

Once a `vk.PhysicalDevice` has been selected, a `vk.Device` can be created. This process is
facilitated by `vkb.Device_Builder`. Creation and usage follows the forms laid out by
`vkb.Instance_Builder`.

```odin
device_builder := vkb.create_device_builder(vkb_physical_device)
defer vkb.destroy_device_builder(device_builder)

vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
if vkb_device_err != nil {
    fmt.eprintfln("Failed to get logical device: %#v", vkb_device_err)
    return
}
// To destroy a `vkb.Device`, call `vkb.destroy_device(device)`.
defer vkb.destroy_device(device)
 ```

The features and extensions used as selection criteria in `vkb.Physical_Device_Selector`
automatically propagate into `vkb.Device_Builder`. Because of this, there is no way to enable
features or extensions that were not specified during `vkb.Physical_Device_Selector`. This is
by design as any feature or extension enabled in a device *must* have support from the
`vk.PhysicalDevice` it is created with.

The common method to extend Vulkan functionality in existing API calls is to use the pNext
chain. This is accounted for `Vk.Device` creation with the `device_builder_add_pnext`
procedure. Note: Any structures added to the pNext chain must remain valid until
`vkb.device_builder_build()` is called:

```odin
descriptor_indexing_features := vk.PhysicalDeviceDescriptorIndexingFeatures{}
vkb.device_builder_add_pnext(device_builder, &descriptor_indexing_features)
```

### Queues

By default, `vkb..Device_Builder` will enable one queue from each queue family available on the
`Vk.PhysicalDevice`. This is done because in practice, most use cases only need a single queue
from each family.

To get a `Vk.Queue` or the index of a `Vk.Queue`, use the `vkb.device_get_queue
(vkb_device, Queue_Type)` and `vkb.device_get_queue_index(vkb_device, Queue_Type)` procedures.
These will return the appropriate `Vk.Queue` or `u32` if they exist and were enabled, else they
will return an error.

```odin
graphics_queue, graphics_queue_err := vkb.device_get_queue(vkb_device, .Graphics)
if graphics_queue_err != nil {
    fmt.eprintfln("Failed to get graphics queue: %#v", graphics_queue_err)
    return
}
```

Queue families represent a set of queues with similar operations, such as graphics, transfer,
and compute. Because not all Vulkan hardware has queue families for each operation category, an
application should be able to handle the presence or lack of certain queue families. For this
reason the `vkb.device_get_dedicated_queue`  and `vkb.device_get_dedicated_queue_index`
procedures exist to allow applications to easily know if there is a queue dedicated to a
particular operation, such as compute or transfer operations.

#### Custom queue setup

If an application wishes to have more fine grained control over their queue setup, they should
create an array of `vkb.Custom_Queue_Description` which describe the index and a `[]f32` of
priorities.

But to build up such data as you wish, use the `vkb.physical_device_get_queue_families
(vkb_physical_device)` procedure or access `vkb_physical_device.queue_families` to get a `
[]vk.QueueFamilyProperties`.

For example:

```odin
queue_descriptions: [dynamic]vkb.Custom_Queue_Description
for f, i in vkb_physical_device.queue_families {
    // Find the first queue family with graphics operations supported
    if .GRAPHICS in f.queueFlags {
        append(&queue_descriptions, vkb.Custom_Queue_Description{u32(i), {1.0}})
    }
}
```

Then call `vkb.device_builder_custom_queue_setup(device_builder, queue_descriptions[:])`.

## Swapchain

Creating a swapchain follows the same form outlined by `vkb.Instance_Builder` and
`vkb.Device_Builder`. Create the `vkb.Swapchain_Builder` by providing the `vkb.Device`, call
the appropriate builder procedures, and call `vkb.swapchain_builder_build(swapchain_builder)`.

```odin
swapchain_builder := vkb.create_swapchain_builder(vkb_device)
defer vkb.destroy_swapchain_builder(swapchain_builder)

vkb_swapchain, vkb_swapchain_err := vkb.swapchain_builder_build(swapchain_builder)
if vkb_swapchain_err != nil {
    fmt.eprintfln("Failed to build swapchain: %#v", vkb_swapchain_err)
    return
}
// To destroy the swapchain, call `vkb.destroy_swapchain(swapchain)`
defer vkb.destroy_swapchain(vkb_swapchain)
```

By default, the swapchain will use the `.FORMAT_B8G8R8A8_SRGB` or `.FORMAT_R8G8B8A8_SRGB` image
format with the color space `.COLOR_SPACE_SRGB_NONLINEAR_KHR`. The present mode will default to
`.PRESENT_MODE_MAILBOX_KHR` if available and fallback to `.PRESENT_MODE_FIFO_KHR`. The image
usage default flag is `{.COLOR_ATTACHMENT}`.

Recreating the swapchain is equivalent to creating a new swapchain but providing the old
swapchain as a source. Be sure to not use the same `vk.SwapchainKHR` again as it expires when
it is recycled after trying to create a new swapchain.

```odin
vkb.swapchain_builder_set_old_swapchain(swapchain_builder, vkb_swapchain)
vkb_new_swapchain, vkb_new_swapchain_err := vkb.swapchain_builder_build(swapchain_builder)
if vkb_new_swapchain_err != nil {
    // If it failed to create a swapchain, the old swapchain handle is invalid.
    vkb_swapchain.swapchain = 0
}
// Even though we recycled the previous swapchain, we need to free its resources.
if vkb_swapchain != nil {
    vkb.destroy_swapchain(vkb_swapchain)
}
vkb_swapchain = vkb_new_swapchain
```
