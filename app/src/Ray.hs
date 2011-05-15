-- Module for handling rays in a raytracer
{-# LANGUAGE BangPatterns #-}

module Ray where

import Vector

-- For now, we're sticking to Floats
data Ray = Ray { origin :: {-# UNPACK #-} !Position, direction :: {-# UNPACK #-} !Direction, rayLength :: {-# UNPACK #-} !Float }

-- Make a ray given the start and end position
rayWithPoints :: Position -> Position -> Ray
rayWithPoints !start !end = Ray start (normalise (end - start)) (end `distance` start)

rayWithDirection :: Position -> Direction -> Float -> Ray
rayWithDirection !start !dir !rayLen = Ray start dir rayLen

rayWithPosDir :: (Position, Direction) -> Float -> Ray
rayWithPosDir !(start, dir) !rayLen = Ray start dir rayLen

-- Given a ray and a distance, produce the point along the ray
pointAlongRay :: Ray -> Float -> Position
pointAlongRay (Ray !org !dir _) !dist = madd org dir dist

-- Given some intercept, work out if it is valid, for this ray
validIntercept :: Ray -> Float -> Bool
validIntercept (Ray _ _ !rayLen) !t = t >= 0 && t <= rayLen

-- Make a shorter version of the same ray
shortenRay :: Ray -> Float -> Ray
shortenRay (Ray !org !dir _) !newLength = Ray org dir newLength