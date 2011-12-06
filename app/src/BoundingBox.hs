-- Bounding box code
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE BangPatterns #-}

module BoundingBox where

import PolymorphicNum
import Vector
import GHC.Types
import GHC.Prim
import Matrix
import Misc
import Ray

type AABB = (Vector, Vector)

boundingBoxRadius :: AABB -> Double
boundingBoxRadius (boxMin, boxMax) = boxMin `distance` boxMax

boundingBoxCentre :: AABB -> Position
boundingBoxCentre (boxMin, boxMax) = (boxMin <+> boxMax) <*> (0.5 :: Double)

boundingBoxUnion :: AABB -> AABB -> AABB
boundingBoxUnion (min1, max1) (min2, max2) = (Vector.min min1 min2, Vector.max max1 max2)

boundingBoxValid :: AABB -> Bool
boundingBoxValid (boxMin, boxMax) = vecX boxMin <= vecX boxMax &&
                                    vecY boxMin <= vecY boxMax &&
                                    vecZ boxMin <= vecZ boxMax

boundingBoxOverlaps :: AABB -> AABB -> Bool
boundingBoxOverlaps box1 box2 = overlaps box1 box2 || overlaps box2 box1
    where
      overlaps (min1, max1) (min2, max2) = vecX min1 <= vecX max2 && (vecX max1 >= vecX min2) &&
                                           vecY min1 <= vecY max2 && (vecY max1 >= vecY min2) &&
                                           vecZ min1 <= vecZ max2 && (vecZ max1 >= vecZ min2)

-- Enlarge a bounding box to include a point
enlargeBoundingBox :: Position -> AABB -> AABB
enlargeBoundingBox pos(boxMin, boxMax) = (Vector.min boxMin pos, Vector.max boxMax pos)

-- Linearly scale a box
scaleBoundingBox :: AABB -> Double -> AABB
scaleBoundingBox (boxMin, boxMax) k = (setWTo1 $ boxMin <*> k, setWTo1 $ boxMax <*> k)

-- Give a bounding box a buffer of a certain distance all the way around
growBoundingBox :: AABB -> Double -> AABB
growBoundingBox (Vector x1 y1 z1 _, Vector x2 y2 z2 _) k = (Vector (x1 - k) (y1 - k) (z1 - k) 1, Vector (x2 + k) (y2 + k) (z2 + k) 1)

-- This is a dummy box that is used initially. If anything is intersected with it, it becomes valid. Else it is an invalid box that can be tested for
initialInvalidBox :: AABB
initialInvalidBox = (Vector bigNumber bigNumber bigNumber 1, Vector smallNumber smallNumber smallNumber 1)
    where
      bigNumber = 10000000
      smallNumber = -10000000

-- These functions are useful for finding the greatest or smallest part of a box relative to a normal
selectMinBoxComponent :: (Vector -> Double) -> Vector -> AABB -> Double
selectMinBoxComponent f norm (boxMin, boxMax) = if f norm > 0 then f boxMin else f boxMax

selectMaxBoxComponent :: (Vector -> Double) -> Vector -> AABB -> Double
selectMaxBoxComponent f norm (boxMin, boxMax) = if f norm > 0 then f boxMax else f boxMin

-- Does a box contain a point?
contains :: AABB -> Position -> Bool
{-# SPECIALIZE INLINE contains :: AABB -> Position -> Bool #-}
contains (Vector !(D# minX) !(D# minY) !(D# minZ) _, Vector !(D# maxX) !(D# maxY) !(D# maxZ) _) (Vector !(D# x) !(D# y) !(D# z) _) = 
    x >=## minX && x <=## maxX &&
    y >=## minY && y <=## maxY &&
    z >=## minZ && z <=## maxZ

overlapsSphere :: AABB -> Position -> Double -> Bool
overlapsSphere (boxMin, boxMax) p r = all insideInterval [vecX, vecY, vecZ]
    where 
      insideInterval f = f p >= (f boxMin - r) && f p <= (f boxMax + r)

intersectRayAABB :: AABB -> Ray -> Matrix -> Maybe Double
intersectRayAABB (bounds0, bounds1) (Ray rayOrg@(Vector ox oy oz _) rayDir@(Vector dx dy dz _) rayLen) _ -- TODO Need to transform ray by inverse object matrix
  | dx == 0 && (ox < vecX bounds0 || ox > vecX bounds1) = Nothing
  | dy == 0 && (oy < vecY bounds0 || oy > vecY bounds1) = Nothing
  | dz == 0 && (oz < vecZ bounds0 || oz > vecZ bounds1) = Nothing
  | otherwise = case tMinMax of
                     Nothing -> Nothing
                     Just (tmin, tmax) -> if tmin > tmax || 
                                             tmax < 0 || 
                                             tmin > rayLen then Nothing
                                          else Just tmin
  where
    intX = nearestSlabIntersection vecX
    intY = nearestSlabIntersection vecY
    intZ = nearestSlabIntersection vecZ
    tMinMax = maybePairFunctor Prelude.max Prelude.min intX (maybePairFunctor Prelude.max Prelude.min intY intZ)
    nearestSlabIntersection f
      | f rayDir == 0 = Nothing
      | t1 > t2 = Just (t2, t1)
      | otherwise = Just (t1, t2)
      where
        t1 = ((f bounds0) - (f rayOrg)) / (f rayDir)
        t2 = ((f bounds1) - (f rayOrg)) / (f rayDir)
