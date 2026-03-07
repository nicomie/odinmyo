package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

drawFrame :: proc(ctx: ^Context) {
    device := ctx.vulkan.device
    currentFrame := ctx.currentFrame
    swapchain := &ctx.sc.swapchain

    vk.WaitForFences(device, 1, &ctx.frames[currentFrame].inFlightFence, true, max(u64))

    imageIndex: u32    
    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), ctx.frames[currentFrame].imageAvailableSemaphore, {}, &imageIndex)
    if res == .ERROR_OUT_OF_DATE_KHR {
        recreateSwapchain(ctx)
        return
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        fmt.eprintln("failed to acquire swapchain image")
        os.exit(1)
    }
    if ctx.imagesInFlight[imageIndex] != {}  {
        vk.WaitForFences(device, 1, &ctx.imagesInFlight[imageIndex], true, max(u64))
    }
    vk.ResetFences(device, 1, &ctx.frames[currentFrame].inFlightFence)
    ctx.imagesInFlight[imageIndex] = ctx.frames[currentFrame].inFlightFence

    UpdateUI(ctx)
    
    vk.ResetCommandBuffer(ctx.frames[currentFrame].commandBuffer, {})
    updateUniformBuffer(ctx, currentFrame)
    _, buffer := recordCommandBuffer(ctx, ctx.frames[currentFrame].commandBuffer, imageIndex)
    _, _ =  recordUICommandBuffer(ctx, buffer, imageIndex)
 
    waitSemaphores := [?]vk.Semaphore{ctx.frames[currentFrame].imageAvailableSemaphore}
    waitStages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}


    if ctx.platform.clickPending {
    //    processClick(ctx)
    }

    submitInfo : vk.SubmitInfo 
    submitInfo.sType = .SUBMIT_INFO
    submitInfo.waitSemaphoreCount = 1
    submitInfo.pWaitSemaphores= &waitSemaphores[0] 
    submitInfo.pWaitDstStageMask = &waitStages[0]
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = &ctx.frames[currentFrame].commandBuffer

    signalSemaphores := [?]vk.Semaphore{ctx.renderFinishedSemaphores[imageIndex]}
    submitInfo.signalSemaphoreCount = 1
    submitInfo.pSignalSemaphores = &signalSemaphores[0]

    if vk.QueueSubmit(ctx.vulkan.graphicsQueue, 1, &submitInfo, ctx.frames[currentFrame].inFlightFence) != .SUCCESS {
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

    res = vk.QueuePresentKHR(ctx.vulkan.presentQueue, &presentInfo)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || ctx.framebufferResized{
        ctx.framebufferResized = false
        recreateSwapchain(ctx)
    } else if res != .SUCCESS {
        fmt.eprintln("failed to present swapchain image")
        os.exit(1)
    }

    ctx.currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT

}