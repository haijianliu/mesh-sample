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
}

// MARK: - App specific mesh class containing vertex data describing the mesh and submesh object describing how to draw parts of the mesh
class Mesh: NSObject {
	
	// Constructs an array of meshes from the provided file URL, which indicate the location of a model
	//  file in a format supported by Model I/O, such as OBJ, ABC, or USD.  the Model I/O vertex
	//  descriptor defines the layout Model I/O will use to arrange the vertex data while the
	//  bufferAllocator supplies allocations of Metal buffers to store vertex and index data
	func newMeshesFromURL(url: NSURL, modelIOVertexDescriptor vertexDescriptor: MDLVertexDescriptor, metalDevice device: MTLDevice, error: NSError) -> [Mesh] {
		return []
	}
	
	func isTexturedProperty(propertyIndex: FunctionConstant, atQualityLevel quality: QualityLevel) -> Bool {
		return false
	}
	
	// A MetalKit mesh containing vertex buffers describing the shape of the mesh
	var metalKitMesh: MTKMesh?
	
	// An array of Submesh objects containing buffers and data with which we can make a draw call
	//  and material data to set in a Metal render command encoder for that draw call
	var submeshes: [Submesh] = []
}






