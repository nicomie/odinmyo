package app

import vk "vendor:vulkan"

DescriptorType :: enum {
    UniformBuffer,
    CombinedImageSampler,
    StorageBuffer,
}

DescriptorBinding :: struct {
    binding: u32,
    type: DescriptorType,
    count: u32,
    stage_flags: vk.ShaderStageFlags,
}

DescriptorSetLayoutConfig :: struct {
    bindings: []DescriptorBinding,
}

DescriptorPoolSizes :: map[DescriptorType]u32