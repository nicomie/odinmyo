package engine

import cr "../engine/core"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import vk "vendor:vulkan"

ViewProjection :: struct {
	view: linalg.Matrix4f32,
	proj: linalg.Matrix4f32,
}


createUniformBuffers :: proc(ctx: ^Context) {
	sys := &ctx.scene.cameraSystem

	bufferSize := cast(vk.DeviceSize)size_of(ViewProjection)

	sys.uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
	ctx.light.ubo = make([]Buffer, MAX_FRAMES_IN_FLIGHT)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		createBuffer(
			ctx,
			bufferSize,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&sys.uniformBuffers[i],
			fmt.tprintf("camera ubo%d", i),
		)
		vk.MapMemory(
			ctx.vulkan.device,
			sys.uniformBuffers[i].memory,
			0,
			bufferSize,
			{},
			&sys.uniformBuffers[i].mapped_ptr,
		)

		createBuffer(
			ctx,
			bufferSize,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&ctx.light.ubo[i],
			fmt.tprintf("light ubo%d", i),
		)
		vk.MapMemory(
			ctx.vulkan.device,
			ctx.light.ubo[i].memory,
			0,
			bufferSize,
			{},
			&ctx.light.ubo[i].mapped_ptr,
		)
	}


}

updateUniformBuffer :: proc(ctx: ^Context, currentImage: u32) {
	camera := camera_system_get_active(&ctx.scene.cameraSystem)

	ubo: ViewProjection = {
		view = camera.view,
		proj = camera.projection,
	}

	mem.copy(ctx.scene.cameraSystem.uniformBuffers[currentImage].mapped_ptr, &ubo, size_of(ubo))

	light := ctx.light.light
	lightubo: ViewProjection = {
		view = ctx.light.light.view,
		proj = ctx.light.light.projection,
	}

}
