package main

// Core
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"

// Vendor
import "vendor:glfw"
import vk "vendor:vulkan"

// Local packages
import vkb "./../../"

MAX_FRAMES_IN_FLIGHT :: 2
MINIMUM_API_VERSION  :: vk.API_VERSION_1_2

Init :: struct {
	window:          glfw.WindowHandle,
	instance:        ^vkb.Instance,
	surface:         vk.SurfaceKHR,
	physical_device: ^vkb.Physical_Device,
	device:          ^vkb.Device,
	swapchain:       ^vkb.Swapchain,
}

Render_Data :: struct {
	graphics_queue:        vk.Queue,
	present_queue:         vk.Queue,

	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,
	framebuffers:          []vk.Framebuffer,

	render_pass:           vk.RenderPass,
	pipeline_layout:       vk.PipelineLayout,
	graphics_pipeline:     vk.Pipeline,

	command_pool:          vk.CommandPool,
	command_buffers:       []vk.CommandBuffer,

	available_semaphores:  []vk.Semaphore,
	finished_semaphores:   []vk.Semaphore,
	in_flight_fences:      []vk.Fence,
	image_in_flight:       []vk.Fence,
	current_frame:         uint,
}

create_window_glfw :: proc(
	window_name: string,
	resize := true,
) -> glfw.WindowHandle {
	ensure(bool(glfw.Init()), "Failed to initialize GLFW")
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if !resize { glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE) }

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	window_cname := strings.clone_to_cstring(window_name, context.temp_allocator)
	return glfw.CreateWindow(640, 480, window_cname, nil, nil)
}

destroy_window_glfw :: proc(window: glfw.WindowHandle) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

create_surface_glfw :: proc(
	instance: vk.Instance,
	window: glfw.WindowHandle,
	allocator: ^vk.AllocationCallbacks = nil,
) -> (
	surface: vk.SurfaceKHR,
) {
    res := glfw.CreateWindowSurface(instance, window, allocator, &surface)
    if res != .SUCCESS {
    	error_msg, error_code := glfw.GetError()
    	if error_code != 0 {
    		fmt.eprintfln("[GLFW %v]: %s", error_code, error_msg)
    	}
    }
	return
}

device_initialization :: proc(init: ^Init) -> (ok: bool) {
	window := create_window_glfw("Vulkan Triangle", resize = true)
	defer if !ok { destroy_window_glfw(window) }

	instance_builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(instance_builder)

	vkb.instance_builder_require_api_version(instance_builder, MINIMUM_API_VERSION)

	when ODIN_DEBUG {
		info, info_err := vkb.get_system_info()
		if info_err != nil {
			fmt.eprintfln("Failed to get system info: %#v", info_err)
			return
		}
		defer vkb.destroy_system_info(info)

		vkb.instance_builder_use_default_debug_messenger(instance_builder)
		vkb.instance_builder_request_validation_layers(instance_builder)

		VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

		if vkb.system_info_is_layer_available(info, VK_LAYER_LUNARG_MONITOR) {
			// Displays FPS in the application's title bar. It is only compatible with the
			// Win32 and XCB windowing systems. Mark as not required layer.
			// https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
			when ODIN_OS == .Windows || ODIN_OS == .Linux {
				vkb.instance_builder_enable_layer(instance_builder, VK_LAYER_LUNARG_MONITOR)
			}
		}
	}

	vkb_instance, vkb_instance_err := vkb.instance_builder_build(instance_builder)
	if vkb_instance_err != nil {
		fmt.eprintfln("Failed to build instance: %#v", vkb_instance_err)
		return
	}
	defer if !ok {
		vkb.destroy_instance(vkb_instance)
	}

	// Surface
	surface := create_surface_glfw(vkb_instance.instance, window)
	defer if !ok {
		vkb.destroy_surface(vkb_instance, surface)
	}

	// Physical device
	selector := vkb.create_physical_device_selector(vkb_instance)
	defer vkb.destroy_physical_device_selector(selector)

	vkb.physical_device_selector_set_minimum_version(selector, MINIMUM_API_VERSION)
	vkb.physical_device_selector_set_surface(selector, surface)

	vkb_physical_device, vkb_physical_device_err := vkb.physical_device_selector_select(selector)
	if vkb_physical_device_err != nil {
		fmt.eprintfln("Failed to select physical device: %#v", vkb_physical_device_err)
		return
	}
	defer if !ok {
		vkb.destroy_physical_device(vkb_physical_device)
	}

	// Deice
	device_builder := vkb.create_device_builder(vkb_physical_device)
	defer vkb.destroy_device_builder(device_builder)

	vkb_device, vkb_device_err := vkb.device_builder_build(device_builder)
	if vkb_device_err != nil {
		fmt.eprintfln("Failed to get logical device: %#v", vkb_device_err)
		return
	}

	init.window = window
	init.instance = vkb_instance
	init.surface = surface
	init.physical_device = vkb_physical_device
	init.device = vkb_device

	return true
}

create_swapchain :: proc(init: ^Init) -> (ok: bool) {
	builder := vkb.create_swapchain_builder(init.device)
	defer vkb.destroy_swapchain_builder(builder)

	vkb.swapchain_builder_set_old_swapchain(builder, init.swapchain)
	// Set default surface format and color space: `B8G8R8A8_SRGB, SRGB_NONLINEAR`
	vkb.swapchain_builder_use_default_format_selection(builder)
	// Use hard VSync, which will limit the FPS to the speed of the monitor
	vkb.swapchain_builder_set_desired_present_mode(builder, .FIFO)

	swapchain, swapchain_err := vkb.swapchain_builder_build(builder)
	if swapchain_err != nil {
		fmt.eprintfln("Failed to build swapchain: %#v", swapchain_err)
		return
	}
	if init.swapchain != nil {
		vkb.destroy_swapchain(init.swapchain)
	}
	init.swapchain = swapchain
	return true
}

get_queues :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	graphics_queue, graphics_queue_err := vkb.device_get_queue(init.device, .Graphics)
	if graphics_queue_err != nil {
		fmt.eprintfln("Failed to get graphics queue: %#v", graphics_queue_err)
		return
	}

	present_queue, present_queue_err := vkb.device_get_queue(init.device, .Present)
	if present_queue_err != nil {
		fmt.eprintfln("Failed to get present queue: %#v", present_queue_err)
		return
	}

	data.graphics_queue = graphics_queue
	data.present_queue = present_queue

	return true
}

create_render_pass :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	color_attachment := vk.AttachmentDescription {
		format         = init.swapchain.image_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
	}

	render_pass_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	if res := vk.CreateRenderPass(
		init.device.device,
		&render_pass_info,
		nil,
		&data.render_pass,
	); res != .SUCCESS {
		log.fatalf("Failed to create render pass: [%v]", res)
		return
	}

	return true
}

create_shader_module :: proc(init: ^Init, code: []u8) -> (shader_module: vk.ShaderModule, ok: bool) {
	vertex_module_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	if res := vk.CreateShaderModule(
		init.device.device,
		&vertex_module_info,
		nil,
		&shader_module,
	); res != .SUCCESS {
		log.fatalf("failed to create shader module: [%v]", res)
		return
	}

	return shader_module, true
}

create_graphics_pipeline :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	// Create the modules for each shader
	vertex_shader_code := #load("./shaders/shader_vert.spv")
	vertex_shader_module := create_shader_module(init, vertex_shader_code) or_return
	defer vk.DestroyShaderModule(init.device.device, vertex_shader_module, nil)

	fragment_shader_code := #load("./shaders/shader_frag.spv")
	fragment_shader_module := create_shader_module(init, fragment_shader_code) or_return
	defer vk.DestroyShaderModule(init.device.device, fragment_shader_module, nil)

	// Create stage info for each shader
	vertex_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertex_shader_module,
		pName  = "main",
	}

	fragment_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragment_shader_module,
		pName  = "main",
	}

	shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_stage_info, fragment_stage_info}

	// Dynamic state
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = cast(u32)len(dynamic_states),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// State for vertex input
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 0,
		pVertexBindingDescriptions      = nil,
		vertexAttributeDescriptionCount = 0,
		pVertexAttributeDescriptions    = nil,
	}

	// State for assembly
	input_assembly_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// State for viewport scissor
	viewport := vk.Viewport {
		x        = 0.0,
		y        = 0.0,
		width    = cast(f32)init.swapchain.extent.width,
		height   = cast(f32)init.swapchain.extent.height,
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = init.swapchain.extent,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = &viewport,
		scissorCount  = 1,
		pScissors     = &scissor,
	}

	// State for rasteriser
	rasteriser := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1.0,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
	}

	// State for multisampling
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = false,
		rasterizationSamples  = {._1},
		minSampleShading      = 1.0,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	// State for colour blending
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = {.R, .G, .B, .A},
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
		blendConstants  = {0.0, 0.0, 0.0, 0.0},
	}

	// Pipeline layout
	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 0,
		pSetLayouts            = nil,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}

	if res := vk.CreatePipelineLayout(
		init.device.device,
		&pipeline_layout_info,
		nil,
		&data.pipeline_layout,
	); res != .SUCCESS {
		log.fatalf("Failed to create pipeline layout: [%v]", res)
		return
	}

	// pipeline finally
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = u32(len(shader_stages)),
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly_info,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasteriser,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		layout              = data.pipeline_layout,
		renderPass          = data.render_pass,
		subpass             = 0,
	}

	if res := vk.CreateGraphicsPipelines(
		init.device.device,
		0,
		1,
		&pipeline_info,
		nil,
		&data.graphics_pipeline,
	); res != .SUCCESS {
		log.fatalf("Failed to create graphics pipeline: [%v]", res)
		return
	}

	return true
}

create_framebuffers :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	swapchain_images, swapchain_images_err := vkb.swapchain_get_images(init.swapchain)
	if swapchain_images_err != nil {
		fmt.eprintfln("Failed to get swapchain images: %#v", swapchain_images_err)
		return
	}

	swapchain_image_views,swapchain_image_views_err := vkb.swapchain_get_image_views(init.swapchain)
	if swapchain_image_views_err != nil {
		fmt.eprintfln("Failed to get swapchain image views: %#v", swapchain_image_views_err)
		return
	}

	data.swapchain_images = swapchain_images
	data.swapchain_image_views = swapchain_image_views

	data.framebuffers = make([]vk.Framebuffer, len(data.swapchain_image_views))

	for v, i in data.swapchain_image_views {
		attachments := []vk.ImageView{v}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = data.render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments),
			width           = init.swapchain.extent.width,
			height          = init.swapchain.extent.height,
			layers          = 1,
		}

		if res := vk.CreateFramebuffer(
			init.device.device,
			&framebuffer_info,
			nil,
			&data.framebuffers[i],
		); res != .SUCCESS {
			log.fatalf("failed to create framebuffers: [%v]", res)
			return
		}
	}

	return true
}

create_command_pool :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	queue_family_index, queue_family_index_err := vkb.device_get_queue_index(init.device, .Graphics)
	if queue_family_index_err != nil {
		fmt.eprintfln("Failed to get queue index: %#v", queue_family_index_err)
		return
	}

	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_family_index,
	}

	if res := vk.CreateCommandPool(
		init.device.device,
		&create_info,
		nil,
		&data.command_pool,
	); res != .SUCCESS {
		log.fatalf("Failed to create command pool: [%v]", res)
		return
	}

	return true
}

create_command_buffers :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	data.command_buffers = make([]vk.CommandBuffer, len(data.framebuffers))
	defer if !ok { delete(data.command_buffers) }

	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = data.command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(data.command_buffers)),
	}

	if res := vk.AllocateCommandBuffers(
		init.device.device,
		&allocate_info,
		raw_data(data.command_buffers),
	); res != .SUCCESS {
		log.fatalf("Failed to allocate command buffers: [%v]", res)
		return
	}

	for &cmdbuf, image_index in data.command_buffers {
		record_command_buffer(init, data, cmdbuf, u32(image_index)) or_return
	}

	return true
}

record_command_buffer :: proc(
	init: ^Init,
	data: ^Render_Data,
	buffer: vk.CommandBuffer,
	image_index: u32,
) -> (
	ok: bool,
) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	if res := vk.BeginCommandBuffer(buffer, &begin_info); res != .SUCCESS {
		log.errorf("Failed to begin recording command buffer: [%v]", res)
		return
	}

	clear_color := vk.ClearValue {
		color = {
			float32 = { 0.0, 0.0, 0.0, 1.0, },
		},
	}

	render_pass_info := vk.RenderPassBeginInfo {
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = data.render_pass,
		framebuffer     = data.framebuffers[image_index],
		renderArea      = { offset = {0, 0}, extent = init.swapchain.extent },
		clearValueCount = 1,
		pClearValues    = &clear_color,
	}

	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = f32(init.swapchain.extent.width)
	viewport.height = f32(init.swapchain.extent.height)
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0

	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = init.swapchain.extent

	vk.CmdSetViewport(buffer, 0, 1, &viewport)
	vk.CmdSetScissor(buffer, 0, 1, &scissor)

	vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE)

	vk.CmdBindPipeline(buffer, .GRAPHICS, data.graphics_pipeline)

	vk.CmdDraw(buffer, 3, 1, 0, 0)

	vk.CmdEndRenderPass(buffer)

	if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
		log.errorf("Failed to record command buffer: [%v]", res)
		return
	}

	return true
}

create_sync_objects :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	data.available_semaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	data.finished_semaphores = make([]vk.Semaphore, init.swapchain.image_count)
	data.in_flight_fences = make([]vk.Fence, MAX_FRAMES_IN_FLIGHT)
	data.image_in_flight = make([]vk.Fence, init.swapchain.image_count)

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = { .SIGNALED },
	}

	for i in 0 ..< init.swapchain.image_count {
		if res := vk.CreateSemaphore(
			init.device.device,
			&semaphore_info,
			nil,
			&data.finished_semaphores[i],
		); res != .SUCCESS {
			log.errorf("failed to create synchronization objects for a frame: [%v]", res)
			return
		}
    }

    for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if res := vk.CreateSemaphore(
			init.device.device,
			&semaphore_info,
			nil,
			&data.available_semaphores[i],
		); res != .SUCCESS {
			log.errorf("failed to create synchronization objects for a frame: [%v]", res)
			return
		}

		if res := vk.CreateFence(init.device.device, &fence_info, nil, &data.in_flight_fences[i]);
		   res != .SUCCESS {
			log.errorf("Failed to create \"in_flight\" fence: [%v]", res)
			return
		}
    }

	return true
}

recreate_swapchain :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	vk.DeviceWaitIdle(init.device.device)

	vk.DestroyCommandPool(init.device.device, data.command_pool, nil)

	delete(data.command_buffers)

	for &v in data.framebuffers {
		vk.DestroyFramebuffer(init.device.device, v, nil)
	}
	delete(data.framebuffers)

	vkb.swapchain_destroy_image_views(init.swapchain, data.swapchain_image_views)
	delete(data.swapchain_images)
	delete(data.swapchain_image_views)

	if !create_swapchain(init) { return }
	if !create_framebuffers(init, data) { return }
	if !create_command_pool(init, data) { return }
	if !create_command_buffers(init, data) { return }

	return true
}

draw_frame :: proc(init: ^Init, data: ^Render_Data) -> (ok: bool) {
	vk.WaitForFences(
		init.device.device,
		1,
		&data.in_flight_fences[data.current_frame],
		true,
		max(u64),
	)

	image_index: u32 = 0
	if res := vk.AcquireNextImageKHR(
		init.device.device,
		init.swapchain.swapchain,
		max(u64),
		data.available_semaphores[data.current_frame],
		0,
		&image_index,
	); res == .ERROR_OUT_OF_DATE_KHR {
		return recreate_swapchain(init, data)
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		log.errorf("Failed to acquire swap chain image: [%v]", res)
		return
	}

	// Wait for the fence associated with this image if it's in use
	if data.image_in_flight[image_index] != 0 {
		vk.WaitForFences(
			init.device.device,
			1,
			&data.image_in_flight[image_index],
			true,
			max(u64),
		)
	}
	data.image_in_flight[image_index] = data.in_flight_fences[data.current_frame]

	wait_semaphores := []vk.Semaphore{data.available_semaphores[data.current_frame]}
	signal_semaphores := []vk.Semaphore{data.finished_semaphores[image_index]}

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = raw_data(wait_semaphores),
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 1,
		pCommandBuffers      = &data.command_buffers[image_index],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = raw_data(signal_semaphores),
	}

	// Reset fence before submitting
	vk.ResetFences(init.device.device, 1, &data.in_flight_fences[data.current_frame])

	if res := vk.QueueSubmit(
		data.graphics_queue,
		1,
		&submit_info,
		data.in_flight_fences[data.current_frame],
	); res != .SUCCESS {
		log.errorf("failed to submit draw command buffer: [%v]", res)
		return
	}

	swapchains := []vk.SwapchainKHR{init.swapchain.swapchain}
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = raw_data(signal_semaphores),
		swapchainCount     = 1,
		pSwapchains        = raw_data(swapchains),
		pImageIndices      = &image_index,
	}

	if res := vk.QueuePresentKHR(data.present_queue, &present_info);
	   res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
		return recreate_swapchain(init, data)
	} else if res != .SUCCESS {
		log.errorf("failed to present swapchain image: [%v]", res)
		return
	}

	data.current_frame = (data.current_frame + 1) % MAX_FRAMES_IN_FLIGHT

	return true
}

cleanup :: proc(init: ^Init, data: ^Render_Data) {
	// Wait for all operations to complete before cleanup
	vk.DeviceWaitIdle(init.device.device)

	// Destroy synchronization objects
	for i in 0 ..< init.swapchain.image_count {
		vk.DestroySemaphore(init.device.device, data.finished_semaphores[i], nil)
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(init.device.device, data.available_semaphores[i], nil)
		vk.DestroyFence(init.device.device, data.in_flight_fences[i], nil)
	}
	delete(data.finished_semaphores)
	delete(data.available_semaphores)
	delete(data.in_flight_fences)
	delete(data.image_in_flight)

	// Destroy command pool (this automatically frees command buffers)
	vk.DestroyCommandPool(init.device.device, data.command_pool, nil)
	delete(data.command_buffers)

	// Destroy framebuffers
	for framebuffer in data.framebuffers {
		vk.DestroyFramebuffer(init.device.device, framebuffer, nil)
	}
	delete(data.framebuffers)

	// Destroy pipeline and render pass
	vk.DestroyPipeline(init.device.device, data.graphics_pipeline, nil)
	vk.DestroyPipelineLayout(init.device.device, data.pipeline_layout, nil)
	vk.DestroyRenderPass(init.device.device, data.render_pass, nil)

	// Destroy swapchain resources
	vkb.swapchain_destroy_image_views(init.swapchain, data.swapchain_image_views)
	delete(data.swapchain_image_views)
	delete(data.swapchain_images)
	vkb.destroy_swapchain(init.swapchain)

	// Destroy device and instance
	vkb.destroy_device(init.device)
	vkb.destroy_physical_device(init.physical_device)
	vkb.destroy_surface(init.instance, init.surface)
	vkb.destroy_instance(init.instance)

	// Destroy window
	destroy_window_glfw(init.window)
}

main :: proc() {
	init: Init
	render_data: Render_Data

	if !device_initialization(&init) { return }
	if !create_swapchain(&init) { return }
	if !get_queues(&init, &render_data) { return }
	if !create_render_pass(&init, &render_data) { return }
	if !create_graphics_pipeline(&init, &render_data) { return }
	if !create_framebuffers(&init, &render_data) { return }
	if !create_command_pool(&init, &render_data) { return }
	if !create_command_buffers(&init, &render_data) { return }
	if !create_sync_objects(&init, &render_data) { return }

	for !glfw.WindowShouldClose(init.window) {
        glfw.PollEvents()
        if res := draw_frame(&init, &render_data); !res {
        	fmt.eprintln("Failed to draw frame")
        	return
        }
    }

	cleanup(&init, &render_data)
	fmt.println("Exiting...")
}
