package app

import vk "vendor:vulkan"

create_main_descriptor_layout :: proc(r: ^Renderer) -> vk.DescriptorSetLayout {
    config := DescriptorSetLayoutConfig{
        bindings = {
            { 
                binding = 0,
                type = .UniformBuffer,
                count = 1,
                stage_flags = {.VERTEX, .FRAGMENT},
            },
            { 
                binding = 1,
                type = .CombinedImageSampler,
                count = 1,
                stage_flags = {.FRAGMENT},
            },
        },
    }
    layout, _ := create_layout(r, &config)
    return layout
}

create_layout :: proc(
    r: ^Renderer,
    config: ^DescriptorSetLayoutConfig,
) -> (layout: vk.DescriptorSetLayout, err: vk.Result) {
    
    bindings := make([]vk.DescriptorSetLayoutBinding, len(config.bindings))
    for b, i in config.bindings {
        bindings[i] = vk.DescriptorSetLayoutBinding{
            binding = b.binding,
            descriptorType = auto_cast b.type,
            descriptorCount = b.count,
            stageFlags = b.stage_flags,
        }
    }

    create_info := vk.DescriptorSetLayoutCreateInfo{
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = cast(u32)len(bindings),
        pBindings = raw_data(bindings),
    }

    if vk.CreateDescriptorSetLayout(r.device, &create_info, nil, &layout) != .SUCCESS {
        return {}, .ERROR_OUT_OF_HOST_MEMORY
    }


    return layout, .SUCCESS
}

destroy_layout :: proc(r: ^Renderer, layout: vk.DescriptorSetLayout) {
    vk.DestroyDescriptorSetLayout(r.device, layout, nil)
}