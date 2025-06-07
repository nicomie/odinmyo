package app

import vk "vendor:vulkan"
import "core:os"
import "core:fmt"



Pipeline :: struct {
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, pos),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color),
	},
    {
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, texCoord),
	},
}

VERTEX_BINDING := vk.VertexInputBindingDescription{
    binding = 0,
    stride = size_of(Vertex),
    inputRate = .VERTEX,
}

create_mesh_pipeline :: proc(using r: ^Renderer, layout: vk.PipelineLayout) -> vk.Pipeline {
    vertShaderCode, _ := os.read_entire_file_from_filename("shaders/vert.spv")
    fragShaderCode, _ := os.read_entire_file_from_filename("shaders/frag.spv")
    defer delete(vertShaderCode)
    defer delete(fragShaderCode)

    vertShaderModule := create_shader_module(vertShaderCode, device)
    fragShaderModule := create_shader_module(fragShaderCode, device)
    defer vk.DestroyShaderModule(device, vertShaderModule, nil)
    defer vk.DestroyShaderModule(device, fragShaderModule, nil)

    vertShaderStage := vk.PipelineShaderStageCreateInfo{
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.VERTEX},
        module = vertShaderModule,
        pName = "main",
    }

    fragShaderStage := vk.PipelineShaderStageCreateInfo{
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.FRAGMENT},
        module = fragShaderModule,
        pName = "main",
    }

    shaderStages := []vk.PipelineShaderStageCreateInfo{vertShaderStage, fragShaderStage}

    vertexInput := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = &VERTEX_BINDING,
        vertexAttributeDescriptionCount = cast(u32)len(VERTEX_ATTRIBUTES),
        pVertexAttributeDescriptions = &VERTEX_ATTRIBUTES[0],
    }

    inputAssembly := vk.PipelineInputAssemblyStateCreateInfo{
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    viewport := vk.Viewport{
        x = 0,
        y = 0,
        width = cast(f32)swapchain.extent.width,
        height = cast(f32)swapchain.extent.height,
        minDepth = 0,
        maxDepth = 1,
    }

    scissor := vk.Rect2D{
        offset = {0, 0},
        extent = swapchain.extent,
    }

    viewportState := vk.PipelineViewportStateCreateInfo{
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &viewport,
        scissorCount = 1,
        pScissors = &scissor,
    }

    rasterizer := vk.PipelineRasterizationStateCreateInfo{
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable = false,
        rasterizerDiscardEnable = false,
        polygonMode = .FILL,
        lineWidth = 1.0,
        cullMode = {.BACK},
        frontFace = .COUNTER_CLOCKWISE,
        depthBiasEnable = false,
    }

    multisampling := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1}, 
    }

    depthStencil := vk.PipelineDepthStencilStateCreateInfo{
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = true,
        depthWriteEnable = true,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable = false,
    }

    colorBlendAttachment := vk.PipelineColorBlendAttachmentState{
        colorWriteMask = {.R, .G, .B, .A},
        blendEnable = false,
    }

    colorBlending := vk.PipelineColorBlendStateCreateInfo{
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable = false,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &colorBlendAttachment,
        blendConstants = {0, 0, 0, 0},
    }

    pipelineInfo := vk.GraphicsPipelineCreateInfo{
        sType = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = cast(u32)len(shaderStages),
        pStages = &shaderStages[0],
        pVertexInputState = &vertexInput,
        pInputAssemblyState = &inputAssembly,
        pViewportState = &viewportState,
        pRasterizationState = &rasterizer,
        pMultisampleState = &multisampling,
        pDepthStencilState = &depthStencil,
        pColorBlendState = &colorBlending,
        layout = layout,
        renderPass = render_pass.render_pass,
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create mesh pipeline")
        os.exit(1)
    }

    return pipeline
}

create_pipeline_layout :: proc(
    r: ^Renderer,
    config: PipelineLayoutConfig,
) -> (layout: vk.PipelineLayout, err: vk.Result) {
    
    create_info := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &r.descriptor_set_layouts[PipelineType.Main],
        pushConstantRangeCount = 0,
    }

    if vk.CreatePipelineLayout(r.device, &create_info, nil, &layout) != .SUCCESS {
        return {}, .ERROR_INITIALIZATION_FAILED
    }

    return layout, .SUCCESS
}

init_pipeline_layouts :: proc(r: ^Renderer) -> (layouts: PipelineLayoutCollection, err: vk.Result) {
    main_config := PipelineLayoutConfig{
        descriptor_layout = r.descriptor_set_layouts[PipelineType.Main],
        label = "Main Pipeline Layout",
    }
    layouts.layouts[.Main], err = create_pipeline_layout(r, main_config)
    if err != .SUCCESS do return {}, err

    return layouts, .SUCCESS
}
