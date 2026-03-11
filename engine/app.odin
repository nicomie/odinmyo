package engine

import "vendor:darwin/CoreVideo"
import cr "../engine/core"
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "vendor:cgltf"
import sdl "vendor:sdl2"
import "vendor:stb/image"
import vk "vendor:vulkan"


MAX_FRAMES_IN_FLIGHT :: 2

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32
Mat4 :: linalg.Matrix4f32

UIContext :: struct {
	font:             Font,
	elements:         [dynamic]UIElement,
	uiDescriptorSets: [2 * MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
}

PlatformContext :: struct {
	window:                     ^sdl.Window,
	timeContext:                ^cr.TimeContext,
	clickPending:               bool,
	clickX, clickY:             i32,
	clickyXDelta, clickyYDelta: i32,
}

VulkanContext :: struct {
	instance:       vk.Instance,
	device:         vk.Device,
	physicalDevice: vk.PhysicalDevice,
	queueIndices:   [QueueFamily]int,
	graphicsQueue:  vk.Queue,
	surface:        vk.SurfaceKHR,
	debugMessenger: vk.DebugUtilsMessengerEXT,
	presentQueue:   vk.Queue,
	commandPool:    vk.CommandPool,
}

SwapchainContext :: struct {
	swapchain:  Swapchain,
	renderPass: vk.RenderPass,
	depthImage: DepthImage,
	colorImage: DepthImage,
	msaa:       vk.SampleCountFlags,
}

FrameContext :: struct {
	commandBuffer:           vk.CommandBuffer,
	imageAvailableSemaphore: vk.Semaphore,
	inFlightFence:           vk.Fence,
}

PipelineContext :: struct {
	pipelines:            map[string]vk.Pipeline,
	meshPipelineLayout:   vk.PipelineLayout,
	uiPipelineLayout:     vk.PipelineLayout,
	descriptorPool:       vk.DescriptorPool,
	descriptorSetLayouts: map[string]vk.DescriptorSetLayout
}


SceneContext :: struct {
	cameraSystem: CameraSystem,
	ray:          Ray,
	toggleHover:  bool,
	isPlayer:     bool,
	mesh:         Mesh,
}

Context :: struct {
	platform:           PlatformContext,
	vulkan:             VulkanContext,
	sc:                 SwapchainContext,
	pipe:               PipelineContext,
	resource:           ResourceManager,
	scene:              SceneContext,
	ui:                 UIContext,
	frames:             [MAX_FRAMES_IN_FLIGHT]FrameContext,
	imagesInFlight: 	[]vk.Fence,
	renderFinishedSemaphores: []vk.Semaphore,
	currentFrame:       u32,
	framebufferResized: bool,
	render: RenderSystem,
    
	globalDescriptorSetLayouts: map[string]vk.DescriptorSetLayout,
	globalDescriptorSets: []vk.DescriptorSet,
}

Ray :: struct {
	origin:    linalg.Vector4f32,
	direction: linalg.Vector4f32,
}

Vertex :: struct {
	pos:      [3]f32,
	color:    [3]f32,
	texCoord: [2]f32,
}

initVulkan :: proc(ctx: ^Context) {
	getInstanceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
	assert(getInstanceProcAddr != nil)
	vk.load_proc_addresses(getInstanceProcAddr)
	create_instance(ctx)

	vk.load_proc_addresses(ctx.vulkan.instance)
	setup_debug_messenger(ctx)

	fmt.println("Available extensions")
	extensions := get_extensions()
	for _, i in extensions do fmt.println(cstring(&extensions[i].extensionName[0]))

	createSurface(ctx)
	pickPhysicalDevice(ctx)
	createLogicalDevice(ctx)
	createSwapchain(ctx)
	createImageViews(ctx)
	findQueueFamilies(ctx)

	ctx.sc.renderPass = createRenderPass(
		ctx,
		{format = ctx.sc.swapchain.format, use_depth = true, final_layout = .PRESENT_SRC_KHR},
	)

	createCommandPool(ctx)
    createColorResources(ctx)
	createDepthResource(ctx)
	createFramebuffer(ctx)
	createUniformBuffers(ctx)
	createCommandBuffers(ctx)
	createDescriptorPool(ctx)

	createGlobalDescriptorSetLayouts(ctx)
	createGlobalDescriptorSets(ctx)
	createGlobalPipelineLayouts(ctx)

	bool := AddUI(ctx)
	createUiDescriptorSets(ctx)
	createSyncObjects(ctx)

	ffmpeg_test()
	ctx.render.modules = make([]^RenderModule, 1)
	ctx.render.modules[0] = init3DModule(ctx)
}

exit :: proc(ctx: ^Context) {
	device := ctx.vulkan.device
	swapchain := &ctx.sc.swapchain
	textures := &ctx.resource.textures

	vk.DeviceWaitIdle(device)
	cleanSwapchain(ctx)

	for module in ctx.render.modules {
		module->shutdown(ctx)
	}

	for texture in textures {
		vk.DestroySampler(device, texture^.sampler, nil)
		vk.DestroyImageView(device, texture^.view, nil)
		vk.DestroyImage(device, texture^.handle.texture, nil)
		vk.FreeMemory(device, texture^.handle.memory, nil)
	}

	// --- Buffers ---
	freeCameras(ctx)

	for &mat in ctx.resource.materials {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			destroyBuffer(fmt.tprintf("material-ubo%d", i), device, mat.materialUBO[i])
		}
		delete(mat.materialUBO)
	}


	// for mesh in meshes {
	for &mesh in ctx.resource.meshes {
		destroyBuffer("vBuffer", device, mesh.vertexBuffer^)
		destroyBuffer("iBuffer", device, mesh.indexBuffer^)
	}

	for el in ctx.ui.elements {
		destroyBuffer("meshVertex", device, ctx.ui.elements[0].vertex_buffer^)
	}
	free_font(ctx, &ctx.ui.font)


	// --- Descriptor cleanup ---
	vk.DestroyDescriptorPool(device, ctx.pipe.descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(device, ctx.globalDescriptorSetLayouts["global"], nil)
	vk.DestroyDescriptorSetLayout(device, ctx.globalDescriptorSetLayouts["ui"], nil)
	delete(ctx.globalDescriptorSetLayouts)

	// --- Pipelines ---
	for _, pipeline in ctx.pipe.pipelines {
		vk.DestroyPipeline(device, pipeline, nil)
	}
	delete(ctx.pipe.pipelines)

	vk.DestroyPipelineLayout(device, ctx.pipe.uiPipelineLayout, nil)

	// --- Render passes ---
	vk.DestroyRenderPass(device, ctx.sc.renderPass, nil)

	// --- Sync ---
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(device, ctx.frames[i].imageAvailableSemaphore, nil)
		vk.DestroyFence(device, ctx.frames[i].inFlightFence, nil)
	}
	for i in 0 ..< len(ctx.renderFinishedSemaphores) {
		vk.DestroySemaphore(device, ctx.renderFinishedSemaphores[i], nil)
	}

	// --- Command pool ---
	vk.DestroyCommandPool(device, ctx.vulkan.commandPool, nil)

	// --- Device and Instance ---
	vk.DestroyDevice(device, nil)
	when ODIN_DEBUG {
		DestroyDebugUtilsMessengerEXT(ctx.vulkan.instance, ctx.vulkan.debugMessenger, nil)
	}
	vk.DestroySurfaceKHR(ctx.vulkan.instance, ctx.vulkan.surface, nil)
	vk.DestroyInstance(ctx.vulkan.instance, nil)

	// --- SDL ---
	sdl.DestroyWindow(ctx.platform.window)
	sdl.Quit()
}


run :: proc(ctx: ^Context) {

	cameraSystem := &ctx.scene.cameraSystem
	timeContext := ctx.platform.timeContext

	loop: for {
		target_frame_time := 1.0 / 240.0
		frame_start := time.now()
		cr.update(timeContext)
		camera := camera_system_get_active(cameraSystem)

		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .KEYDOWN:
				#partial switch event.key.keysym.sym {
				case .ESCAPE:
					break loop
				case .SPACE:
					ctx.scene.isPlayer = !ctx.scene.isPlayer
					
					ctx.ui.elements[0].stagedText = ctx.scene.isPlayer ? "Playing" : "Viewing"
					if !ctx.scene.isPlayer do camera_system_toggle(cameraSystem, .Free)
					if ctx.scene.isPlayer do camera_system_toggle(cameraSystem, .Player)
					fmt.printf("isPlayer toggled to: %t\n", ctx.scene.isPlayer)
				}
			case .KEYUP:
				#partial switch event.key.keysym.sym {
				case .ESCAPE:
				}
			case .MOUSEBUTTONDOWN:
				if event.button.button == sdl.BUTTON_MIDDLE {
					ctx.platform.clickPending = true
					ctx.platform.clickX = event.button.x
					ctx.platform.clickY = event.button.y
					fmt.printf("Middle mouse button at (%d, %d)\n", event.button.x, event.button.y)

				}
			case .MOUSEBUTTONUP:
				if event.button.button == sdl.BUTTON_MIDDLE {
					ctx.platform.clickPending = false
					fmt.printf(
						"Middle mouse button released at (%d, %d)\n",
						event.button.x,
						event.button.y,
					)

				}
			case .MOUSEMOTION:
				if ctx.platform.clickPending {
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
			time.sleep(time.Duration(sleep_time * 1e9)) // Nanoseconds
		}
	}
	vk.DeviceWaitIdle(ctx.vulkan.device)
}

main :: proc() {
	ctx: Context
	ctx.platform.timeContext = cr.init(); defer cr.end(ctx.platform.timeContext)
	initWindow(&ctx)
	initContext(&ctx)
	initVulkan(&ctx)
	initCamera(&ctx)
	run(&ctx)
	exit(&ctx)
}

initContext :: proc(ctx: ^Context) {
	for &q in ctx.vulkan.queueIndices do q = -1
}
