//
//  ShaderTypes.h
//  MeshSample Shared
//
//  Created by haijian on 2019/05/11.
//  Copyright © 2019 haijian. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
	BufferIndexMeshPositions = 0,
	BufferIndexMeshGenerics  = 1,
	BufferIndexUniforms      = 2
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
	VertexAttributePosition  = 0,
	VertexAttributeTexcoord  = 1,
};

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef NS_ENUM(NSInteger, TextureIndex)
{
	TextureIndexBaseColor    = 0,
	TextureIndexMetallic         = 1,
	TextureIndexRoughness        = 2,
	TextureIndexNormal           = 3,
	TextureIndexAmbientOcclusion = 4,
	TextureIndexIrradianceMap    = 5,
	TextureIndexNumMeshTextureIndices = TextureIndexAmbientOcclusion + 1,
};

typedef struct
{
	matrix_float4x4 projectionMatrix;
	matrix_float4x4 modelViewMatrix;
} Uniforms;

typedef NS_ENUM(NSInteger, QualityLevel)
{
	QualityLevelHigh   = 0,
	QualityLevelMedium = 1,
	QualityLevelLow    = 2,
	NumQualityLevels
};

typedef NS_ENUM(NSInteger, FunctionConstant)
{
	FunctionConstantBaseColorMapIndex,
	FunctionConstantNormalMapIndex,
	FunctionConstantMetallicMapIndex,
	FunctionConstantRoughnessMapIndex,
	FunctionConstantAmbientOcclusionMapIndex,
	FunctionConstantIrradianceMapIndex
};

typedef struct
{
	vector_float3 baseColor;
	vector_float3 irradiatedColor;
	vector_float3 roughness;
	vector_float3 metalness;
	float         ambientOcclusion;
	float         mapWeights[TextureIndexNumMeshTextureIndices];
} MaterialUniforms;


#endif /* ShaderTypes_h */



