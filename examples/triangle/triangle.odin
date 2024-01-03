package main

// Core
import "core:fmt"
import "core:log"
import "core:mem"

// Vendor
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

// Package
import "./../../vkb"

State :: struct {
	window:          ^sdl.Window,
	instance:        ^vkb.Instance,
	surface:         vk.SurfaceKHR,
	physical_device: ^vkb.Physical_Device,
	device:          ^vkb.Device,
	swapchain:       ^vkb.Swapchain,
	is_minimized:    bool,
}

Render_Data :: struct {
	graphics_queue:        vk.Queue,
	present_queue:         vk.Queue,
	swapchain_images:      []vk.Image,
	swapchain_image_views: []vk.ImageView,
	frame_buffers:         []vk.Framebuffer,
	render_pass:           vk.RenderPass,
	pipeline_layout:       vk.PipelineLayout,
	graphics_pipeline:     vk.Pipeline,
	command_pool:          vk.CommandPool,
	command_buffers:       []vk.CommandBuffer,
	available_semaphores:  []vk.Semaphore,
	finished_semaphores:   []vk.Semaphore,
	in_flight_fences:      []vk.Fence,
	current_frame:         uint,
}

MAX_FRAMES_IN_FLIGHT :: 2
MINIMUM_API_VERSION :: vk.API_VERSION_1_2

General_Error :: enum {
	None,
	SDL_Init_Failed,
	Vulkan_Error,
}

Error :: union #shared_nil {
	General_Error,
	vkb.Error,
}

create_window_sdl :: proc(
	window_title: cstring,
	resize := true,
) -> (
	window: ^sdl.Window,
	err: Error,
) {
	sdl_flags := sdl.InitFlags{.VIDEO}
	if res := sdl.Init(sdl_flags); res != 0 {
		log.errorf("Failed to initialize SDL: [%s]", sdl.GetError())
		return nil, .SDL_Init_Failed
	}
	defer if err != nil do sdl.Quit()

	window_flags: sdl.WindowFlags = {.VULKAN, .ALLOW_HIGHDPI, .SHOWN}

	if resize do window_flags += {.RESIZABLE}

	window = sdl.CreateWindow(
		window_title,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		800,
		600,
		window_flags,
	)
	if window == nil {
		log.errorf("Failed to create a SDL window: [%s]", sdl.GetError())
		return nil, .SDL_Init_Failed
	}

	return
}

destroy_window_sdl :: proc(window: ^sdl.Window) {
	sdl.DestroyWindow(window)
	sdl.Quit()
}

device_initialization :: proc(s: ^State) -> (err: Error) {
	// Window
	s.window = create_window_sdl("Vulkan Triangle", true) or_return
	defer if err != nil do destroy_window_sdl(s.window)

	// Instance
	instance_builder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&instance_builder)
	vkb.instance_set_minimum_version(&instance_builder, MINIMUM_API_VERSION)

	when ODIN_DEBUG {
		vkb.instance_request_validation_layers(&instance_builder)
		vkb.instance_use_default_debug_messenger(&instance_builder)

		VK_LAYER_LUNARG_MONITOR :: "VK_LAYER_LUNARG_monitor"

		if vkb.is_layer_available(&instance_builder.info, VK_LAYER_LUNARG_MONITOR) {
			// Displays FPS in the application's title bar. It is only compatible with the
			// Win32 and XCB windowing systems. Mark as not required layer.
			// https://vulkan.lunarg.com/doc/sdk/latest/windows/monitor_layer.html
			when ODIN_OS == .Windows || ODIN_OS == .Linux {
				vkb.instance_enable_layer(&instance_builder, VK_LAYER_LUNARG_MONITOR)
			}
		}
	}

	s.instance = vkb.build_instance(&instance_builder) or_return
	defer if err != nil do vkb.destroy_instance(s.instance)

	// Surface
	if !sdl.Vulkan_CreateSurface(s.window, s.instance.ptr, &s.surface) {
		log.errorf("SDL couldn't create vulkan surface: %s", sdl.GetError())
		return
	}
	defer if err != nil do vkb.destroy_surface(s.instance, s.surface)

	// Physical device
	selector := vkb.init_physical_device_selector(s.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, MINIMUM_API_VERSION)
	vkb.selector_set_surface(&selector, s.surface)

	s.physical_device = vkb.select_physical_device(&selector) or_return
	defer if err != nil do vkb.destroy_physical_device(s.physical_device)

	// Deice
	device_builder := vkb.init_device_builder(s.physical_device) or_return
	defer vkb.destroy_device_builder(&device_builder)

	s.device = vkb.build_device(&device_builder) or_return

	return
}

create_swapchain :: proc(s: ^State, width, height: u32) -> (err: vkb.Error) {
	builder := vkb.init_swapchain_builder(s.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, s.swapchain)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	// Set default surface format and color space: `B8G8R8A8_SRGB, SRGB_NONLINEAR`
	vkb.swapchain_builder_use_default_format_selection(&builder)
	// Use hard VSync, which will limit the FPS to the speed of the monitor
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)

	swapchain := vkb.build_swapchain(&builder) or_return
	vkb.destroy_swapchain(s.swapchain)
	s.swapchain = swapchain

	return
}

get_queue :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	data.graphics_queue = vkb.device_get_queue(s.device, .Graphics) or_return
	data.present_queue = vkb.device_get_queue(s.device, .Present) or_return
	return
}

create_render_pass :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	color_attachment := vk.AttachmentDescription {
		format = s.swapchain.image_format,
		samples = {._1},
		loadOp = .CLEAR,
		storeOp = .STORE,
		stencilLoadOp = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout = .UNDEFINED,
		finalLayout = .PRESENT_SRC_KHR,
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
		srcSubpass = vk.SUBPASS_EXTERNAL,
		dstSubpass = 0,
		srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
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

	if res := vk.CreateRenderPass(s.device.ptr, &render_pass_info, nil, &data.render_pass);
	   res != .SUCCESS {
		log.fatalf("Failed to create render pass: [%v]", res)
		return .Vulkan_Error
	}

	return
}

create_shader_module :: proc(
	s: ^State,
	code: []u8,
) -> (
	shader_module: vk.ShaderModule,
	err: Error,
) {
	vertex_module_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = cast(^u32)raw_data(code),
	}

	if res := vk.CreateShaderModule(s.device.ptr, &vertex_module_info, nil, &shader_module);
	   res != .SUCCESS {
		log.fatalf("failed to create shader module: [%v]", res)
		return 0, .Vulkan_Error
	}

	return
}

create_graphics_pipeline :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	// Create the modules for each shader
	vertex_shader_code := #load("./shaders/shader_vert.spv")
	vertex_shader_module := create_shader_module(s, vertex_shader_code) or_return
	defer vk.DestroyShaderModule(s.device.ptr, vertex_shader_module, nil)

	fragment_shader_code := #load("./shaders/shader_frag.spv")
	fragment_shader_module := create_shader_module(s, fragment_shader_code) or_return
	defer vk.DestroyShaderModule(s.device.ptr, fragment_shader_module, nil)

	// Create stage info for each shader
	vertex_stage_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.VERTEX},
		module = vertex_shader_module,
		pName = "main",
	}

	fragment_stage_info := vk.PipelineShaderStageCreateInfo {
		sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage = {.FRAGMENT},
		module = fragment_shader_module,
		pName = "main",
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
		width    = cast(f32)s.swapchain.extent.width,
		height   = cast(f32)s.swapchain.extent.height,
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = s.swapchain.extent,
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
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {.BACK},
		frontFace = .CLOCKWISE,
		depthBiasEnable = false,
	}

	// State for multisampling
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable = false,
		rasterizationSamples = {._1},
		minSampleShading = 1.0,
		pSampleMask = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable = false,
	}

	// State for colour blending
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp = .ADD,
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable = false,
		logicOp = .COPY,
		attachmentCount = 1,
		pAttachments = &color_blend_attachment,
		blendConstants = {0.0, 0.0, 0.0, 0.0},
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
		s.device.ptr,
		&pipeline_layout_info,
		nil,
		&data.pipeline_layout,
	); res != .SUCCESS {
		log.fatalf("Failed to create pipeline layout: [%v]", res)
		return .Vulkan_Error
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
		s.device.ptr,
		0,
		1,
		&pipeline_info,
		nil,
		&data.graphics_pipeline,
	); res != .SUCCESS {
		log.fatalf("Failed to create graphics pipeline: [%v]", res)
		return .Vulkan_Error
	}

	return
}

create_framebuffers :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	data.swapchain_images = vkb.swapchain_get_images(s.swapchain) or_return
	data.swapchain_image_views = vkb.swapchain_get_image_views(s.swapchain) or_return

	data.frame_buffers = make([]vk.Framebuffer, len(data.swapchain_image_views))

	for v, i in data.swapchain_image_views {
		attachments := []vk.ImageView{v}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = data.render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments),
			width           = s.swapchain.extent.width,
			height          = s.swapchain.extent.height,
			layers          = 1,
		}

		if res := vk.CreateFramebuffer(
			s.device.ptr,
			&framebuffer_info,
			nil,
			&data.frame_buffers[i],
		); res != .SUCCESS {
			log.fatalf("failed to create framebuffers: [%v]", res)
			return .Vulkan_Error
		}
	}

	return
}

create_command_pool :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	create_info := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = vkb.device_get_queue_index(s.device, .Graphics) or_return,
	}

	if res := vk.CreateCommandPool(s.device.ptr, &create_info, nil, &data.command_pool);
	   res != .SUCCESS {
		log.fatalf("Failed to create command pool: [%v]", res)
		return .Vulkan_Error
	}

	return
}

create_command_buffers :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	data.command_buffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
	defer if err != nil do delete(data.command_buffers)

	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = data.command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(data.command_buffers)),
	}

	if res := vk.AllocateCommandBuffers(
		s.device.ptr,
		&allocate_info,
		raw_data(data.command_buffers),
	); res != .SUCCESS {
		log.fatalf("Failed to allocate command buffers: [%v]", res)
		return .Vulkan_Error
	}

	return
}

record_command_buffer :: proc(
	s: ^State,
	data: ^Render_Data,
	buffer: vk.CommandBuffer,
	image_index: u32,
) -> (
	err: Error,
) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	if res := vk.BeginCommandBuffer(buffer, &begin_info); res != .SUCCESS {
		log.errorf("Failed to begin recording command buffer: [%v]", res)
		return .Vulkan_Error
	}

	clear_color := vk.ClearValue {
		color =  {
			float32 =  {
				0.03561436968491878157417676879363,
				0.22713652550514897375949232016547,
				0.65237010541082120207337791500345,
				1.0,
			},
		},
	}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = data.render_pass,
		framebuffer = data.frame_buffers[image_index],
		renderArea = {offset = {0, 0}, extent = s.swapchain.extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}

	viewport: vk.Viewport
	viewport.x = 0.0
	viewport.y = 0.0
	viewport.width = f32(s.swapchain.extent.width)
	viewport.height = f32(s.swapchain.extent.height)
	viewport.minDepth = 0.0
	viewport.maxDepth = 1.0

	scissor: vk.Rect2D
	scissor.offset = {0, 0}
	scissor.extent = s.swapchain.extent

	vk.CmdSetViewport(buffer, 0, 1, &viewport)
	vk.CmdSetScissor(buffer, 0, 1, &scissor)

	vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE)

	vk.CmdBindPipeline(buffer, .GRAPHICS, data.graphics_pipeline)

	vk.CmdDraw(buffer, 3, 1, 0, 0)

	vk.CmdEndRenderPass(buffer)

	if res := vk.EndCommandBuffer(buffer); res != .SUCCESS {
		log.errorf("Failed to record command buffer: [%v]", res)
		return .Vulkan_Error
	}

	return
}

create_sync_objects :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	data.available_semaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	data.finished_semaphores = make([]vk.Semaphore, MAX_FRAMES_IN_FLIGHT)
	data.in_flight_fences = make([]vk.Fence, MAX_FRAMES_IN_FLIGHT)

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if res := vk.CreateSemaphore(
			s.device.ptr,
			&semaphore_info,
			nil,
			&data.available_semaphores[i],
		); res != .SUCCESS {
			log.errorf("Failed to create \"image_available\" semaphore: [%v]", res)
			return .Vulkan_Error
		}

		if res := vk.CreateSemaphore(
			s.device.ptr,
			&semaphore_info,
			nil,
			&data.finished_semaphores[i],
		); res != .SUCCESS {
			log.errorf("Failed to create \"render_finished\" semaphore: [%v]", res)
			return .Vulkan_Error
		}

		if res := vk.CreateFence(s.device.ptr, &fence_info, nil, &data.in_flight_fences[i]);
		   res != .SUCCESS {
			log.errorf("Failed to create \"in_flight\" fence: [%v]", res)
			return .Vulkan_Error
		}
	}

	return
}

recreate_swapchain :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	width, height: i32
	sdl.GetWindowSize(s.window, &width, &height)

	vk.DeviceWaitIdle(s.device.ptr)

	vk.DestroyCommandPool(s.device.ptr, data.command_pool, nil)

	delete(data.command_buffers)

	for &v in data.frame_buffers {
		vk.DestroyFramebuffer(s.device.ptr, v, nil)
	}
	delete(data.frame_buffers)

	vkb.swapchain_destroy_image_views(s.swapchain, &data.swapchain_image_views)
	delete(data.swapchain_images)
	delete(data.swapchain_image_views)

	if create_swapchain(s, u32(width), u32(height)) != nil do return
	if create_framebuffers(s, data) != nil do return
	if create_command_pool(s, data) != nil do return
	if create_command_buffers(s, data) != nil do return

	return
}

draw_frame :: proc(s: ^State, data: ^Render_Data) -> (err: Error) {
	vk.WaitForFences(s.device.ptr, 1, &data.in_flight_fences[data.current_frame], true, max(u64))
	vk.ResetFences(s.device.ptr, 1, &data.in_flight_fences[data.current_frame])

	image_index: u32 = 0
	if res := vk.AcquireNextImageKHR(
		s.device.ptr,
		s.swapchain.ptr,
		max(u64),
		data.available_semaphores[data.current_frame],
		0,
		&image_index,
	); res == .ERROR_OUT_OF_DATE_KHR {
		return recreate_swapchain(s, data)
	} else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		log.errorf("Failed to acquire swap chain image: [%v]", res)
		return .Vulkan_Error
	}

	vk.ResetCommandBuffer(data.command_buffers[data.current_frame], {})
	record_command_buffer(s, data, data.command_buffers[data.current_frame], image_index)

	wait_semaphores := []vk.Semaphore{data.available_semaphores[data.current_frame]}
	signal_semaphores := []vk.Semaphore{data.finished_semaphores[data.current_frame]}

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = raw_data(wait_semaphores),
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 1,
		pCommandBuffers      = &data.command_buffers[data.current_frame],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = raw_data(signal_semaphores),
	}

	if res := vk.QueueSubmit(
		data.graphics_queue,
		1,
		&submit_info,
		data.in_flight_fences[data.current_frame],
	); res != .SUCCESS {
		log.errorf("failed to submit draw command buffer: [%v]", res)
		return .Vulkan_Error
	}

	swapchains := []vk.SwapchainKHR{s.swapchain.ptr}
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
		return recreate_swapchain(s, data)
	} else if res != .SUCCESS {
		log.errorf("failed to present swapchain image: [%v]", res)
		return .Vulkan_Error
	}

	// When `MAX_FRAMES_IN_FLIGHT` is a power of 2 you can update the current frame without modulo
	// division. Doing a logical "and" operation is a lot cheaper than doing division.
	data.current_frame = (data.current_frame + 1) & (MAX_FRAMES_IN_FLIGHT - 1)
	// data.current_frame = (data.current_frame + 1) % MAX_FRAMES_IN_FLIGHT

	return
}

cleanup :: proc(s: ^State, data: ^Render_Data) {
	vk.DeviceWaitIdle(s.device.ptr)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(s.device.ptr, data.finished_semaphores[i], nil)
		vk.DestroySemaphore(s.device.ptr, data.available_semaphores[i], nil)
		vk.DestroyFence(s.device.ptr, data.in_flight_fences[i], nil)
	}

	delete(data.finished_semaphores)
	delete(data.available_semaphores)
	delete(data.in_flight_fences)

	// vk.FreeCommandBuffers(
	// 	s.device.ptr,
	// 	data.command_pool,
	// 	u32(len(data.command_buffers)),
	// 	raw_data(data.command_buffers),
	// )

	vk.DestroyCommandPool(s.device.ptr, data.command_pool, nil)

	delete(data.command_buffers)

	for &v in data.frame_buffers {
		vk.DestroyFramebuffer(s.device.ptr, v, nil)
	}
	delete(data.frame_buffers)
	delete(data.swapchain_images)

	vk.DestroyPipeline(s.device.ptr, data.graphics_pipeline, nil)
	vk.DestroyPipelineLayout(s.device.ptr, data.pipeline_layout, nil)
	vk.DestroyRenderPass(s.device.ptr, data.render_pass, nil)

	vkb.swapchain_destroy_image_views(s.swapchain, &data.swapchain_image_views)
	delete(data.swapchain_image_views)

	vkb.destroy_swapchain(s.swapchain)
	vkb.destroy_device(s.device)
	vkb.destroy_physical_device(s.physical_device)
	vkb.destroy_surface(s.instance, s.surface)
	vkb.destroy_instance(s.instance)

	destroy_window_sdl(s.window)
}

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
		defer log.destroy_console_logger(context.logger)

		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer mem.tracking_allocator_destroy(&track)

		defer {
			for _, leak in track.allocation_map {
				fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
			}
			for bad_free in track.bad_free_array {
				fmt.printf(
					"%v allocation %p was freed badly\n",
					bad_free.location,
					bad_free.memory,
				)
			}
		}
	}

	state: State
	render_data: Render_Data

	if device_initialization(&state) != nil do return

	width, height: i32
	sdl.GetWindowSize(state.window, &width, &height)
	if create_swapchain(&state, u32(width), u32(height)) != nil do return

	if get_queue(&state, &render_data) != nil do return
	if create_render_pass(&state, &render_data) != nil do return
	if create_graphics_pipeline(&state, &render_data) != nil do return
	if create_framebuffers(&state, &render_data) != nil do return
	if create_command_pool(&state, &render_data) != nil do return
	if create_command_buffers(&state, &render_data) != nil do return
	if create_sync_objects(&state, &render_data) != nil do return

	main_loop: for {
		e: sdl.Event
		for sdl.PollEvent(&e) {
			#partial switch (e.type) {
			case .QUIT:
				break main_loop
			case .WINDOWEVENT:
				#partial switch (e.window.event) {
				case .SIZE_CHANGED:
				case .RESIZED:
					width := cast(u32)e.window.data1
					height := cast(u32)e.window.data2

					// Avoid multiple .SIZE_CHANGED and .RESIZED events at the same time.
					if state.swapchain.extent.width != width ||
					   state.swapchain.extent.height != height {
						recreate_swapchain(&state, &render_data)
					}

				case .MINIMIZED:
					state.is_minimized = true

				case .FOCUS_GAINED:
					state.is_minimized = false
				}
			}
		}

		if !state.is_minimized {
			if res := draw_frame(&state, &render_data); res != nil {
				log.errorf("Failed to draw frame: [%v]", res)
				break main_loop
			}
		}
	}

	cleanup(&state, &render_data)
}
