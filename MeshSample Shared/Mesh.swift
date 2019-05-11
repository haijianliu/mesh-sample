//
//  Mesh.swift
//  MeshSample
//
//  Created by haijian on 2019/05/11.
//  Copyright © 2019 haijian. All rights reserved.
//

import Metal
import MetalKit

// App specific submesh class containing data to draw a submesh
class Submesh: NSObject {
	
	// Sets the weight of values sampled from a texture vs a material uniform for a transition
	//   between levels.
	func computeTextureWeightsForQualityLevel(quality: QualityLevel, withGlobalMapWeight globalWeight: Float) {
		
	}
	
	// A MetalKit submesh mesh containing the primitive type, index buffer, and index count
	//   used to draw all or part of its parent Mesh object
	var metalKitSubmmesh: MTKSubmesh?
	
	// Material textures (indexed by TextureIndex) to set in the Metal Render Command Encoder
	//  before drawing the submesh.  Used for higher LODs
	var textures: [MTLTexture] = []
	
	// Material uniforms used instead of texture when rendering with lower LODs
	var materialUniforms: MTLBuffer?
	
	/// Create a metal texture with the given semantic in the given Model I/O material object
	private func createMetalTextureFromMaterial(material: MDLMaterial, modelIOMaterialSemantic materialSemantic: MDLMaterialSemantic, modelIOMaterialType defaultPropertyType: MDLMaterialPropertyType, metalKitTextureLoader textureLoader: MTKTextureLoader, materialUniform uniform: MaterialUniforms?) -> MTLTexture? {
		
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

// App specific mesh class containing vertex data describing the mesh and submesh object describing
//   how to draw parts of the mesh
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





