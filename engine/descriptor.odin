package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:mem"


VERTEX_BINDING := vk.VertexInputBindingDescription{
    binding = 0,
    stride = size_of(Vertex),
    inputRate = .VERTEX,
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, pos),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color),
	},
    {
		binding = 0,
		location = 2,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, normals),
	},
    {
		binding = 0,
		location = 3,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, texCoord),
	},
}

DescriptorSetLayout :: struct {
    binding: u32,
    type: vk.DescriptorType,
    shaderStageFlags: vk.ShaderStageFlags
}

createDescriptorSetLayouts :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.pipe
    globalSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .UNIFORM_BUFFER, shaderStageFlags = {.VERTEX, .FRAGMENT}}, 
        {binding = 1, type = .UNIFORM_BUFFER, shaderStageFlags = {.FRAGMENT}}, 
    })

    materialSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .COMBINED_IMAGE_SAMPLER, shaderStageFlags = {.FRAGMENT}}, 
        {binding = 1, type = .UNIFORM_BUFFER, shaderStageFlags = {.FRAGMENT}}
    })


   uiDescriptorSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .COMBINED_IMAGE_SAMPLER, shaderStageFlags = {.FRAGMENT}},
    })
    
    descriptorSetLayouts = make(map[string]vk.DescriptorSetLayout)
    descriptorSetLayouts["global"] = globalSetLayout
    descriptorSetLayouts["material"] = materialSetLayout
    descriptorSetLayouts["ui"] = uiDescriptorSetLayout

}


createDescriptorSetLayout :: proc(device: vk.Device, descriptorSets: []DescriptorSetLayout) -> vk.DescriptorSetLayout{

    bindings := make([]vk.DescriptorSetLayoutBinding, len(descriptorSets))
    for set, i in descriptorSets {
        bindings[i] = vk.DescriptorSetLayoutBinding{
            binding = set.binding,
            descriptorCount = 1,
            descriptorType = set.type,
            stageFlags = set.shaderStageFlags,
            pImmutableSamplers = nil,
        }
    }
         
    layoutInfo := vk.DescriptorSetLayoutCreateInfo{
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = cast(u32)len(bindings),
        pBindings = &bindings[0]
    }
    
    layout: vk.DescriptorSetLayout
    if vk.CreateDescriptorSetLayout(device, &layoutInfo, nil, &layout) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorSetLayout")
        os.exit(1)
    }

    return layout
}

createGlobalDescriptorSets :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.pipe
    using ctx.resource
    using ctx.scene

    globalLayouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        globalLayouts[i] = descriptorSetLayouts["global"]
    }

    globalAllocInfo := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptorPool,
        descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &globalLayouts[0],
    }

    if vk.AllocateDescriptorSets(device, &globalAllocInfo, &cameraSystem.descriptorSets[0]) != .SUCCESS {
        fmt.eprintln("failed to allocate mesh descriptor sets")
        os.exit(1)
    }

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        bufferInfo := vk.DescriptorBufferInfo{
            buffer = cameraSystem.uniformBuffers.buffer[i].buffer,
            offset = 0,
            range = size_of(CameraUBO),
        }

        lightInfo := vk.DescriptorBufferInfo{
            buffer = scene.lightning.ubo.buffer[i].buffer,
            offset = 0,
            range = size_of(LightUBO),
        }

        globalDescriptorWrites := []vk.WriteDescriptorSet{
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 0,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo = &bufferInfo,
            },
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 1,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo = &lightInfo,
            }
        }

        vk.UpdateDescriptorSets(device, cast(u32)len(globalDescriptorWrites), &globalDescriptorWrites[0], 0, nil)
    }
}

createMaterialDescriptorSets :: proc(using ctx: ^Context) {
    using ctx.vulkan
    rm := ctx.resource

    fmt.println("=== Starting createMaterialDescriptorSets ===")
    fmt.printf("Number of materials: %d\n", len(rm.materials))
    fmt.printf("Number of textures: %d\n", len(rm.textures))

    for &mat, matIdx in rm.materials {
                
        fmt.printf("\n--- Processing material %d ---\n", matIdx)

        layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
        for i in 0..<MAX_FRAMES_IN_FLIGHT do layouts[i] = ctx.pipe.descriptorSetLayouts["material"]

        materialLayout := ctx.pipe.descriptorSetLayouts["material"]
        fmt.printf("Material descriptor set layout: %v\n", materialLayout)
        if materialLayout == {} {
            fmt.eprintln("ERROR: Material descriptor set layout is NULL!")
            os.exit(1)
        }
        allocInfo := vk.DescriptorSetAllocateInfo{
            sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
            descriptorPool = ctx.pipe.descriptorPool,
            descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
            pSetLayouts = &layouts[0],
        }

        checkVk(vk.AllocateDescriptorSets(device, &allocInfo, &mat.descriptorSets[0]))

        bufferSize := cast(vk.DeviceSize)size_of(MaterialUBO)

        mat.materialUBO = make([]Buffer, MAX_FRAMES_IN_FLIGHT)

        for i in 0..<MAX_FRAMES_IN_FLIGHT {
            createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, 
                &mat.materialUBO[i], fmt.tprintf("material ubo%d", i))
            vk.MapMemory(device, mat.materialUBO[i].memory, 0, bufferSize, {}, &mat.materialUBO[i].mapped_ptr)

            ubo: MaterialUBO
            ubo.color = mat.baseColorFactor

            fmt.printf("should use color: %d\n", mat.baseColorTexIdx != -1)
            ubo.params = mat.baseColorTexIdx == -1 ? Vec4{1,0,0,0} : Vec4{0,0,0,0}

            mem.copy(mat.materialUBO[i].mapped_ptr, &ubo, size_of(ubo))
        }

        for i in 0..<MAX_FRAMES_IN_FLIGHT {
            imageInfo := vk.DescriptorImageInfo{
                imageLayout = .SHADER_READ_ONLY_OPTIMAL,
                imageView   = rm.textures[mat.normalTexIdx].view,
                sampler     = rm.textures[mat.normalTexIdx].sampler,
            }

            bufferInfo := vk.DescriptorBufferInfo{
                buffer = mat.materialUBO[i].buffer,
                offset = 0,
                range  = size_of(MaterialUBO),
            }

            writes := []vk.WriteDescriptorSet{     
            {
                sType           = .WRITE_DESCRIPTOR_SET,
                dstSet          = mat.descriptorSets[i],
                dstBinding      = 0,
                descriptorType  = .COMBINED_IMAGE_SAMPLER,
                descriptorCount = 1,
                pImageInfo      = &imageInfo,
            },
               {
                sType           = .WRITE_DESCRIPTOR_SET,
                dstSet          = mat.descriptorSets[i],
                dstBinding      = 1,
                descriptorType  = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo      = &bufferInfo,
            }
        }
            vk.UpdateDescriptorSets(device, cast(u32)len(writes), &writes[0], 0, nil)
        }
    }
}

createUiDescriptorSets :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.pipe
    using ctx.resource
    using ctx.ui
    layouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        layouts[i] = descriptorSetLayouts["ui"]
    }

    allocInfo := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptorPool,
        descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &layouts[0],
    }

    if vk.AllocateDescriptorSets(device, &allocInfo, &ctx.ui.uiDescriptorSets[0]) != .SUCCESS {
        fmt.eprintln("failed to allocate ui descriptor sets")
        os.exit(1)
    }

    fmt.printf("Font texture - view: %v, sampler: %v\n", font.texture.view, font.texture.sampler)


    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        imageInfo := vk.DescriptorImageInfo{
            imageLayout = .SHADER_READ_ONLY_OPTIMAL,
            imageView = font.texture.view,
            sampler = font.texture.sampler
        }
    
        descriptorWrites := []vk.WriteDescriptorSet{
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = uiDescriptorSets[i],
                dstBinding = 0,
                dstArrayElement = 0,
                descriptorType = .COMBINED_IMAGE_SAMPLER,
                descriptorCount = 1,
                pImageInfo = &imageInfo,
            },
        }

        vk.UpdateDescriptorSets(device, cast(u32)len(descriptorWrites), &descriptorWrites[0], 0, nil)
    }
}

createIdDescriptorSets :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.pipe
    using ctx.resource
    using ctx.id
    idLayouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        idLayouts[i] = descriptorSetLayouts["global"]
    }

    idAllocInfo := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptorPool,
        descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &idLayouts[0],
    }

    if vk.AllocateDescriptorSets(device, &idAllocInfo, &idDescriptorSets[0]) != .SUCCESS {
        fmt.eprintln("failed to allocate ID descriptor sets")
        os.exit(1)
    }

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        bufferInfo := vk.DescriptorBufferInfo{
            buffer = ctx.scene.cameraSystem.uniformBuffers.buffer[i].buffer,
            offset = 0,
            range = size_of(CameraUBO),
        }

        idDescriptorWrites := []vk.WriteDescriptorSet{
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = idDescriptorSets[i],
                dstBinding = 0,
                dstArrayElement = 0,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo = &bufferInfo,
            },
        }

        vk.UpdateDescriptorSets(device, cast(u32)len(idDescriptorWrites), &idDescriptorWrites[0], 0, nil)
    }
}

createDescriptorPool :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.pipe
    poolSizes := []vk.DescriptorPoolSize{
        {
            type = .UNIFORM_BUFFER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT*20
        },
        {
            type = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT*20
        }
    }

    poolInfo : vk.DescriptorPoolCreateInfo
    poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
    poolInfo.poolSizeCount = cast(u32)len(poolSizes)
    poolInfo.pPoolSizes = &poolSizes[0]
    poolInfo.maxSets = MAX_FRAMES_IN_FLIGHT*20
    
    if vk.CreateDescriptorPool(device, &poolInfo, nil, &descriptorPool) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorPool")
        os.exit(1)
    }

}