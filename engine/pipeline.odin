package engine

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import vk "vendor:vulkan"

createPipelineLayouts :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) {

	pipe := pipelineContext

	pRanges := vk.PushConstantRange {
		stageFlags = {.VERTEX},
		offset     = 0,
		size       = size_of(Mat4),
	}

	meshLayouts := [2]vk.DescriptorSetLayout {
		ctx.globalDescriptorSetLayouts["global"],
		pipe.descriptorSetLayouts["material"],
	}

	pipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = cast(u32)len(meshLayouts),
		pSetLayouts            = &meshLayouts[0],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pRanges,
	}

	if vk.CreatePipelineLayout(
		   ctx.vulkan.device,
		   &pipelineLayoutInfo,
		   nil,
		   &pipe.meshPipelineLayout,
	   ) !=
	   .SUCCESS {
		fmt.eprintln("failed to create pipeline layout")
		os.exit(1)
	}


}

createGlobalPipelineLayouts :: proc(ctx: ^Context) {

	uiPushRange := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = size_of(Vec2),
	}

	compositePipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &ctx.globalDescriptorSetLayouts["composite"],
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &uiPushRange,
	}

	if vk.CreatePipelineLayout(
		   ctx.vulkan.device,
		   &compositePipelineLayoutInfo,
		   nil,
		   &ctx.pipe.compositePipelineLayout,
	   ) !=
	   .SUCCESS {
		fmt.eprintln("failed to create pipeline layout (composite)")
		os.exit(1)
	}
}

createPipelines :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) {
	scenePipeline := createScenePipeline(ctx, pipelineContext)
	compositePipeline := createCompositePipeline(ctx, pipelineContext)
	pipelineContext.pipelines = make(map[string]vk.Pipeline)
	pipelineContext.pipelines["scene"] = scenePipeline
	if ctx.pipe.pipelines == nil {
		ctx.pipe.pipelines = make(map[string]vk.Pipeline)
	}
	ctx.pipe.pipelines["composite"] = compositePipeline

}

createScenePipeline :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) -> vk.Pipeline {
	device := ctx.vulkan.device
	swapchain := ctx.sc.swapchain
	allocator := runtime.heap_allocator()
	exe_dir, err := os.get_executable_directory(allocator)
	if err != nil {
		fmt.eprintln("Failed to get executable directory:", err)
		os.exit(1)
	}

	vertPath, errx := os.join_path({"shaders", "vert.spv"}, allocator)
	fragPath, erry := os.join_path({"shaders", "frag.spv"}, allocator)

	if errx != nil do fmt.println(errx)
	if erry != nil do fmt.println(erry)

	fmt.println(vertPath)
	fmt.println(fragPath)

	vertShaderCode, _ := os.read_entire_file_from_path(vertPath, allocator)
	fragShaderCode, _ := os.read_entire_file_from_path(fragPath, allocator)

	defer delete(vertShaderCode)
	defer delete(fragShaderCode)

	vertShaderModule := createShaderModule(vertShaderCode, device)
	fragShaderModule := createShaderModule(fragShaderCode, device)
	defer vk.DestroyShaderModule(device, vertShaderModule, nil)
	defer vk.DestroyShaderModule(device, fragShaderModule, nil)

	vertShaderStage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertShaderModule,
		pName  = "main",
	}

	fragShaderStage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragShaderModule,
		pName  = "main",
	}

	shaderStages := []vk.PipelineShaderStageCreateInfo{vertShaderStage, fragShaderStage}

	vertexInput := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &VERTEX_BINDING,
		vertexAttributeDescriptionCount = cast(u32)len(VERTEX_ATTRIBUTES),
		pVertexAttributeDescriptions    = &VERTEX_ATTRIBUTES[0],
	}

	inputAssembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewportState := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = nil,
		scissorCount  = 1,
		pScissors     = nil,
	}

	dynamicStates := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamicState := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = cast(u32)len(dynamicStates),
		pDynamicStates    = &dynamicStates[0],
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1.0,
		cullMode                = {.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	depthStencil := vk.PipelineDepthStencilStateCreateInfo {
		sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable       = true,
		depthWriteEnable      = true,
		depthCompareOp        = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	colorBlendAttachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
		blendEnable    = false,
	}

	colorBlending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &colorBlendAttachment,
		blendConstants  = {0, 0, 0, 0},
	}

	renderingInfo := vk.PipelineRenderingCreateInfoKHR {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &ctx.sc.sceneColor.image.format,
		depthAttachmentFormat   = ctx.sc.sceneDepth.image.format,
		stencilAttachmentFormat = .UNDEFINED,
	}

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = cast(u32)len(shaderStages),
		pStages             = &shaderStages[0],
		pVertexInputState   = &vertexInput,
		pInputAssemblyState = &inputAssembly,
		pViewportState      = &viewportState,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pDepthStencilState  = &depthStencil,
		pColorBlendState    = &colorBlending,
		pDynamicState       = &dynamicState,
		layout              = pipelineContext.meshPipelineLayout,
		pNext               = &renderingInfo,
		subpass             = 0,
	}

	pipeline: vk.Pipeline
	result := vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline)
	if result != .SUCCESS {
		fmt.eprintln("failed to create mesh pipeline: ", result)
		os.exit(1)
	}

	return pipeline
}

createCompositePipeline :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) -> vk.Pipeline {
	device := ctx.vulkan.device
	swapchain := ctx.sc.swapchain

	allocator := runtime.heap_allocator()
	vertPath, errx := os.join_path({"shaders", "ui.vert.spv"}, allocator)
	fragPath, erry := os.join_path({"shaders", "ui.frag.spv"}, allocator)

	if errx != nil do fmt.println(errx)
	if erry != nil do fmt.println(erry)

	fmt.println(vertPath)
	fmt.println(fragPath)

	vertShaderCode, _ := os.read_entire_file_from_path(vertPath, allocator)
	fragShaderCode, _ := os.read_entire_file_from_path(fragPath, allocator)
	defer delete(vertShaderCode)
	defer delete(fragShaderCode)

	vertShaderModule := createShaderModule(vertShaderCode, device)
	fragShaderModule := createShaderModule(fragShaderCode, device)
	defer vk.DestroyShaderModule(device, vertShaderModule, nil)
	defer vk.DestroyShaderModule(device, fragShaderModule, nil)

	vertShaderStage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertShaderModule,
		pName  = "main",
	}

	fragShaderStage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragShaderModule,
		pName  = "main",
	}

	shaderStages := []vk.PipelineShaderStageCreateInfo{vertShaderStage, fragShaderStage}

	vertexInput := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &UI_VERTEX_BINDING,
		vertexAttributeDescriptionCount = cast(u32)len(UI_VERTEX_ATTRIBUTES),
		pVertexAttributeDescriptions    = &UI_VERTEX_ATTRIBUTES[0],
	}

	inputAssembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewportState := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		pViewports    = nil,
		scissorCount  = 1,
		pScissors     = nil,
	}

	dynamicStatesUI := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamicStateUI := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = cast(u32)len(dynamicStatesUI),
		pDynamicStates    = &dynamicStatesUI[0],
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1.0,
		cullMode                = nil,
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	depthStencil := vk.PipelineDepthStencilStateCreateInfo {
		sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable       = false,
		depthWriteEnable      = false,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	colorBlendAttachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = {.R, .G, .B, .A},
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
	}

	colorBlending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &colorBlendAttachment,
	}

	renderingInfo := vk.PipelineRenderingCreateInfoKHR {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &ctx.sc.swapchain.format,
		depthAttachmentFormat   = .UNDEFINED,
		stencilAttachmentFormat = .UNDEFINED,
	}

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = cast(u32)len(shaderStages),
		pStages             = &shaderStages[0],
		pVertexInputState   = &vertexInput,
		pInputAssemblyState = &inputAssembly,
		pViewportState      = &viewportState,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pDepthStencilState  = &depthStencil,
		pColorBlendState    = &colorBlending,
		pDynamicState       = &dynamicStateUI,
		layout              = ctx.pipe.compositePipelineLayout,
		subpass             = 0,
		pNext               = &renderingInfo,
	}

	pipeline: vk.Pipeline
	result := vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline)
	if result != .SUCCESS {
		fmt.eprintln("failed to create UI pipeline: ", result)
		os.exit(1)
	}

	return pipeline
}
