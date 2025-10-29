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

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

Texture :: struct {
    handle: Image,
    view: vk.ImageView,
    sampler: vk.Sampler,
    mips: u32,
    uri: cstring,
}

UIContext :: struct {
    elements: [dynamic]UI,
    uiDescriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
}

PlatformContext :: struct {
    window: ^sdl.Window,
    timeContext: ^cr.TimeContext,
    clickPending: bool,
    clickX, clickY: i32,
    clickyXDelta, clickyYDelta: i32,
}

VulkanContext :: struct {
    instance: vk.Instance,
    device: vk.Device,
    physicalDevice: vk.PhysicalDevice,
    queueIndices: [QueueFamily]int,
    graphicsQueue: vk.Queue,
    surface: vk.SurfaceKHR,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    presentQueue: vk.Queue,
    commandPool: vk.CommandPool,
}

SwapchainContext :: struct {
    swapchain: Swapchain,
    renderPass: vk.RenderPass,
    depthImage: DepthImage,
    colorImage: DepthImage,
    msaa: vk.SampleCountFlags,
}

FrameContext :: struct {
    commandBuffers: vk.CommandBuffer,
    idCommandBuffer: vk.CommandBuffer,

    imageAvailableSemaphores: vk.Semaphore,
    renderFinishedSemaphores: vk.Semaphore,
    inFlightFences: vk.Fence,
}

PipelineContext :: struct {
    pipelines: map[string]vk.Pipeline, 
    meshPipelineLayout: vk.PipelineLayout,
    uiPipelineLayout: vk.PipelineLayout,
    descriptorPool: vk.DescriptorPool,
    descriptorSetLayouts: map[string]vk.DescriptorSetLayout,
    descriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
}

IdPipelineContext :: struct {
    idStagingBuffer: Buffer,
    idStagingBufferMemory: vk.DeviceMemory,
    idPipelineLayout: vk.PipelineLayout,
    idDescriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
    idImage: DepthImage,
    idRenderPass: vk.RenderPass,
    idFramebuffer: vk.Framebuffer,
    
}

ResourceContext :: struct {
    uniformBuffers: []Buffer,
    uniformBuffersMapped: []rawptr,
    textures: []^Texture,
    meshes: [dynamic]MeshObject,
}

SceneContext :: struct {
    camera: Camera,
    ray: Ray,
    toggleHover: bool,
    isPlayer: bool,
}

Context :: struct {
    platform: PlatformContext,
    vulkan: VulkanContext,
    sc: SwapchainContext,
    pipe: PipelineContext,
    resource: ResourceContext,
    id: IdPipelineContext,
    scene: SceneContext,
    ui: UIContext,

    frames: [MAX_FRAMES_IN_FLIGHT]FrameContext,
    currentFrame :u32,
    framebufferResized :bool,  
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
    using ctx.vulkan
    using ctx.sc
    using ctx.id
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
        final_layout = .PRESENT_SRC_KHR,
    })

    createDescriptorSetLayouts(ctx)
    createPipelineLayouts(ctx)
    createCommandPool(ctx)

    createPipelines(ctx)
    setupGlb(ctx, "glbs/SciFiHelmet/glTF/SciFiHelmet.gltf")

    createColorResources(ctx)
    createDepthResource(ctx)
    createIdResource(ctx)

    createFramebuffer(ctx)
    createObjectIdFramebuffer(ctx)

    createUniformBuffers(ctx)
    
    // Add this after creating ID resources but before command buffers
    imageSize := cast(vk.DeviceSize)(swapchain.extent.width * swapchain.extent.height * 4)
    createBuffer(
        ctx,
        imageSize, // RGBA8
        {.TRANSFER_DST},
        {.HOST_VISIBLE, .HOST_COHERENT},
        &idStagingBuffer,
        "idStaging"
    )
    createCommandBuffers(ctx)
    createDescriptorPool(ctx)
    createDescriptorSets(ctx)
    createUiDescriptorSets(ctx)
    //createIdDescriptorSets(ctx)
    createSyncObjects(ctx)

}

exit :: proc(using ctx: ^Context) {
    using ctx.platform
    using ctx.vulkan
    using ctx.sc
    using ctx.pipe
    using ctx.resource
    using ctx.id
    vk.DeviceWaitIdle(device)

    cleanSwapchain(ctx)

    // --- Staging ---
    destroyBuffer("idStaging", device, idStagingBuffer)

    // --- Images / textures ---
    vk.DestroyImageView(device, idImage.view, nil)
    vk.DestroyImage(device, idImage.image.texture, nil)
    vk.FreeMemory(device, idImage.image.memory, nil)

    for texture in textures {
        vk.DestroySampler(device, texture^.sampler, nil)
        vk.DestroyImageView(device, texture^.view, nil)
        vk.DestroyImage(device, texture^.handle.texture, nil)
        vk.FreeMemory(device, texture^.handle.memory, nil)
    }
   
    // --- Framebuffers ---
    vk.DestroyFramebuffer(device, idFramebuffer, nil)

    // --- Buffers ---
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        destroyBuffer(fmt.tprintf("ubo%d", i), device, uniformBuffers[i])
    }

    // for mesh in meshes {
    destroyBuffer("vBuffer", device, meshes[0].vertexBuffer^)
    destroyBuffer("iBuffer", device, meshes[0].indexBuffer^)
    

    for el in ui.elements {
        destroyBuffer("meshVertex", device, el.vertex^)
        destroyBuffer("meshIndex", device, el.indices^)
    }

    // --- Descriptor cleanup ---
    vk.DestroyDescriptorPool(device, descriptorPool, nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["mesh"], nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["id"], nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["ui"], nil)
    delete(descriptorSetLayouts)

    // --- Pipelines ---
    for _, pipeline in pipelines {
        vk.DestroyPipeline(device, pipeline, nil)
    }
    delete(pipelines)

    vk.DestroyPipelineLayout(device, meshPipelineLayout, nil)
    vk.DestroyPipelineLayout(device, idPipelineLayout, nil)
    vk.DestroyPipelineLayout(device, uiPipelineLayout, nil)

    // --- Render passes ---
    vk.DestroyRenderPass(device, renderPass, nil)
    vk.DestroyRenderPass(device, idRenderPass, nil)

    // --- Sync ---
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.DestroySemaphore(device, ctx.frames[i].imageAvailableSemaphores, nil)
        vk.DestroySemaphore(device, ctx.frames[i].renderFinishedSemaphores, nil)
        vk.DestroyFence(device, ctx.frames[i].inFlightFences, nil)
    }

    // --- Command pool ---
    vk.DestroyCommandPool(device, commandPool, nil)

    // --- Device and Instance ---
    vk.DestroyDevice(device, nil)
    when ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
    }
    vk.DestroySurfaceKHR(instance, surface, nil)
    vk.DestroyInstance(instance, nil)

    // --- SDL ---
    sdl.DestroyWindow(window)
    sdl.Quit()
}


run :: proc(using ctx: ^Context) {
    using ctx.platform
    using ctx.vulkan
    using ctx.scene
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
                        case .SPACE:
                            isPlayer = !isPlayer
                    }
                case .MOUSEBUTTONDOWN:
                    if event.button.button == sdl.BUTTON_MIDDLE { 
                        clickPending = true
                        clickX = event.button.x
                        clickY = event.button.y
                        fmt.printf("Middle mouse button at (%d, %d)\n", event.button.x, event.button.y)

                    }
                case .MOUSEBUTTONUP:
                    if event.button.button == sdl.BUTTON_MIDDLE {
                        clickPending = false
                        fmt.printf("Middle mouse button released at (%d, %d)\n", event.button.x, event.button.y)

                    }
                case .MOUSEMOTION:
                    if clickPending {
                        deltaX := f32(event.motion.xrel)
                        deltaY := f32(event.motion.yrel)

                        sensitivity := f32(0.005)
                        camera.yaw -= deltaX * sensitivity
                        camera.pitch -= deltaY * sensitivity

                        camera.yaw = math.mod(camera.yaw, math.TAU)
                        camera.pitch = math.mod(camera.pitch, math.TAU)
                    }
                case .MOUSEWHEEL:
                       zoom_speed := f32(0.5)
                        camera.distance -= f32(event.wheel.y) * zoom_speed
                        camera.distance = math.max(camera.distance, 0.1)
                case .QUIT:
                    break loop
            }      
        }
        key_state := sdl.GetKeyboardState(nil)
        move_speed :: 5.0
        if key_state[sdl.SCANCODE_UP] != 0 do camera.target.y += move_speed * timeContext.deltaTime
        if key_state[sdl.SCANCODE_DOWN] != 0 do camera.target.y -= move_speed * timeContext.deltaTime
        if key_state[sdl.SCANCODE_LEFT] != 0 do camera.target.x -= move_speed * timeContext.deltaTime
        if key_state[sdl.SCANCODE_RIGHT] != 0 do camera.target.x += move_speed * timeContext.deltaTime
        
       
        updateCameraPosition(ctx)
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
    using ctx.platform
    timeContext = cr.init(); defer cr.end(timeContext)
    initWindow(&ctx)
    initContext(&ctx)
    initVulkan(&ctx)
    initCamera(&ctx)
    AddUI(&ctx)
    run(&ctx)  
    exit(&ctx)
}

initContext :: proc(using ctx: ^Context) {
   using ctx.vulkan
   for &q in queueIndices do q = -1
}