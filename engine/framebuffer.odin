package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createFramebuffer :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.sc
    swapchain.attachments.framebuffers = make([]vk.Framebuffer, len(swapchain.attachments.views))

    for i in 0..<len(swapchain.attachments.views) {
        attachments := []vk.ImageView{swapchain.attachments.views[i], depthImage.view }
 
        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = renderPass 
        framebufferInfo.attachmentCount = cast(u32)len(attachments)
        framebufferInfo.pAttachments = &attachments[0]
        framebufferInfo.width = swapchain.extent.width
        framebufferInfo.height = swapchain.extent.height
        framebufferInfo.layers = 1


        if vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapchain.attachments.framebuffers[i]) != .SUCCESS{
            fmt.eprintf("Failed to create fram buffer for index %d \n", i)
            os.exit(1)
        }
    }
}

createObjectIdFramebuffer :: proc (using ctx: ^Context) {
    using ctx.vulkan
    using ctx.sc
    attachments := []vk.ImageView{idImage.view, depthImage.view}

    framebufferInfo: vk.FramebufferCreateInfo
    framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
    framebufferInfo.renderPass = idRenderPass 
    framebufferInfo.attachmentCount = cast(u32)len(attachments)
    framebufferInfo.pAttachments = &attachments[0]
    framebufferInfo.width = swapchain.extent.width
    framebufferInfo.height = swapchain.extent.height
    framebufferInfo.layers = 1

    if vk.CreateFramebuffer(device, &framebufferInfo, nil, &idFramebuffer) != .SUCCESS{
        fmt.eprintf("Failed to create fram buffer for id %v \n", framebufferInfo)
        os.exit(1)
    }
}