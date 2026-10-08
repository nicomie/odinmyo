package engine

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

RenderSystem :: struct {
	modules:           []^RenderModule,
	activeModuleIndex: u32,
	activeModule:      ^RenderModule,
	mode:              RunMode,
}

RunMode :: enum {
	Single,
	Multi,
}

RenderOption :: enum {
	Fullscreen,
}

RenderRegion :: union {
	RenderOption,
	^UIElement,
}

RenderPassType :: enum {
	Scene,
	Composite,
	UI,
}

RenderModule :: struct {
	name:             string,
	data:             rawptr,
	init:             ModuleInitProc,
	resize:           proc(ctx: ^Context, data: rawptr),
	shutdown:         ExitProc,
	renderProcedures: []RenderProcedure,
}

shutdownThreeD :: proc(m: ^RenderModule, ctx: ^Context) {
	device := ctx.vulkan.device

	module: ^ThreeDModule = cast(^ThreeDModule)m.data
	vk.DestroyDescriptorSetLayout(
		ctx.vulkan.device,
		module.pipeline.descriptorSetLayouts["material"],
		nil,
	)
	delete(module.pipeline.descriptorSetLayouts)

	for _, pipeline in module.pipeline.pipelines {
		vk.DestroyPipeline(device, pipeline, nil)
	}
	delete(module.pipeline.pipelines)

	vk.DestroyPipelineLayout(device, module.pipeline.meshPipelineLayout, nil)
}

ModuleInitProc :: proc(ctx: ^Context)
RecordProc :: proc(r: ^RenderProcedure, ctx: ^Context, cmd: vk.CommandBuffer, frameIndex: u32)
ExitProc :: proc(r: ^RenderModule, ctx: ^Context)

RenderProcedure :: struct {
	record: RecordProc,
	data:   rawptr,
	pass:   RenderPassType,
	region: RenderRegion,
}

ThreeDModule :: struct {
	pipeline: PipelineContext,
	meshes:   []MeshObject,
}

findProcedures := proc(m: ^RenderModule, pass: RenderPassType) -> []^RenderProcedure {
	procedures := make([dynamic]^RenderProcedure, 0)

	for i in 0 ..< len(m.renderProcedures) {
		if m.renderProcedures[i].pass == pass {
			append(&procedures, &m.renderProcedures[i])
		}
	}

	return procedures[:]
}

recordUI :: proc(r: ^RenderProcedure, ctx: ^Context, cmd: vk.CommandBuffer, frameIndex: u32) {
	descriptorSets := &ctx.ui.uiDescriptorSets
	swapchain := &ctx.sc.swapchain

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipe.pipelines["ui"])
	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ctx.pipe.compositePipelineLayout,
		0,
		1,
		&descriptorSets[frameIndex],
		0,
		nil,
	)

	root := ctx.ui.root

	if root != nil do RenderUI(cmd, ctx, frameIndex)
}

record3D :: proc(r: ^RenderProcedure, ctx: ^Context, cmd: vk.CommandBuffer, frameIndex: u32) {
	module: ^ThreeDModule = cast(^ThreeDModule)r.data
	vk.CmdBindPipeline(cmd, .GRAPHICS, module.pipeline.pipelines["scene"])
	vk.CmdBindDescriptorSets(
		cmd,
		vk.PipelineBindPoint.GRAPHICS,
		module.pipeline.meshPipelineLayout,
		0,
		1,
		&ctx.scene.cameraSystem.descriptorSets[frameIndex],
		0,
		nil,
	)

	for &o in module.meshes {
		mesh := ctx.resource.meshes[o.meshIndex]

		vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}
		offsets := [?]vk.DeviceSize{0}

		vk.CmdBindVertexBuffers(cmd, 0, 1, &vertexBuffers[0], &offsets[0])
		vk.CmdBindIndexBuffer(cmd, mesh.indexBuffer.buffer, 0, .UINT32)

		vk.CmdPushConstants(
			cmd,
			module.pipeline.meshPipelineLayout,
			{.VERTEX},
			0,
			size_of(Mat4),
			&o.worldTransform,
		)

		for primitive in mesh.primitives {
			matIndex := primitive.materialIndex
			vk.CmdBindDescriptorSets(
				cmd,
				.GRAPHICS,
				module.pipeline.meshPipelineLayout,
				1,
				1,
				&ctx.resource.materials[matIndex].descriptorSets[frameIndex],
				0,
				nil,
			)
			vk.CmdDrawIndexed(
				cmd,
				cast(u32)primitive.indexCount,
				1,
				cast(u32)primitive.firstIndex,
				primitive.firstVertex,
				0,
			)
		}
	}

}

recordComposite :: proc(
	r: ^RenderProcedure,
	ctx: ^Context,
	cmd: vk.CommandBuffer,
	frameIndex: u32,
) {
	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipe.pipelines["composite"])

	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ctx.pipe.compositePipelineLayout,
		0,
		1,
		&ctx.pipe.compositeDescriptorSets[frameIndex],
		0,
		nil,
	)

	// fullscreen triangle
	vk.CmdDraw(cmd, 3, 1, 0, 0)
}

init3DModule :: proc(ctx: ^Context) -> ^RenderModule {
	m := new(RenderModule)
	m.name = "3d"
	moduleData := new(ThreeDModule)
	m.data = cast(rawptr)moduleData

	m.renderProcedures = make([]RenderProcedure, 3)
	m.renderProcedures[0] = RenderProcedure {
		record = record3D,
		data   = m.data,
		pass   = .Scene,
		region = RenderOption.Fullscreen,
	}
	m.renderProcedures[1] = RenderProcedure {
		record = recordComposite,
		data   = nil,
		pass   = .Composite,
		region = findWindow(ctx, ctx.ui.root, .Render),
	}
	m.renderProcedures[2] = RenderProcedure {
		record = recordUI,
		data   = nil,
		pass   = .UI,
		region = RenderOption.Fullscreen,
	}

	m.shutdown = shutdownThreeD

	moduleData.pipeline.descriptorPool = ctx.pipe.descriptorPool
	file, errx := os.join_path({"glbs", "SciFiHelmet", "glTF"}, runtime.heap_allocator())
	setupGlb(ctx, strings.clone_to_cstring(file), "SciFiHelmet.gltf", &moduleData.meshes)
	createDescriptorSetLayoutsForPipe(ctx, &moduleData.pipeline)
	createMaterialDescriptorSets(ctx, moduleData.pipeline.descriptorSetLayouts["material"])
	createPipelineLayouts(ctx, &moduleData.pipeline)
	createPipelines(ctx, &moduleData.pipeline)
	return m
}
