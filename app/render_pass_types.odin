package app 

import vk "vendor:vulkan"

AttachmentConfig :: struct {
    format: vk.Format,
    samples: vk.SampleCountFlags,
    load_op: vk.AttachmentLoadOp,
    store_op: vk.AttachmentStoreOp,
    stencil_load_op: vk.AttachmentLoadOp,
    stencil_store_op: vk.AttachmentStoreOp,
    initial_layout: vk.ImageLayout,
    final_layout: vk.ImageLayout,
}

SubpassConfig :: struct {
    color_attachments: []u32, 
    depth_stencil_attachment: Maybe(u32),
}

RenderPassConfig :: struct  {
    format: vk.Format,
    depth_format: vk.Format,
    use_depth: bool,
    for_picking: bool,
    final_layout: vk.ImageLayout,
}