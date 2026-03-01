package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createFramebuffer :: proc(ctx: ^Context) {
    ctx.sc.swapchain.attachments.framebuffers = make([]vk.Framebuffer, len(ctx.sc.swapchain.attachments.views))

    for i in 0..<len(ctx.sc.swapchain.attachments.views) {
        attachments := []vk.ImageView{ctx.sc.swapchain.attachments.views[i], ctx.sc.depthImage.view }
 
        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = ctx.sc.renderPass 
        framebufferInfo.attachmentCount = cast(u32)len(attachments)
        framebufferInfo.pAttachments = &attachments[0]
        framebufferInfo.width = ctx.sc.swapchain.extent.width
        framebufferInfo.height = ctx.sc.swapchain.extent.height
        framebufferInfo.layers = 1


        if vk.CreateFramebuffer(ctx.vulkan.device, &framebufferInfo, nil, &ctx.sc.swapchain.attachments.framebuffers[i]) != .SUCCESS{
            fmt.eprintf("Failed to create fram buffer for index %d \n", i)
            os.exit(1)
        }
    }
}
