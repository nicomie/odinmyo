package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

RenderPassConfig :: struct  {
    format: vk.Format,
    depth_format: vk.Format,
    use_depth: bool,
    for_picking: bool,
    final_layout: vk.ImageLayout,
}

createRenderPass :: proc(using ctx: ^Context, config: RenderPassConfig) -> vk.RenderPass{
    using ctx.vulkan
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
            format = findDepthFormat(physicalDevice),
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

    render_pass: vk.RenderPass
    if vk.CreateRenderPass(device, &render_pass_info, nil, &render_pass) != .SUCCESS {
        fmt.eprintln("failed to create render pass")
        os.exit(1)
    }

    return render_pass
}