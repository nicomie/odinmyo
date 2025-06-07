package app

import vk "vendor:vulkan"
import "core:os"
import "core:fmt"

create_shader_module :: proc(data: []u8, device: vk.Device) -> vk.ShaderModule {
    createInfo : vk.ShaderModuleCreateInfo
    createInfo.sType = .SHADER_MODULE_CREATE_INFO
    createInfo.codeSize = len(data)
    createInfo.pCode = cast(^u32)raw_data(data)

    shaderModule : vk.ShaderModule
    if vk.CreateShaderModule(device, &createInfo, nil, &shaderModule) != .SUCCESS {
        fmt.println("failed to create shader module")
        os.exit(1) 
    }

    return shaderModule
}