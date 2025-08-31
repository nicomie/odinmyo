package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createFramebuffer :: proc(using ctx: ^Context) {
    using ctx.vulkan
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.imageViews))

    for i in 0..<len(swapchain.imageViews) {
        attachments := []vk.ImageView{swapchain.imageViews[i], depthImage.view }
 
        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = renderPass 
        framebufferInfo.attachmentCount = cast(u32)len(attachments)
        framebufferInfo.pAttachments = &attachments[0]
        framebufferInfo.width = swapchain.extent.width
        framebufferInfo.height = swapchain.extent.height
        framebufferInfo.layers = 1


        if vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapchain.framebuffers[i]) != .SUCCESS{
            fmt.eprintf("Failed to create fram buffer for index %d \n", i)
            os.exit(1)
        }
    }
}

createObjectIdFramebuffer :: proc (using ctx: ^Context) {
    using ctx.vulkan
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