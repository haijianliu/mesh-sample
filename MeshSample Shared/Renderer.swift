//
//  Renderer.swift
//  MeshSample Shared
//
//  Created by haijian on 2019/05/11.
//  Copyright © 2019 haijian. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size & ~0xFF) + 0x100

// The max number of command buffers in flight
let maxBuffersInFlight = 3

enum RendererError: Error {
	case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
	
	public let device: MTLDevice
	let commandQueue: MTLCommandQueue
	var dynamicUniformBuffer: MTLBuffer
	var pipelineState: MTLRenderPipelineState
	var depthState: MTLDepthStencilState
	var colorMap: MTLTexture
	
	let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
	
	var uniformBufferOffset = 0
	
	var uniformBufferIndex = 0
	
	var uniforms: UnsafeMutablePointer<Uniforms>
	
	var projectionMatrix: matrix_float4x4 = matrix_float4x4()
	
	var rotation: Float = 0
	
	var mesh: MTKMesh
	
	var meshes = [MTKMesh]()
	
	init?(metalKitView: MTKView) {
		self.device = metalKitView.device!
		guard let queue = self.device.makeCommandQueue() else { return nil }
		self.commandQueue = queue
		
		let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
		
		guard let buffer = self.device.makeBuffer(length:uniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
		dynamicUniformBuffer = buffer
		
		self.dynamicUniformBuffer.label = "UniformBuffer"
		
		uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)
		
		metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
		metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
		metalKitView.sampleCount = 1
		
		let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
		
		do {
			pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
																																 metalKitView: metalKitView,
																																 mtlVertexDescriptor: mtlVertexDescriptor)
		} catch {
			print("Unable to compile render pipeline state.  Error info: \(error)")
			return nil
		}
		
		let depthStateDesciptor = MTLDepthStencilDescriptor()
		depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
		depthStateDesciptor.isDepthWriteEnabled = true
		guard let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) else { return nil }
		depthState = state
		
		do {
			mesh = try Renderer.buildMesh(device: device, mtlVertexDescriptor: mtlVertexDescriptor)
		} catch {
			print("Unable to build MetalKit Mesh. Error info: \(error)")
			return nil
		}
		
		do {
			colorMap = try Renderer.loadTexture(device: device, textureName: "ColorMap")
		} catch {
			print("Unable to load texture. Error info: \(error)")
			return nil
		}
		
		// Create a Model I/O vertexDescriptor so that we format/layout our Model I/O mesh vertices to fit our Metal render pipeline's vertex descriptor layout
		let modelIOVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
		guard let attributes = modelIOVertexDescriptor.attributes as? [MDLVertexAttribute] else { return nil }
		
		// Indicate how each Metal vertex descriptor attribute maps to each ModelIO  attribute
		attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
		attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
		attributes[VertexAttribute.normal.rawValue].name = MDLVertexAttributeNormal
		attributes[VertexAttribute.tangent.rawValue].name = MDLVertexAttributeTangent
		attributes[VertexAttribute.bitangent.rawValue].name = MDLVertexAttributeBitangent
		
		// Uses Model I/O to load a model file at the given URL
		let modelFileURL = Bundle.main.url(forResource: "Models/firetruck", withExtension: "obj")
		// Create a MetalKit mesh buffer allocator so that Model I/O  will load mesh data directly into Metal buffers accessible by the GPU
		let bufferAllocator = MTKMeshBufferAllocator(device: device)
		// Use Model I/O to load the model file at the URL.
		// This returns a Model I/O asset object, which contains a hierarchy of Model I/O objects composing a "scene" described by the model file.
		// This hierarchy may include lights, cameras, but, most importantly, mesh and submesh data that we'll render with Metal
		let asset = MDLAsset(url: modelFileURL, vertexDescriptor: nil, bufferAllocator: bufferAllocator)
		
		// Traverse the Model I/O asset hierarchy to find Model I/O meshes and create Metal vertex buffers, index buffers, and textures from them
		for object in asset.childObjects(of: MDLMesh.self) {
			// If this Model I/O  object is a mesh object (not a camera, light, or something else)...
			if let modelIOMesh = object as? MDLMesh {
				// Apply the Model I/O vertex descriptor we created to match the Metal vertex descriptor.
				// Assigning a new vertex descriptor to a Model I/O mesh performs a re-layout of the vertex data. In this case we created the Model I/O vertex descriptor so that the layout of the vertices in the Model I/O mesh match the layout of vertices our Metal render pipeline expects as input into its vertex shader
				// Note that we can only perform this re-layout operation after we have created tangents and bitangents. This is because Model I/O's addTangentBasis methods only work with vertex data is all in 32-bit floating-point. The vertex descriptor we're applying changes some 32-bit floats into 16-bit floats or other types from which Model I/O cannot produce tangents
				modelIOMesh.vertexDescriptor = modelIOVertexDescriptor

				// Create the metalKit mesh which will contain the Metal buffer(s) with the mesh's vertex data and submeshes with info to draw the mesh
				var metalKitMesh: MTKMesh
				do { metalKitMesh = try MTKMesh(mesh: modelIOMesh, device: device) }
				catch { print("Unable to build MetalKit Mesh. Error info: \(error)"); return nil }
				meshes.append(metalKitMesh)
				
				// There should always be the same number of MetalKit submeshes in the MetalKit mesh as there are Model I/O submeshes in the Model I/O mesh
				assert(metalKitMesh.submeshes.count == modelIOMesh.submeshes!.count);
			}
		}
		
		super.init()
	}
	
	class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
		// Creete a Metal vertex descriptor specifying how vertices will by laid out for input into our render
		//   pipeline and how we'll layout our Model IO vertices
		
		let mtlVertexDescriptor = MTLVertexDescriptor()
		
		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
		mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
		
		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
		mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
		
		mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].format = MTLVertexFormat.half4
		mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].offset = 8
		mtlVertexDescriptor.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
		
		mtlVertexDescriptor.attributes[VertexAttribute.tangent.rawValue].format = MTLVertexFormat.half4
		mtlVertexDescriptor.attributes[VertexAttribute.tangent.rawValue].offset = 16
		mtlVertexDescriptor.attributes[VertexAttribute.tangent.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
		
		mtlVertexDescriptor.attributes[VertexAttribute.bitangent.rawValue].format = MTLVertexFormat.half4
		mtlVertexDescriptor.attributes[VertexAttribute.bitangent.rawValue].offset = 24
		mtlVertexDescriptor.attributes[VertexAttribute.bitangent.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
		
		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
		mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex
		
		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 32
		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
		mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex
		
		return mtlVertexDescriptor
	}
	
	class func buildRenderPipelineWithDevice(device: MTLDevice,
																					 metalKitView: MTKView,
																					 mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
		/// Build a render state pipeline object
		
		let library = device.makeDefaultLibrary()
		
		let vertexFunction = library?.makeFunction(name: "vertexShader")
		let fragmentFunction = library?.makeFunction(name: "fragmentShader")
		
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.label = "RenderPipeline"
		pipelineDescriptor.sampleCount = metalKitView.sampleCount
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
		
		pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
		pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
		pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
		
		return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
	}
	
	class func buildMesh(device: MTLDevice,
											 mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
		/// Create and condition mesh data to feed into a pipeline using the given vertex descriptor
		
		let metalAllocator = MTKMeshBufferAllocator(device: device)
		
		let mdlMesh = MDLMesh.newBox(withDimensions: float3(4, 4, 4),
																 segments: uint3(2, 2, 2),
																 geometryType: MDLGeometryType.triangles,
																 inwardNormals:false,
																 allocator: metalAllocator)
		
		let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
		
		guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
			throw RendererError.badVertexDescriptor
		}
		attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
		attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
		
		mdlMesh.vertexDescriptor = mdlVertexDescriptor
		
		return try MTKMesh(mesh:mdlMesh, device:device)
	}
	
	class func loadTexture(device: MTLDevice,
												 textureName: String) throws -> MTLTexture {
		/// Load texture data with optimal parameters for sampling
		
		let textureLoader = MTKTextureLoader(device: device)
		
		let textureLoaderOptions = [
			MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
			MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
		]
		
		return try textureLoader.newTexture(name: textureName,
																				scaleFactor: 1.0,
																				bundle: nil,
																				options: textureLoaderOptions)
		
	}
	
	private func updateDynamicBufferState() {
		/// Update the state of our uniform buffers before rendering
		
		uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
		
		uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
		
		uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
	}
	
	private func updateGameState() {
		/// Update any game state before rendering
		
		uniforms[0].projectionMatrix = projectionMatrix
		
		let rotationAxis = float3(0, 1, 0)
		let modelMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
		let viewMatrix = matrix4x4_translation(0.0, -10.0, -40.0)
		uniforms[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
		rotation += 0.01
	}
	
	func draw(in view: MTKView) {
		/// Per frame updates hare
		
		_ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
		
		if let commandBuffer = commandQueue.makeCommandBuffer() {
			
			let semaphore = inFlightSemaphore
			commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
				semaphore.signal()
			}
			
			self.updateDynamicBufferState()
			
			self.updateGameState()
			
			/// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
			///   holding onto the drawable and blocking the display pipeline any longer than necessary
			let renderPassDescriptor = view.currentRenderPassDescriptor
			
			if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
				
				/// Final pass rendering code here
				renderEncoder.label = "Primary Render Encoder"
				
				renderEncoder.pushDebugGroup("Draw Box")
				
				renderEncoder.setCullMode(.back)
				
				renderEncoder.setFrontFacing(.counterClockwise)
				
				renderEncoder.setRenderPipelineState(pipelineState)
				
				renderEncoder.setDepthStencilState(depthState)
				
				renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
				renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
				
				renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.baseColor.rawValue)
				
				for mesh in meshes {
					for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
						guard let layout = element as? MDLVertexBufferLayout else { return }
						
						if layout.stride != 0 {
							let buffer = mesh.vertexBuffers[index]
							renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
						}
					}
					
					for submesh in mesh.submeshes {
						renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
					}
				}
			
				renderEncoder.popDebugGroup()
				
				renderEncoder.endEncoding()
				
				if let drawable = view.currentDrawable {
					commandBuffer.present(drawable)
				}
			}
		
			commandBuffer.commit()
		}
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		/// Respond to drawable size or orientation changes here
		
		let aspect = Float(size.width) / Float(size.height)
		projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
	}
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: float3) -> matrix_float4x4 {
	let unitAxis = normalize(axis)
	let ct = cosf(radians)
	let st = sinf(radians)
	let ci = 1 - ct
	let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
	return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
																			 vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
																			 vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
																			 vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
	return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
																			 vector_float4(0, 1, 0, 0),
																			 vector_float4(0, 0, 1, 0),
																			 vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
	let ys = 1 / tanf(fovy * 0.5)
	let xs = ys / aspectRatio
	let zs = farZ / (nearZ - farZ)
	return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
																			 vector_float4( 0, ys, 0,   0),
																			 vector_float4( 0,  0, zs, -1),
																			 vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
	return (degrees / 180) * .pi
}

