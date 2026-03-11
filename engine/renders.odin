package engine 

import vk "vendor:vulkan"
import "core:strings"
import "base:runtime"
import "core:os"
import "core:fmt"

RenderSystem :: struct{
	modules:  []^RenderModule,
	activeModuleIndex: u32,
	activeModule: ^RenderModule,
	mode: RunMode,
}

RunMode :: enum{
    Single,
    Multi
}

RenderModule :: struct{
    name: string,
    data: rawptr,
    init: ModuleInitProc,
    resize: proc(ctx: ^Context, data: rawptr),
    shutdown: ExitProc,
    renderProcedures: []RenderProcedure
}

shutdownThreeD ::proc(m: ^RenderModule, ctx: ^Context) {
    device := ctx.vulkan.device

    module :^ThreeDModule= cast(^ThreeDModule)m.data
    vk.DestroyDescriptorSetLayout(ctx.vulkan.device, module.pipeline.descriptorSetLayouts["material"], nil)
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
    data: rawptr,
}

ThreeDModule :: struct{
    pipeline: PipelineContext,
    meshes: []MeshObject,
}

recordUI :: proc(r: ^RenderProcedure, ctx: ^Context, cmd: vk.CommandBuffer, frameIndex: u32) {
    descriptorSets := &ctx.ui.uiDescriptorSets
    swapchain := &ctx.sc.swapchain

    vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipe.pipelines["ui"])
    vk.CmdBindDescriptorSets(cmd, .GRAPHICS, ctx.pipe.uiPipelineLayout, 0, 1, &descriptorSets[frameIndex], 0, nil)

    for &element in ctx.ui.elements {
        screen_size := Vec2{f32(swapchain.extent.width), f32(swapchain.extent.height)}
        vk.CmdPushConstants(
            cmd,
            ctx.pipe.uiPipelineLayout,
            {.VERTEX, .FRAGMENT},
            0,                 
            size_of(Vec2), 
            &screen_size,
        )

        if &element.vertex_buffer^ != nil {
            vertexBuffers := [?]vk.Buffer{element.vertex_buffer.buffer}
            offsets := [?]vk.DeviceSize{0}
            vk.CmdBindVertexBuffers(cmd, 0, 1, raw_data(vertexBuffers[:]), raw_data(offsets[:]))
            vk.CmdDraw(cmd, u32(element.vertex_buffer.length), 1, 0, 0)
        }
    }
}

record3D :: proc(r: ^RenderProcedure,ctx: ^Context, cmd: vk.CommandBuffer, frameIndex: u32) {
    module :^ThreeDModule= cast(^ThreeDModule)r.data
    vk.CmdBindPipeline(cmd, .GRAPHICS, module.pipeline.pipelines["mesh"])
    vk.CmdBindDescriptorSets(cmd, vk.PipelineBindPoint.GRAPHICS, module.pipeline.meshPipelineLayout, 
                        0, 1, &ctx.scene.cameraSystem.descriptorSets[frameIndex], 0, nil);

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
            &o.worldTransform
        )

        for primitive in mesh.primitives {
            matIndex := primitive.materialIndex
            vk.CmdBindDescriptorSets(cmd, .GRAPHICS, module.pipeline.meshPipelineLayout, 1, 1, 
                &ctx.resource.materials[matIndex].descriptorSets[frameIndex], 0, nil)
            vk.CmdDrawIndexed(cmd, cast(u32)primitive.indexCount, 1, cast(u32)primitive.firstIndex, primitive.firstVertex, 0)
        }
    }

}

init3DModule :: proc(ctx: ^Context) -> ^RenderModule {
    m := new(RenderModule)
    m.name = "3d"
    moduleData := new(ThreeDModule)
    m.data = cast(rawptr)moduleData

    m.renderProcedures = make([]RenderProcedure, 2)
    m.renderProcedures[0] = RenderProcedure{
        record = record3D,
        data   = m.data,
    }
    m.renderProcedures[1] = RenderProcedure{
        record = recordUI,
        data   = nil,
    }

    m.shutdown = shutdownThreeD

    moduleData.pipeline.descriptorPool = ctx.pipe.descriptorPool
	file, errx := os.join_path({"glbs", "SciFiHelmet", "glTF"}, runtime.heap_allocator())
	setupGlb(ctx, strings.clone_to_cstring(file), "SciFiHelmet.gltf", &moduleData.meshes)
    createDescriptorSetLayouts(ctx, &moduleData.pipeline)
	createMaterialDescriptorSets(ctx, moduleData.pipeline.descriptorSetLayouts["material"])
	createPipelineLayouts(ctx, &moduleData.pipeline)
    createPipelines(ctx, &moduleData.pipeline)
    return m
}
