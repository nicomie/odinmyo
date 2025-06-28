package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"


createCommandPool :: proc(using ctx: ^Context) {
    poolInfo : vk.CommandPoolCreateInfo
    poolInfo.sType = .COMMAND_POOL_CREATE_INFO 
    poolInfo.flags = {.RESET_COMMAND_BUFFER}
    poolInfo.queueFamilyIndex = u32(queueIndices[.Graphics])

    if vk.CreateCommandPool(device, &poolInfo, nil, &commandPool) != .SUCCESS {
        fmt.eprintln("failed to create command pool")
        os.exit(1)
    }
}