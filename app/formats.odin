package app

import vk "vendor:vulkan"
import "core:os"
import "core:fmt"


find_depth_format :: proc(physicalDevice: vk.PhysicalDevice) -> vk.Format {
    candidates := []vk.Format{
        .D32_SFLOAT,
        .D32_SFLOAT_S8_UINT, 
        .D24_UNORM_S8_UINT,
    }
    return find_supported_format(
        physicalDevice,
        candidates,
        .OPTIMAL,
        {.DEPTH_STENCIL_ATTACHMENT}
    )
}

find_supported_format :: proc(physicalDevice: vk.PhysicalDevice, candidates: []vk.Format, 
    tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format{

        for &format in candidates {
            props: vk.FormatProperties
            vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &props)

            if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
                return format
            } else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
                return format
            }
        }
       
        fmt.eprintln("failed to find supported format")
        return vk.Format{}
}