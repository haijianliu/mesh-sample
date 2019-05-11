//
//  Mesh.swift
//  MeshSample
//
//  Created by haijian on 2019/05/11.
//  Copyright © 2019 haijian. All rights reserved.
//

import Metal
import MetalKit
import Foundation

// MARK: - App specific submesh class containing data to draw a submesh
class Submesh: NSObject {
	
	// Sets the weight of values sampled from a texture vs a material uniform for a transition
	//   between levels.
	func computeTextureWeightsForQualityLevel(quality: QualityLevel, withGlobalMapWeight globalWeight: Float) {
		for textureIndex in 0 ..< TextureIndex.numMeshTextureIndices.rawValue {
			let constantIndex = Submesh.mapTextureBindPointToFunctionConstantIndex(textureIndex: TextureIndex(rawValue: textureIndex)!)
			
			if Mesh.isTexturedProperty(propertyIndex: constantIndex, atQualityLevel: quality) {
				uniforms.pointee.mapWeights.0 = globalWeight
			} else {
				uniforms.pointee.mapWeights.0 = 1.0
			}
		}
	}
	
	// MARK: Properties
	
	// A MetalKit submesh mesh containing the primitive type, index buffer, and index count
	//   used to draw all or part of its parent Mesh object
	var metalKitSubmmesh: MTKSubmesh
	
	// Material textures (indexed by TextureIndex) to set in the Metal Render Command Encoder
	//  before drawing the submesh.  Used for higher LODs
	var textures: [MTLTexture?]
	
	// Material uniforms used instead of texture when rendering with lower LODs
	var materialUniforms: MTLBuffer
	
	var uniforms: UnsafeMutablePointer<MaterialUniforms>
	
	// MARK: Initializer
	
	init?(modelIOSubmesh: MDLSubmesh, metalKitSubmesh: MTKSubmesh, metalKitTextureLoader textureLoader: MTKTextureLoader) {
		metalKitSubmmesh = metalKitSubmesh;
		
		// Fill up our texture array with null objects so that we can fill it by indexing into it
		textures = [MTLTexture?](repeating: nil, count: TextureIndex.numMeshTextureIndices.rawValue)
		
		//create the uniform buffer
		guard let buffer = textureLoader.device.makeBuffer(length: MemoryLayout<MaterialUniforms>.size, options:[]) else { return nil }
		materialUniforms = buffer
		
		materialUniforms.label = "MaterialUniforms"
		
		uniforms = UnsafeMutableRawPointer(materialUniforms.contents()).bindMemory(to: MaterialUniforms.self, capacity: 1)
		
		// Set default material uniforms
		uniforms.pointee.baseColor = vector3(0.3, 0.0, 0.0)
		uniforms.pointee.roughness = vector3(0.2, 0.2, 0.2)
		uniforms.pointee.metalness = vector3(0.0, 0.0, 0.0)
		uniforms.pointee.ambientOcclusion = 0.5
		uniforms.pointee.irradiatedColor = vector3(1.0, 1.0, 1.0)
		
		// Set each index in our array with the appropriate material semantic specified in the submesh's material property
		
		textures[TextureIndex.baseColor.rawValue] = Submesh.createMetalTextureFromMaterial(material: modelIOSubmesh.material!, modelIOMaterialSemantic: MDLMaterialSemantic.baseColor, modelIOMaterialType: MDLMaterialPropertyType.float3, metalKitTextureLoader: textureLoader)
		
		textures[TextureIndex.metallic.rawValue] = Submesh.createMetalTextureFromMaterial(material: modelIOSubmesh.material!, modelIOMaterialSemantic: MDLMaterialSemantic.metallic, modelIOMaterialType: MDLMaterialPropertyType.float3, metalKitTextureLoader: textureLoader)
		
		textures[TextureIndex.roughness.rawValue] = Submesh.createMetalTextureFromMaterial(material: modelIOSubmesh.material!, modelIOMaterialSemantic: MDLMaterialSemantic.roughness, modelIOMaterialType: MDLMaterialPropertyType.float3, metalKitTextureLoader: textureLoader)
		
		textures[TextureIndex.normal.rawValue] = Submesh.createMetalTextureFromMaterial(material: modelIOSubmesh.material!, modelIOMaterialSemantic: MDLMaterialSemantic.tangentSpaceNormal, modelIOMaterialType: MDLMaterialPropertyType.none, metalKitTextureLoader: textureLoader)
		
		textures[TextureIndex.ambientOcclusion.rawValue] = Submesh.createMetalTextureFromMaterial(material: modelIOSubmesh.material!, modelIOMaterialSemantic: MDLMaterialSemantic.ambientOcclusion, modelIOMaterialType: MDLMaterialPropertyType.none, metalKitTextureLoader: textureLoader)
		
		super.init()
	}
	
	// MARK: Texture
	
	/// Create a metal texture with the given semantic in the given Model I/O material object
	static private func createMetalTextureFromMaterial(material: MDLMaterial, modelIOMaterialSemantic materialSemantic: MDLMaterialSemantic, modelIOMaterialType defaultPropertyType: MDLMaterialPropertyType, metalKitTextureLoader textureLoader: MTKTextureLoader) -> MTLTexture? {
		
		var texture: MTLTexture?
		
		let propertiesWithSemantic = material.properties(with: materialSemantic)
		
		for property in propertiesWithSemantic {
			
			assert(property.semantic == materialSemantic);
			
			if property.type == MDLMaterialPropertyType.string {
				
				// Load our textures with TextureUsageShaderRead and StorageModePrivate
				let textureLoaderOptions = [
					MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
					MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
				]
				
				// First will interpret the string as a file path and attempt to load it with
				//    -[MTKTextureLoader newTextureWithContentsOfURL:options:error:]
				let textureURL = URL(string: "file://" + property.stringValue!)
				
				// Attempt to load the texture from the file system
				do {
					texture = try textureLoader.newTexture(URL: textureURL!, options: textureLoaderOptions)
				} catch {
					print("Unable to load texture. Error info: \(error)")
				}
				
				// If we found a texture using the string as a file path name...
				if texture != nil { continue }
				
				// If we did not find a texture by interpreting the URL as a path, we'll interpret
				//   the last component of the URL as an asset catalog name and attempt to load it
				//   with -[MTKTextureLoader newTextureWithName:scaleFactor:bundle:options::error:]
				
				let lastComponent = property.stringValue?.components(separatedBy: "/").last
				
				do {
					texture = try textureLoader.newTexture(name: lastComponent!, scaleFactor: 1, bundle: nil, options: textureLoaderOptions)
				} catch {
					print("Unable to load texture. Error info: \(error)")
				}
				// If we found a texture with the string in our asset catalog...
				if texture != nil { continue }
				
				// If we did not find the texture by interpreting the strung as a file path or as an
				//   asset name in our asset catalog, something went wrong (Perhaps the file was missing
				//   or  misnamed in the asset catalog, model/material file, or file system)
				
				// Depending on how the Metal render pipeline used with this submesh is implemented,
				//   this condition could be handled more gracefully.  The app could load a dummy texture
				//   that will look okay when set with the pipeline or ensure that the pipeline rendering
				//   this submesh does not require a material with this property.type.
				// TODO
			}
		}
		return texture
	}
	
	static private func mapTextureBindPointToFunctionConstantIndex(textureIndex: TextureIndex) -> FunctionConstant {
		switch (textureIndex) {
		case .baseColor:
			return .baseColorMapIndex
		case .normal:
			return .normalMapIndex
		case .metallic:
			return .metallicMapIndex
		case .ambientOcclusion:
			return .ambientOcclusionMapIndex
		case .roughness:
			return .roughnessMapIndex
		default: assert(false)
		}
	}
}

// MARK: - App specific mesh class containing vertex data describing the mesh and submesh object describing how to draw parts of the mesh
class Mesh: NSObject {
	
	// A MetalKit mesh containing vertex buffers describing the shape of the mesh
	var metalKitMesh: MTKMesh
	
	// An array of Submesh objects containing buffers and data with which we can make a draw call
	//  and material data to set in a Metal render command encoder for that draw call
	var submeshes: [Submesh?]
	
	/// Load the Model I/O mesh, including vertex data and submesh data which have index buffers and
	///   textures.  Also generate tangent and bitangent vertex attributes
	init?(modelIOMesh: MDLMesh, modelIOVertexDescriptor vertexDescriptor: MDLVertexDescriptor, metalKitTextureLoader textureLoader: MTKTextureLoader, metalDevice device: MTLDevice) {
		
		modelIOMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.2)
		
		// Have Model I/O create the tangents from mesh texture coordinates and normals
		modelIOMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
		
		// Have Model I/O create bitangents from mesh texture coordinates and the newly created tangents
		modelIOMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, tangentAttributeNamed: MDLVertexAttributeTangent, bitangentAttributeNamed: MDLVertexAttributeBitangent)
		
		// Apply the Model I/O vertex descriptor we created to match the Metal vertex descriptor.
		// Assigning a new vertex descriptor to a Model I/O mesh performs a re-layout of the vertex data.
		// In this case we created the Model I/O vertex descriptor so that the layout of the vertices in the Model I/O mesh match the layout of vertices our Metal render pipeline expects as input into its vertex shader
		// Note that we can only perform this re-layout operation after we have created tangents and bitangents (as we did above).
		// This is because Model I/O's addTangentBasis methods only work with vertex data is all in 32-bit floating-point.
		// The vertex descriptor we're applying changes some 32-bit floats into 16-bit floats or other types from which Model I/O cannot produce tangents
		modelIOMesh.vertexDescriptor = vertexDescriptor;
		
		// Create the metalKit mesh which will contain the Metal buffer(s) with the mesh's vertex data and submeshes with info to draw the mesh
		do {
			metalKitMesh = try MTKMesh(mesh: modelIOMesh, device: device)
		} catch {
			print("Unable to build MetalKit Mesh. Error info: \(error)")
			return nil
		}
		
		// Create an array to hold this Mesh object's Submesh objects
		submeshes = [Submesh?].init(repeating: nil, count: metalKitMesh.submeshes.count)
		
		// Create an AAPLSubmesh object for each submesh and a add it to our submeshes array
		for index in 0 ..< metalKitMesh.submeshes.count {
			// Create our own app specific submesh to hold the MetalKit submesh
			submeshes.append(Submesh(modelIOSubmesh: modelIOMesh.submeshes![index] as! MDLSubmesh, metalKitSubmesh: metalKitMesh.submeshes[index], metalKitTextureLoader: textureLoader))
		}
		
		super.init()
	}
	
	/// Traverses the Model I/O object hierarchy picking out Model I/O mesh objects and creating Metal vertex buffers, index buffers, and textures from them
	private func newMeshesFromObject(object: MDLObject, modelIOVertexDescriptor vertexDescriptor: MDLVertexDescriptor, metalKitTextureLoader textureLoader: MTKTextureLoader, metalDevice device: MTLDevice) -> [Mesh] {
		
		var newMeshes = [Mesh]()
		
		// If this Model I/O  object is a mesh object (not a camera, light, or something else)
		if let mesh = object as? MDLMesh {
			newMeshes.append(Mesh(modelIOMesh: mesh, modelIOVertexDescriptor: vertexDescriptor, metalKitTextureLoader: textureLoader, metalDevice: device)!)
		}
		
		// Recursively traverse the Model I/O asset hierarchy to find Model I/O meshes that are children of this Model I/O  object and create app-specific Mesh objects from those Model I/O meshes
		for child in object.children.objects {
			newMeshes.append(contentsOf: newMeshesFromObject(object: child, modelIOVertexDescriptor: vertexDescriptor, metalKitTextureLoader: textureLoader, metalDevice: device))
		}
		
		return newMeshes;
	}
	
	/// Uses Model I/O to load a model file at the given URL, create Model I/O vertex buffers, index buffers and textures, applying the given Model I/O vertex descriptor to re-layout vertex attribute data in the way that our Metal vertex shaders expect
	/// Constructs an array of meshes from the provided file URL, which indicate the location of a model file in a format supported by Model I/O, such as OBJ, ABC, or USD.
	/// the Model I/O vertex descriptor defines the layout Model I/O will use to arrange the vertex data while the bufferAllocator supplies allocations of Metal buffers to store vertex and index data
	func newMeshesFromURL(url: URL, modelIOVertexDescriptor vertexDescriptor: MDLVertexDescriptor, metalDevice device: MTLDevice) -> [Mesh] {
		
		// Create a MetalKit mesh buffer allocator so that Model I/O  will load mesh data directly into Metal buffers accessible by the GPU
		let bufferAllocator = MTKMeshBufferAllocator(device: device)
		
		// Use Model I/O to load the model file at the URL.
		// This returns a Model I/O asset object, which contains a hierarchy of Model I/O objects composing a "scene" described by the model file.
		// This hierarchy may include lights, cameras, but, most importantly, mesh and submesh data that we'll render with Metal
		let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: bufferAllocator)
		
		// Create a MetalKit texture loader to load material textures from files or the asset catalog into Metal textures
		let textureLoader = MTKTextureLoader(device: device)
		
		var newMeshes = [Mesh]()
		
		// Traverse the Model I/O asset hierarchy to find Model I/O meshes and create app-specific AAPLMesh objects from those Model I/O meshes
		for object in asset.childObjects(of: MDLMesh.self)
		{
			newMeshes.append(contentsOf: newMeshesFromObject(object: object, modelIOVertexDescriptor: vertexDescriptor, metalKitTextureLoader: textureLoader, metalDevice: device))
		}
		
		return newMeshes
	}
	
	
	static fileprivate func isTexturedProperty(propertyIndex: FunctionConstant, atQualityLevel quality: QualityLevel) -> Bool {
		var minLevelForProperty = QualityLevel.high
		
		switch(propertyIndex)
		{
		case .baseColorMapIndex, .irradianceMapIndex:
			minLevelForProperty = .medium;
		default: break
		}
		
		return quality.rawValue <= minLevelForProperty.rawValue
	}
	
	
}











