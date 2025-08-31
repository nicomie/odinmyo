package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

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
    meshDescriptorSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .UNIFORM_BUFFER, shaderStageFlags = {.VERTEX}}, 
        {binding = 1, type = .COMBINED_IMAGE_SAMPLER, shaderStageFlags = {.FRAGMENT}}, 
    })

    idDescriptorSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .UNIFORM_BUFFER, shaderStageFlags = {.VERTEX, .FRAGMENT}}, 
    })

    descriptorSetLayouts = make(map[string]vk.DescriptorSetLayout)
    descriptorSetLayouts["mesh"] = meshDescriptorSetLayout
    descriptorSetLayouts["id"] = idDescriptorSetLayout
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

createDescriptorSets :: proc(using ctx: ^Context) {
    meshLayouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        meshLayouts[i] = descriptorSetLayouts["mesh"]
    }

    meshAllocInfo := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptorPool,
        descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &meshLayouts[0],
    }

    meshDescriptorSets := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    if vk.AllocateDescriptorSets(device, &meshAllocInfo, &descriptorSets[0]) != .SUCCESS {
        fmt.eprintln("failed to allocate mesh descriptor sets")
        os.exit(1)
    }

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        bufferInfo := vk.DescriptorBufferInfo{
            buffer = uniformBuffers[i].buffer,
            offset = 0,
            range = size_of(UBO),
        }

        imageInfo := vk.DescriptorImageInfo{
            imageLayout = .SHADER_READ_ONLY_OPTIMAL,
            imageView = texture.view,
            sampler = texture.sampler,
        }

        meshDescriptorWrites := []vk.WriteDescriptorSet{
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 0,
                dstArrayElement = 0,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo = &bufferInfo,
            },
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 1,
                dstArrayElement = 0,
                descriptorType = .COMBINED_IMAGE_SAMPLER,
                descriptorCount = 1,
                pImageInfo = &imageInfo,
            },
        }

        vk.UpdateDescriptorSets(device, cast(u32)len(meshDescriptorWrites), &meshDescriptorWrites[0], 0, nil)
    }
}

createIdDescriptorSets :: proc(using ctx: ^Context) {
    idLayouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        idLayouts[i] = descriptorSetLayouts["id"]
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
            buffer = uniformBuffers[i].buffer,
            offset = 0,
            range = size_of(UBO),
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

    poolSizes := []vk.DescriptorPoolSize{
        {
            type = .UNIFORM_BUFFER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT*2 + MAX_FRAMES_IN_FLIGHT
        },
        {
            type = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT
        }
    }

    poolInfo : vk.DescriptorPoolCreateInfo
    poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
    poolInfo.poolSizeCount = cast(u32)len(poolSizes)
    poolInfo.pPoolSizes = &poolSizes[0]
    poolInfo.maxSets = MAX_FRAMES_IN_FLIGHT*2
    
    if vk.CreateDescriptorPool(device, &poolInfo, nil, &descriptorPool) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorPool")
        os.exit(1)
    }

}