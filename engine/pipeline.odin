package engine

import "core:math/linalg"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "base:runtime"

createPipelineLayouts :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) {

    pipe := pipelineContext

    pRanges := vk.PushConstantRange{
        stageFlags = {.VERTEX},
        offset = 0,
        size = size_of(Mat4),
    }

    meshLayouts := [2]vk.DescriptorSetLayout{
        ctx.globalDescriptorSetLayouts["global"],   
        pipe.descriptorSetLayouts["material"]
    }

    pipelineLayoutInfo := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = cast(u32)len(meshLayouts),
        pSetLayouts = &meshLayouts[0],
        pushConstantRangeCount = 1,
        pPushConstantRanges = &pRanges
    }

    if vk.CreatePipelineLayout(ctx.vulkan.device, &pipelineLayoutInfo, nil, &pipe.meshPipelineLayout) != .SUCCESS {
        fmt.eprintln("failed to create pipeline layout")
        os.exit(1)
    }


}

createGlobalPipelineLayouts :: proc(ctx: ^Context) {

    uiPushRange := vk.PushConstantRange{
        stageFlags = {.VERTEX, .FRAGMENT},
        offset = 0,
        size = size_of(Vec2),  
    }

     uiPipelineLayoutInfo := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &ctx.globalDescriptorSetLayouts["ui"],  
        pushConstantRangeCount = 1,
        pPushConstantRanges = &uiPushRange,
    }

    if vk.CreatePipelineLayout(ctx.vulkan.device, &uiPipelineLayoutInfo, nil, &ctx.pipe.uiPipelineLayout) != .SUCCESS {
        fmt.eprintln("failed to create pipeline layout (ui)")
        os.exit(1)
    }
}

createPipelines :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) {
    meshPipeline := createMeshPipeline(ctx, pipelineContext)
    uiPipeline := createUiPipeline(ctx, pipelineContext)
    ctx.pipe.pipelines["ui"] = uiPipeline
    pipelineContext.pipelines = make(map[string]vk.Pipeline)
    pipelineContext.pipelines["mesh"] = meshPipeline

}

createMeshPipeline :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) -> vk.Pipeline {
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

    vertShaderCode, _:= os.read_entire_file_from_path(vertPath, allocator)
    fragShaderCode, _:= os.read_entire_file_from_path(fragPath, allocator)

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
        layout = pipelineContext.meshPipelineLayout,
        renderPass = ctx.sc.renderPass,
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create mesh pipeline")
        os.exit(1)
    }

    return pipeline
}

createUiPipeline :: proc(ctx: ^Context, pipelineContext: ^PipelineContext) -> vk.Pipeline {
    device := ctx.vulkan.device
    swapchain := ctx.sc.swapchain

    allocator := runtime.heap_allocator()
    vertPath, errx := os.join_path({ "shaders", "ui.vert.spv"}, allocator)
    fragPath, erry := os.join_path({"shaders", "ui.frag.spv"}, allocator)
   
    if errx != nil do fmt.println(errx)
    if erry != nil do fmt.println(erry)

    fmt.println(vertPath)
    fmt.println(fragPath)

    vertShaderCode, _:= os.read_entire_file_from_path(vertPath, allocator)
    fragShaderCode, _:= os.read_entire_file_from_path(fragPath, allocator)
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

    // Vertex input – replace VERTEX_BINDING / VERTEX_ATTRIBUTES with your UI vertex format
    vertexInput := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = &UI_VERTEX_BINDING, // <- define UI binding
        vertexAttributeDescriptionCount = cast(u32)len(UI_VERTEX_ATTRIBUTES),
        pVertexAttributeDescriptions = &UI_VERTEX_ATTRIBUTES[0], // <- define UI attributes (pos, uv, color)
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
        cullMode = nil, // no culling for UI
        frontFace = .COUNTER_CLOCKWISE,
        depthBiasEnable = false,
    }

    multisampling := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1},
    }

    // Disable depth test/write for UI
    depthStencil := vk.PipelineDepthStencilStateCreateInfo{
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = false,
        depthWriteEnable = false,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable = false,
    }

    // Enable alpha blending for UI
    colorBlendAttachment := vk.PipelineColorBlendAttachmentState{
        colorWriteMask = {.R, .G, .B, .A},
        blendEnable = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp = .ADD,
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
        layout = ctx.pipe.uiPipelineLayout,  
        renderPass = ctx.sc.renderPass,   
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create UI pipeline")
        os.exit(1)
    }

    return pipeline
}