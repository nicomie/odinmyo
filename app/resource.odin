package app

create_color_resource :: proc(using r: ^Renderer) {
    colorFormat := swapchain.format

    create_image(r, swapchain.extent.width, swapchain.extent.height, 1, {._1}, colorFormat,
    .OPTIMAL, {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT}, {.DEVICE_LOCAL}, &colorImage.image)

    colorImage.view = create_image_view(r, colorImage.image.texture, colorFormat, {.COLOR}, 1)
}

create_depth_resource ::proc(using r: ^Renderer) {
    depthFormat := find_depth_format(physicalDevice)
    create_image(r, swapchain.extent.width, swapchain.extent.height, 1, {._1}, depthFormat, 
    .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &depthImage.image)
    depthImage.view = create_image_view(r, depthImage.image.texture, depthFormat, {.DEPTH}, 1)
}