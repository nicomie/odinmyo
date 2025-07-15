package engine

import "core:fmt"
import "core:c"
import "core:os"
import "base:runtime"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:mem"
import "core:time"
import "core:strings"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "core:encoding/endian"
import "core:c/libc"
import "vendor:stb/image"
import "vendor:cgltf"
import cr "../engine/core"


MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct {
    pipelines: map[string]vk.Pipeline, 

    uri: cstring,
    timeContext: ^cr.TimeContext,
    window: ^sdl.Window,
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    physicalDevice: vk.PhysicalDevice,
    device: vk.Device,
    queueIndices: [QueueFamily]int,
    graphicsQueue: vk.Queue,
    surface: vk.SurfaceKHR,
    presentQueue: vk.Queue,
    swapchain: Swapchain,
    renderPass: vk.RenderPass,
    meshPipelineLayout: vk.PipelineLayout,
    commandPool: vk.CommandPool,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    idCommandBuffer: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlightFences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    currentFrame :u32,
    framebufferResized :bool,

    uniformBuffers: []Buffer,
    uniformBuffersMapped: []rawptr,
   
    descriptorPool: vk.DescriptorPool,
    descriptorSetLayouts: map[string]vk.DescriptorSetLayout,
    idDescriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
    descriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

    mipLevels: u32,
    texture: Image,
    textureImageView: vk.ImageView,
    textureSampler: vk.Sampler,

    depthImage: DepthImage,
    colorImage: DepthImage,
   
    msaa: vk.SampleCountFlags,
    camera: Camera,
    ray: Ray,
    meshes: [dynamic]MeshObject,

    idStagingBuffer: Buffer,
    idStagingBufferMemory: vk.DeviceMemory,
    idPipelineLayout: vk.PipelineLayout,
    idImage: DepthImage,
    idRenderPass: vk.RenderPass,
    toggleHover: bool,
    idFramebuffer: vk.Framebuffer,

    clickPending: bool,
    clickX, clickY: i32,
    clickyXDelta, clickyYDelta: i32,
}


Ray :: struct {
    origin: linalg.Vector4f32,
    direction: linalg.Vector4f32,
 
}

Vertex :: struct{
    pos: [3]f32,
    color: [3]f32,
    texCoord: [2]f32,
}

initVulkan :: proc(using ctx: ^Context) {
    getInstanceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
    assert(getInstanceProcAddr != nil)
    vk.load_proc_addresses(getInstanceProcAddr)
    create_instance(ctx)

    vk.load_proc_addresses(instance)
    setup_debug_messenger(ctx)
        
    fmt.println("Available extensions")
    extensions := get_extensions();
    for _, i in extensions do fmt.println(cstring(&extensions[i].extensionName[0]))

    createSurface(ctx)
    pickPhysicalDevice(ctx)
    createLogicalDevice(ctx)
    createSwapchain(ctx)
    createImageViews(ctx)

    findQueueFamilies(ctx)

    renderPass = createRenderPass(ctx, {
        format = swapchain.format,
        use_depth = true,
        final_layout = .PRESENT_SRC_KHR,
    })

    idRenderPass = createRenderPass(ctx, {
        format = .R8G8B8A8_UNORM,
        use_depth = true,
        final_layout = .TRANSFER_SRC_OPTIMAL,
    })

    createDescriptorSetLayouts(ctx)
    createPipelineLayouts(ctx)
    createCommandPool(ctx)

    createPipelines(ctx)
    setupGlb(ctx)

    createColorResources(ctx)
    createDepthResource(ctx)
    createIdResource(ctx)

    createFramebuffer(ctx)
    createObjectIdFramebuffer(ctx)

    createTextureImage(ctx)
    createTextureImageView(ctx)
    createTextureSampler(ctx)


    createUniformBuffers(ctx)
    
    // Add this after creating ID resources but before command buffers
    imageSize := cast(vk.DeviceSize)(swapchain.extent.width * swapchain.extent.height * 4)
    createBuffer(
        ctx,
        imageSize, // RGBA8
        {.TRANSFER_DST},
        {.HOST_VISIBLE, .HOST_COHERENT},
        &idStagingBuffer
    )
    createCommandBuffers(ctx)
    createDescriptorPool(ctx)
    createDescriptorSets(ctx)
    createIdDescriptorSets(ctx)
    createSyncObjects(ctx)

}

exit :: proc(using ctx: ^Context) {
    cleanSwapchain(ctx)

    vk.DestroyBuffer(device, idStagingBuffer.buffer, nil)
    vk.FreeMemory(device, idStagingBuffer.memory, nil)
    
    vk.DestroyImageView(device, idImage.view, nil)
    vk.DestroyImage(device, idImage.image.texture, nil)
    vk.FreeMemory(device, idImage.image.memory, nil)
    
    vk.DestroyFramebuffer(device, idFramebuffer, nil)

    vk.DestroySampler(device, textureSampler, nil)
    
    vk.DestroyImageView(device, textureImageView, nil)
    vk.DestroyImage(device, texture.texture, nil)
    vk.FreeMemory(device, texture.memory, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.DestroyBuffer(device, uniformBuffers[i].buffer, nil)
        vk.FreeMemory(device,  uniformBuffers[i].memory, nil)
    }

    vk.DestroyDescriptorPool(device, descriptorPool, nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["mesh"], nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["id"], nil)
    delete(descriptorSetLayouts)
    
    for mesh in meshes {
        vk.DestroyBuffer(device, mesh.vertexBuffer.buffer, nil)
        vk.FreeMemory(device,  mesh.vertexBuffer.memory, nil)
        vk.DestroyBuffer(device, mesh.indexBuffer.buffer, nil)
        vk.FreeMemory(device,  mesh.indexBuffer.memory, nil)
    }

    for _, pipeline in pipelines {
        vk.DestroyPipeline(device, pipeline, nil)
    }
    delete(pipelines)

    vk.DestroyPipelineLayout(device, meshPipelineLayout, nil)
    vk.DestroyPipelineLayout(device, idPipelineLayout, nil)

    vk.DestroyRenderPass(device, renderPass, nil)
    vk.DestroyRenderPass(device, idRenderPass, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.DestroySemaphore(device, imageAvailableSemaphores[i], nil);
        vk.DestroySemaphore(device, renderFinishedSemaphores[i], nil);
        vk.DestroyFence(device, inFlightFences[i], nil);
    }
   
    vk.DestroyCommandPool(device, commandPool, nil)   
    vk.DestroyDevice(device, nil)
    when ODIN_DEBUG {
       DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
    }
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)
    sdl.DestroyWindow(window)
    sdl.Quit()
}

mouseAction:: proc(using ctx: ^Context, mouseX, mouseY: i32) {
    ctx.clickPending = true
    ctx.clickX = mouseX
    ctx.clickY = mouseY
    ctx.clickyXDelta = 0
    ctx.clickyYDelta = 0
}


mouseRealease :: proc(using ctx: ^Context) {
    ctx.clickPending = false
    ctx.clickyXDelta = 0
    ctx.clickyYDelta = 0
}

run :: proc(using ctx: ^Context) {

    loop: for {
        target_frame_time := 1.0 / 240.0
        frame_start := time.now()
        cr.update(timeContext)

        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .KEYDOWN, .KEYUP:
                    key_state := sdl.GetKeyboardState(nil)
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE:
                            break loop
                    }
                case .MOUSEBUTTONDOWN:
                    if event.button.button == sdl.BUTTON_MIDDLE { 
                        mouseAction(ctx, event.button.x, event.button.y)
                        fmt.printf("Middle mouse button at (%d, %d)\n", event.button.x, event.button.y)

                    }
                case .MOUSEBUTTONUP:
                    if event.button.button == sdl.BUTTON_MIDDLE {
                        fmt.printf("Middle mouse button released at (%d, %d)\n", event.button.x, event.button.y)
                        mouseRealease(ctx)
                    }
                case .QUIT:
                    break loop
            }      
            if ctx.clickPending {
                mx, my : i32
                sdl.GetMouseState(&mx, &my)
                ctx.clickyXDelta = mx - ctx.clickX
                ctx.clickyYDelta = my - ctx.clickY
                ctx.clickX = mx
                ctx.clickY = my
                //fmt.printf("Mouse held at (%d, %d)\n", mx, my)

                sensitivity: f32 = 0.005
                camera.yaw   -= f32(ctx.clickyXDelta) * sensitivity
                camera.pitch -= f32(ctx.clickyYDelta) * sensitivity

                max_pitch := math.PI/2 - 0.05
                min_pitch := -math.PI/2 + 0.05
                camera.pitch = math.clamp(camera.pitch, f32(min_pitch), f32(max_pitch))

                camera.distance = math.max(camera.distance, 0.1)

                x := camera.target.x + camera.distance * math.cos(camera.pitch) * math.sin(camera.yaw)
                y := camera.target.y + camera.distance * math.sin(camera.pitch)
                z := camera.target.z + camera.distance * math.cos(camera.pitch) * math.cos(camera.yaw)
                camera.position = linalg.Vector4f32{x, y, z, 1}
            }      
        }
        key_state := sdl.GetKeyboardState(nil)
        move_speed :: 5.0
        if key_state[sdl.SCANCODE_UP] != 0 do camera.position.y -= move_speed * ctx.timeContext.deltaTime
        if key_state[sdl.SCANCODE_DOWN] != 0 do camera.position.y += move_speed * ctx.timeContext.deltaTime
        if key_state[sdl.SCANCODE_LEFT] != 0 do camera.position.x -= move_speed * ctx.timeContext.deltaTime
        if key_state[sdl.SCANCODE_RIGHT] != 0 do camera.position.x += move_speed * ctx.timeContext.deltaTime
        
  
        drawFrame(ctx)
    
        frame_time := time.duration_seconds(time.diff(frame_start, time.now()))
        sleep_time := target_frame_time - frame_time
        if sleep_time > 0 {
            time.sleep(time.Duration(sleep_time * 1e9))  // Nanoseconds
        }
    }
    vk.DeviceWaitIdle(device)
}

main :: proc() {
    using ctx: Context
    timeContext = cr.init(); defer cr.end(timeContext)
    initWindow(&ctx)
    initContext(&ctx)
    initVulkan(&ctx)
    initCamera(&ctx)
    run(&ctx)  
    exit(&ctx)
}

initContext :: proc(using ctx: ^Context) {
   for &q in queueIndices do q = -1
}