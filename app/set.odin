package app

import vk "vendor:vulkan"

import "core:fmt"
import "core:os"


DescriptorSetLayout :: struct {
    binding: u32,
    type: vk.DescriptorType,
    shaderStageFlags: vk.ShaderStageFlags
}

allocate_descriptor_sets :: proc(
    r: ^Renderer,
    pipeline_type: PipelineType,
    $N: u32,
) -> [N]vk.DescriptorSet {
    layout := r.descriptor_set_layouts[pipeline_type]
    sets, err := allocate_sets(r, &r.descriptor_pool, layout, N)
    return sets
}

allocate_sets :: proc(
    r: ^Renderer,
    pool: ^DescriptorPool,
    layout: vk.DescriptorSetLayout,
    $N: u32,
) -> (sets: [N]vk.DescriptorSet, err: vk.Result) {
    
    if pool.handle == 0 {
        fmt.eprintln("descriptor pool is not initialized %v", pool)
    } 
   
    layouts : [N]vk.DescriptorSetLayout
    for i in 0..<N {
        layouts[i] = layout
    }

    allocate_info := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = pool.handle,
        descriptorSetCount = N,
        pSetLayouts = &layouts[0],
    }

    if vk.AllocateDescriptorSets(r.device, &allocate_info, &sets[0]) != .SUCCESS {
        return {}, .ERROR_OUT_OF_HOST_MEMORY
    }

    return sets, .SUCCESS
}

update_buffer_descriptor :: proc(
    r: ^Renderer,
    set: vk.DescriptorSet,
    binding: u32,
    buffer: vk.Buffer,
    offset: vk.DeviceSize,
    range: vk.DeviceSize,
    type: DescriptorType,
) {
    buffer_info := vk.DescriptorBufferInfo{
        buffer = buffer,
        offset = offset,
        range = range,
    }

    write := vk.WriteDescriptorSet{
        sType = .WRITE_DESCRIPTOR_SET,
        dstSet = set,
        dstBinding = binding,
        dstArrayElement = 0,
        descriptorCount = 1,
        descriptorType = auto_cast type,
        pBufferInfo = &buffer_info,
    }

    vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
}

update_image_descriptor :: proc(
    r: ^Renderer,
    set: vk.DescriptorSet,
    binding: u32,
    image_view: vk.ImageView,
    sampler: vk.Sampler,
    layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) {
    image_info := vk.DescriptorImageInfo{
        sampler = sampler,
        imageView = image_view,
        imageLayout = layout,
    }

    write := vk.WriteDescriptorSet{
        sType = .WRITE_DESCRIPTOR_SET,
        dstSet = set,
        dstBinding = binding,
        dstArrayElement = 0,
        descriptorCount = 1,
        descriptorType = .COMBINED_IMAGE_SAMPLER,
        pImageInfo = &image_info,
    }

    vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)
}

create_descriptor_set_layout :: proc(device: vk.Device, descriptorSets: []DescriptorSetLayout) -> vk.DescriptorSetLayout{

    bindings := make([]vk.DescriptorSetLayoutBinding, len(descriptorSets))
    for set, i in descriptorSets {
        bindings[i] = vk.DescriptorSetLayoutBinding{
            binding = set.binding,
            descriptorCount = 1,
            descriptorType = set.type,
            stageFlags = set.shaderStageFlags,
            pImmutableSamplers = nil,
        }
    }
         
    layoutInfo := vk.DescriptorSetLayoutCreateInfo{
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = cast(u32)len(bindings),
        pBindings = &bindings[0]
    }
    
    layout: vk.DescriptorSetLayout
    if vk.CreateDescriptorSetLayout(device, &layoutInfo, nil, &layout) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorSetLayout")
        os.exit(1)
    }

    return layout
}
