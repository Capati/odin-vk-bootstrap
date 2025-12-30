# CHANGELOG

- All VKB objects now accept an allocator
- Builder objects no longer return errors
- Removed optional `ok` in favor of detailed error objects
- Removed logging
- Use full procedure names  
  (`instance_set_surface` → `instance_builder_set_surface`)
- Improved tests using a mocked Vulkan API
- Examples: replaced `SDL2` with `GLFW`
- Examples: added new examples:
    - `system_info`
    - `custom_debug_callback`
- Examples: fixed the `triangle` example with latest changes
- Added `physical_device_get_supported_features`
- Added `physical_device_find_queue_family_index`
- Renamed `convert_vulkan_to_vma_version` → `VK_API_VERSION_TO_DECIMAL`
- All code is now in `vkbootstrap.odin` at the project root
- Keep previous code at `vkb-old``for reference
