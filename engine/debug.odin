package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "base:runtime"

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};
USE_VALIDATION_LAYERS :: ODIN_DEBUG

debugCallback :: proc "cdecl" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr
) -> b32 {
    context = runtime.default_context()
    fmt.printf("Vulkan Validation Layer Message: %s\n", string(pCallbackData.pMessage))
    return false 
}

CreateDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    pCreateInfo: ^vk.DebugUtilsMessengerCreateInfoEXT,
    pAllocator: ^vk.AllocationCallbacks,
    pDebugMessenger: ^vk.DebugUtilsMessengerEXT
) -> vk.Result {
    // Retrieve the function pointer for vkCreateDebugUtilsMessengerEXT
    func := cast(vk.ProcCreateDebugUtilsMessengerEXT)(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"))
    
    if func != nil {
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger)
    } else {
        return .ERROR_EXTENSION_NOT_PRESENT
    }
}

DestroyDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    pAllocator: ^vk.AllocationCallbacks
){
    func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)(vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"))
    
    if func != nil {
        func(instance, debugMessenger, pAllocator)
    } else {
            fmt.println("destroy not found?")

    }
}

checkVk :: proc(result: vk.Result, location := #caller_location) {
    if result != .SUCCESS {
        fmt.eprintf("Vulkan error at %s: %v\n", location, result)
        os.exit(1)
    }
}

populate_debug_messenger :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT){
    info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    info.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
    info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
    info.pfnUserCallback = debugCallback
}

setup_debug_messenger :: proc(using ctx: ^Context) {
    when ODIN_DEBUG {
        createInfo: vk.DebugUtilsMessengerCreateInfoEXT
        populate_debug_messenger(&createInfo)

        if CreateDebugUtilsMessengerEXT(instance, &createInfo, nil, &debugMessenger) != .SUCCESS {
            fmt.println("Failed to create debug utils messenger")
            return
        }
    }

}