-- Just some built-in test scenes for debugging purposes

module TestScenes where

import Colour
import Light
import SparseVoxelOctree
import Vector
import BoundingBox
import Primitive
import Matrix
import Material
import Camera

-- A simple function to build an SVO. This just works off containment in a sphere
buildSVOSphere :: Position -> Double -> AABB -> Double
buildSVOSphere pos r box 
  | overlapsSphere box pos r = 1
  | otherwise = 0
  
testSvo :: SparseOctree
testSvo = build (buildSVOSphere (Vector 250 250 300 1) 100) (Vector 140 140 190 1, Vector 360 360 410 1) maxRecursion minDimension
  where
    maxRecursion = 10
    minDimension = 5

svoTestScene :: [Object]
svoTestScene = [Object (SparseOctreeModel testSvo) defaultMaterial identity]

svoLeafBoxes :: [Object]
svoLeafBoxes = map (\x -> Object (Box x) defaultMaterial identity) (enumerateLeafBoxes testSvo)

boxTestScene :: [Object]
boxTestScene = [Object (Box (Vector (-50) (-50) (-50) 0, Vector 50 50 50 0)) defaultMaterial identity]

testSceneCamera :: Camera
testSceneCamera = withVectors (Vector 0 0 (-400.0) 1.0) xaxis yaxis zaxis 45.0 10000

testSceneLights :: [Light]
testSceneLights = [ 
    QuadLight (CommonLightData (Colour 500 500 500 0) True) (Vector 0.0 200.0 (-300.0) 1.0) 1000 (Vector 1000.0 0.0 0.0 0.0) (Vector 0.0 0.0 1000.0 0.0)
    ]
