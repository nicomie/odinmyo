package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createSyncObjects :: proc(using ctx: ^Context) {
    using ctx.vulkan
    semaphoreInfo: vk.SemaphoreCreateInfo
    semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

    fenceInfo: vk.FenceCreateInfo
    fenceInfo.sType = .FENCE_CREATE_INFO
    fenceInfo.flags = {.SIGNALED}

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        if vk.CreateSemaphore(device, &semaphoreInfo, nil, &ctx.frames[i].imageAvailableSemaphores) != .SUCCESS ||
        vk.CreateSemaphore(device, &semaphoreInfo, nil, &ctx.frames[i].renderFinishedSemaphores) != .SUCCESS ||
        vk.CreateFence(device, &fenceInfo, nil, &ctx.frames[i].inFlightFences) != .SUCCESS {
            fmt.eprintln("failed to create semaphores")
            os.exit(1)
        }
    }
  
}