package app 


import vk "vendor:vulkan"
import "core:fmt"


Pass :: struct {
    render_pass: vk.RenderPass,
    framebuffers: []vk.Framebuffer,
    pipeline: Pipeline,
}

init_pass :: proc(r: ^Renderer) {
    err: vk.Result
    t(.BEGIN, "renderPass"); 
    r.render_pass.render_pass = create_render_pass(r, {
        format = r.swapchain.format,
        use_depth = true,
        final_layout = .PRESENT_SRC_KHR,
    })
    t(.END, "renderPass"); 
    
    t(.BEGIN, "decsriptor layout"); 
    layout := create_main_descriptor_layout(r)
    add_descriptor_set_layout(r, PipelineType.Main, layout)
    t(.END, "decsriptor layout"); 

    t(.BEGIN, "mesh pipeline"); 
    collections: PipelineLayoutCollection
    collections, err = init_pipeline_layouts(r)
    main_layout := collections.layouts[.Main]
    r.render_pass.pipeline.handle= create_mesh_pipeline(r, main_layout)
    r.render_pass.pipeline.layout = main_layout
    t(.END, "mesh pipeline"); 

    t(.BEGIN, "cmd_pool"); 
    pool := create_command_pool(r)
    set_command_pool(r, pool)
    t(.END, "cmd_pool"); 

    t(.BEGIN, "resources"); 
    create_color_resource(r)
    create_depth_resource(r)
    t(.END, "resources"); 

    t(.BEGIN, "framebuffer")
    create_framebuffer(r)
    t(.END, "framebuffer")

    t(.BEGIN, "texture_image_and_sampler")
    create_texture_image(r,)
    create_texture_image_view(r)
    create_texture_sampler(r, 1)
    t(.END, "texture_image_and_sampler")

    uniformBuffers := create_uniform_buffers(r)
    create_command_buffers(r)

    pool_sizes := []vk.DescriptorPoolSize{
        {
            type = .UNIFORM_BUFFER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT * 2,
        },
        {
            type = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT,
        },
    }

    r.descriptor_pool.handle, err = create_descriptor_pool(r, pool_sizes, MAX_FRAMES_IN_FLIGHT)
    r.descriptor_sets = allocate_descriptor_sets(r, PipelineType.Main, MAX_FRAMES_IN_FLIGHT)
    create_sync_objects(r)

    t(.END, "init_pass")
  
}

create_render_pass :: proc(using r: ^Renderer, config: RenderPassConfig) -> (pass: vk.RenderPass) {

   attachments := [dynamic]vk.AttachmentDescription{}
    attachment_refs := [dynamic]vk.AttachmentReference{}

    colorAttachment := vk.AttachmentDescription{
        format = config.format,
        samples = {._1},
        loadOp = .CLEAR ,
        storeOp = .STORE ,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED ,
        finalLayout = config.final_layout
    }

    append(&attachments, colorAttachment)

    colorAttachmentRef := vk.AttachmentReference{
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL
    }

    depth_attachment_ref := vk.AttachmentReference{}
    depth_attachment_index := -1
    
    if config.use_depth {
        depth_attachment := vk.AttachmentDescription{
            format = find_depth_format(physicalDevice),
            samples = {._1},
            loadOp = .CLEAR,
            storeOp = .DONT_CARE,
            stencilLoadOp = .DONT_CARE,
            stencilStoreOp = .DONT_CARE,
            initialLayout = .UNDEFINED,
            finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        }
        append(&attachments, depth_attachment)
        depth_attachment_index = len(attachments) - 1
        depth_attachment_ref = vk.AttachmentReference{
            attachment = cast(u32)depth_attachment_index,
            layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        }
    }
    
    subpass := vk.SubpassDescription{
        pipelineBindPoint = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments = &colorAttachmentRef,
        pDepthStencilAttachment = config.use_depth ? &depth_attachment_ref : nil,
    }

    dependency := vk.SubpassDependency{
        srcSubpass = vk.SUBPASS_EXTERNAL,
        dstSubpass = 0,
        srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
        dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
    }

  
    render_pass_info := vk.RenderPassCreateInfo{
        sType = .RENDER_PASS_CREATE_INFO,
        attachmentCount = cast(u32)len(attachments),
        pAttachments = &attachments[0],
        subpassCount = 1,
        pSubpasses = &subpass,
        dependencyCount = 1,
        pDependencies = &dependency,
    }

    if vk.CreateRenderPass(device, &render_pass_info, nil, &pass) != .SUCCESS {
        fmt.eprintln("failed to create render pass")
    }

    return pass
}