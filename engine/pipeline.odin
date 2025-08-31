package engine

import "core:math/linalg"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createPipelineLayouts :: proc(using ctx: ^Context) {
    using ctx.vulkan
    pRanges := vk.PushConstantRange{
        stageFlags = {.VERTEX},
        offset = 0,
        size = size_of(linalg.Matrix4f32),
    }

    pipelineLayoutInfo := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &descriptorSetLayouts["mesh"],
        pushConstantRangeCount = 1,
        pPushConstantRanges = &pRanges
    }

    if vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &meshPipelineLayout) != .SUCCESS {
        fmt.eprintln("failed to create pipeline layout")
        os.exit(1)
    }

    pipelineLayoutInfo = vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &descriptorSetLayouts["id"],
        pushConstantRangeCount = 1,
        pPushConstantRanges = &pRanges
    }


    if vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &idPipelineLayout) != .SUCCESS {
        fmt.eprintln("failed to create id pipeline layout")
        os.exit(1)
    }
}

createPipelines :: proc(using ctx: ^Context) {
    meshPipeline := createMeshPipeline(ctx)
    idPipeline := createIdPipeline(ctx)
    pipelines = make(map[string]vk.Pipeline)
    pipelines["mesh"] = meshPipeline
    pipelines["id"] = idPipeline

}

createMeshPipeline :: proc(using ctx: ^Context) -> vk.Pipeline {
    using ctx.vulkan

    vertShaderCode, _:= os.read_entire_file_from_filename("shaders/vert.spv")
    fragShaderCode, _:= os.read_entire_file_from_filename("shaders/frag.spv")
    defer delete(vertShaderCode)
    defer delete(fragShaderCode)

    vertShaderModule := createShaderModule(vertShaderCode, device)
    fragShaderModule := createShaderModule(fragShaderCode, device)
    defer vk.DestroyShaderModule(device, vertShaderModule, nil)
    defer vk.DestroyShaderModule(device, fragShaderModule, nil)

    // Shader stages
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

    // Input assembly
    inputAssembly := vk.PipelineInputAssemblyStateCreateInfo{
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    // Viewport and scissor
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

    // Rasterizer
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

    // Multisampling
    multisampling := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1}, 
    }

    // Depth and stencil testing
    depthStencil := vk.PipelineDepthStencilStateCreateInfo{
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = true,
        depthWriteEnable = true,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable = false,
    }

    // Color blending
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

    // Create the pipeline
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
        layout = meshPipelineLayout,
        renderPass = renderPass,
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create mesh pipeline")
        os.exit(1)
    }

    return pipeline
}

createIdPipeline :: proc(using ctx: ^Context) -> vk.Pipeline {
    using ctx.vulkan
    // Load ID shader modules
    vertShaderCode, _:= os.read_entire_file_from_filename("shaders/id-vert.spv") 
    fragShaderCode, _ := os.read_entire_file_from_filename("shaders/id-frag.spv")

    defer delete(vertShaderCode)
    defer delete(fragShaderCode)

    vertShaderModule := createShaderModule(vertShaderCode, device)
    fragShaderModule := createShaderModule(fragShaderCode, device)
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
        cullMode = nil,
        frontFace = .COUNTER_CLOCKWISE,
        depthBiasEnable = false,
    }

    multisampling := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1} 
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
        attachmentCount = 1,
        pAttachments = &colorBlendAttachment,
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
        layout = idPipelineLayout, // This layout should include the UBO with ID
        renderPass = idRenderPass, // Your special render pass for ID picking
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create ID picking pipeline")
        os.exit(1)
    }

    return pipeline
}