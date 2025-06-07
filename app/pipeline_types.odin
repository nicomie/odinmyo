package app 

import vk "vendor:vulkan"

PipelineLayoutConfig :: struct {
    descriptor_layout: vk.DescriptorSetLayout,
    // push_constant_ranges: []vk.PushConstantRange,
    label: string, 
}

PipelineType :: enum {
    Main,
    ID,
    Shadow,
    PostProcess,
    Custom
}

PipelineLayoutCollection :: struct {
    layouts: [PipelineType]vk.PipelineLayout,
}