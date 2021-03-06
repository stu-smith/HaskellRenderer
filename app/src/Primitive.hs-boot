-- Module for general primitives and intersections
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

module Primitive (primitiveBoundingRadius, 
                  primitiveClosestIntersect, 
                  primitiveAnyIntersect,
                  Object(Object), 
                  Primitive(Sphere, Plane, TriangleMesh, Box, SparseOctreeModel), 
                  primitive, 
                  material, 
                  makeQuad, 
		  makeTriangle,
		  makeTriangleWithTangents,
                  quadsToTriangles,
                  vertPosition, 
                  vertUV, 
                  vertTangentSpace, 
                  transform, 
                  radius,
                  triangles, 
                  getCentre, 
                  planeDistance, 
                  primitiveBoundingBox, 
                  objectListBoundingBox, 
                  intersectsBox, 
                  infinite, 
                  boundingBoxValid, 
                  sphereIntersect,
                  TangentSpace) where

import Ray
import Vector
import Material
import Matrix
import BoundingBox
import {-# SOURCE #-} SparseVoxelOctree

-- Triangle object used for triangle meshes
data Vertex = Vertex { vertPosition :: {-# UNPACK #-} !Position, 
                       vertUV :: {-# UNPACK #-} !Position, 
                       vertTangentSpace :: {-# UNPACK #-} !TangentSpace }
data Triangle = Triangle { vertices :: ![Vertex], plane :: !Primitive, halfPlanes :: ![Primitive] }

-- General object definition
data Object = Object { primitive :: Primitive,
                       material :: Material,
                       transform :: !Matrix}

-- Different kinds of primitives that an object can have
data Primitive = Sphere { radius :: {-# UNPACK #-} !Double }
               | Plane { planeTangentSpace :: {-# UNPACK #-} !TangentSpace, planeDistance :: {-# UNPACK #-} !Double }
               | TriangleMesh { triangles :: [Triangle] }
               | Box { bounds :: {-# UNPACK #-} !AABB } 
               | SparseOctreeModel { svo :: SparseOctree }

primitiveBoundingRadius :: Primitive -> Matrix -> Vector -> Double
primitiveBoundingBox :: Primitive -> Object -> Maybe AABB

primitiveClosestIntersect :: Primitive -> Ray -> Object -> Maybe (Double, TangentSpace)
primitiveAnyIntersect :: Primitive -> Ray -> Object -> Maybe (Double, TangentSpace)

makeQuad :: [Position] -> [Triangle]
makeTriangle :: Position -> Position -> Position -> Triangle
makeTriangleWithTangents :: Position -> Position -> Position -> Direction -> Direction -> Triangle
quadsToTriangles :: [Position] -> [Triangle]
getCentre :: Object -> Vector
objectListBoundingBox :: [Object] -> AABB
intersectsBox :: Primitive -> Matrix -> AABB -> Bool
infinite :: Primitive -> Bool
sphereIntersect :: Double -> Vector -> Ray -> Maybe Double
