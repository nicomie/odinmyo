package app

import vk "vendor:vulkan"
import "core:os"
import "core:fmt"

DescriptorPool :: struct {
    handle: vk.DescriptorPool,
    max_sets: u32,
}

create_pool :: proc(
    r: ^Renderer,
    sizes: DescriptorPoolSizes,
    max_sets: u32,
) -> (pool: DescriptorPool, err: vk.Result) {
    
    pool_sizes := make([dynamic]vk.DescriptorPoolSize, 0, len(sizes))
    defer delete(pool_sizes)
    
    for type, count in sizes {
        append(&pool_sizes, vk.DescriptorPoolSize{
            type = auto_cast type,
            descriptorCount = count,
        })
    }

    create_info := vk.DescriptorPoolCreateInfo{
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets = max_sets,
        poolSizeCount = cast(u32)len(pool_sizes),
        pPoolSizes = raw_data(pool_sizes),
    }

    if vk.CreateDescriptorPool(r.device, &create_info, nil, &pool.handle) != .SUCCESS {
        return {}, .ERROR_OUT_OF_HOST_MEMORY
    }

    pool.max_sets = max_sets
    return pool, .SUCCESS
}

destroy_pool :: proc(r: ^Renderer, pool: ^DescriptorPool) {
    vk.DestroyDescriptorPool(r.device, pool.handle, nil)
    pool^ = {}
}

create_descriptor_pool :: proc(
    r: ^Renderer,
    sizes: []vk.DescriptorPoolSize,
    max_sets: u32,
) -> (pool: vk.DescriptorPool, err: vk.Result) {
    
    pool_info := vk.DescriptorPoolCreateInfo{
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        poolSizeCount = cast(u32)len(sizes),
        pPoolSizes = raw_data(sizes),
        maxSets = max_sets,
    }

    if vk.CreateDescriptorPool(r.device, &pool_info, nil, &pool) != .SUCCESS {
        return 0, .ERROR_INITIALIZATION_FAILED
    }

    return pool, .SUCCESS
}

create_command_pool :: proc(r: ^Renderer) -> vk.CommandPool {
    poolInfo : vk.CommandPoolCreateInfo
    poolInfo.sType = .COMMAND_POOL_CREATE_INFO 
    poolInfo.flags = {.RESET_COMMAND_BUFFER}
    poolInfo.queueFamilyIndex = u32(r.queueIndices[.Graphics])

    pool: vk.CommandPool
    if vk.CreateCommandPool(r.device, &poolInfo, nil, &pool) != .SUCCESS {
        fmt.eprintln("failed to create command pool")
        os.exit(1)
    }

    return pool
}