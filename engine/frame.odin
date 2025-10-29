package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

drawFrame :: proc(using ctx: ^Context) {
    using ctx.platform
    using ctx.vulkan
    using ctx.sc
    vk.WaitForFences(device, 1, &ctx.frames[currentFrame].inFlightFences, true, max(u64))
    vk.ResetFences(device, 1, &ctx.frames[currentFrame].inFlightFences)

    imageIndex: u32
    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), ctx.frames[currentFrame].imageAvailableSemaphores, {}, &imageIndex)
    if res == .ERROR_OUT_OF_DATE_KHR {
        recreateSwapchain(ctx)
        return
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        fmt.eprintln("failed to acquire swapchain image")
        os.exit(1)
    }

    vk.ResetFences(device, 1, &ctx.frames[currentFrame].inFlightFences)

    vk.ResetCommandBuffer(ctx.frames[currentFrame].commandBuffers, {})
    updateUniformBuffer(ctx, currentFrame)
    _, buffer := recordCommandBuffer(ctx, ctx.frames[currentFrame].commandBuffers, imageIndex)
    _, _ =  recordUICommandBuffer(ctx, buffer, imageIndex)

    waitSemaphores := [?]vk.Semaphore{ctx.frames[currentFrame].imageAvailableSemaphores}
    waitStages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}


    if clickPending {
    //    processClick(ctx)
    }

    submitInfo : vk.SubmitInfo 
    submitInfo.sType = .SUBMIT_INFO
    submitInfo.waitSemaphoreCount = 1
    submitInfo.pWaitSemaphores= &waitSemaphores[0] 
    submitInfo.pWaitDstStageMask = &waitStages[0]
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = &ctx.frames[currentFrame].commandBuffers

    signalSemaphores := [?]vk.Semaphore{ctx.frames[currentFrame].renderFinishedSemaphores}
    submitInfo.signalSemaphoreCount = 1
    submitInfo.pSignalSemaphores = &signalSemaphores[0]

    if vk.QueueSubmit(graphicsQueue, 1, &submitInfo, ctx.frames[currentFrame].inFlightFences) != .SUCCESS {
        fmt.eprintln("failed to submit draw command buffer")
        os.exit(1)
    }

    presentInfo : vk.PresentInfoKHR
    presentInfo.sType = .PRESENT_INFO_KHR
    presentInfo.waitSemaphoreCount = 1
    presentInfo.pWaitSemaphores = &signalSemaphores[0]

    swapchains := [?]vk.SwapchainKHR{swapchain.handle}
    presentInfo.swapchainCount = 1
    presentInfo.pSwapchains = &swapchains[0]
    presentInfo.pImageIndices = &imageIndex 
    presentInfo.pResults = nil 

    res = vk.QueuePresentKHR(presentQueue, &presentInfo)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || framebufferResized{
        framebufferResized = false
        recreateSwapchain(ctx)
    } else if res != .SUCCESS {
        fmt.eprintln("failed to present swapchain image")
        os.exit(1)
    }

    currentFrame = (currentFrame + 1) & MAX_FRAMES_IN_FLIGHT

}