-- Photon mapping
{-# LANGUAGE BangPatterns #-}

module PhotonMap(buildPhotonMap, PhotonMap(photonList), irradiance, PhotonMapContext(PhotonMapContext)) where

import {-# SOURCE #-} Light hiding (position)
import Vector
import Distribution
import Material
import Colour
import Random
import SceneGraph
import RayTrace
import Ray hiding (direction)
import Primitive
import Control.Monad.State
import BoundingBox
import KDTree
import Debug.Trace
import Misc
import Control.Parallel.Strategies
import Data.Heap

type GeneratorState = State StdGen

data PhotonMapContext = PhotonMapContext {
      photonGatherDistance :: Float,
      maxGatherPhotons :: Int,
      coneFilterK :: Float }

data Photon = Photon { power :: !Colour, posDir :: !(Position, Direction) } deriving (Show, Read, Eq, Ord)

data PhotonMapTree = PhotonMapNode Int Float PhotonMapTree PhotonMapTree
                   | PhotonMapLeaf (Maybe Photon) deriving (Show, Read, Eq)

data PhotonMap = PhotonMap { photonList :: [Photon],
                             photonMapTree :: PhotonMapTree } deriving(Show, Read, Eq)

data PhotonChoice = DiffuseReflect | SpecularReflect | Absorb

-- Generate a list of photon position and direction tuples to emit
-- I zip up each pos,dir tuple with a random number generator to give each photon a different sequence of random values
-- Helps parallelisation...
emitPhotons :: Light -> Int -> [(Position, Direction, StdGen)]
emitPhotons (PointLight !pos _ _ True) !numPhotons = zipWith (\dir num -> (pos, dir, mkStdGen num)) (generatePointsOnSphere numPhotons 1) [1..numPhotons]
emitPhotons (QuadLight !corner !du !dv _) !numPhotons = zipWith3 (\pos dir num -> (pos, dir, mkStdGen num)) randomPoints randomDirs [1..numPhotons]
    where
      randomPoints = generatePointsOnQuad corner du dv numPhotons
      randomDirs = generatePointsOnSphere numPhotons 1
emitPhotons _ _ = []

-- Compute russian roulette coefficients
russianRouletteCoefficients :: Material -> (Float, Float)
russianRouletteCoefficients !mat = (diffuseP, specularP)
    where
      (Colour diffuseR diffuseG diffuseB _) = Material.diffuse mat
      (Colour specularR specularG specularB _) = Material.specular mat
      diffuseP = (diffuseR + diffuseG + diffuseB) / 3
      specularP = (specularR + specularG + specularB) / 3

-- Decide what to do with a photon
choosePhotonFate :: (Float, Float) -> GeneratorState PhotonChoice
choosePhotonFate !(diffuseP, specularP) = do
  generator <- get
  let (p, newGenerator) = randomR (0.0::Float, 1.0::Float) generator
  let result | p < diffuseP = DiffuseReflect
             | p < (diffuseP + specularP) = SpecularReflect
             | otherwise = Absorb
      -- | bounce >= maxBounces = trace "Hit max bounces forcing absorb" Absorb
  put newGenerator
  return result

-- Compute new power for a photon
computeNewPhotonPower :: PhotonChoice -> (Float, Float) -> Colour -> Material -> Colour
computeNewPhotonPower !fate !(diffuseP, specularP) photonPower !mat = case fate of
                                                                        DiffuseReflect -> photonPower * diffuse mat Colour.</> diffuseP
                                                                        SpecularReflect -> photonPower * specular mat Colour.</> specularP
                                                                        Absorb -> colBlack

-- Compute a new diffuse reflection in spherical co-ordinates
generateUV :: GeneratorState (Float, Float)
generateUV = do generator <- get
                let (u, newGenerator) = randomR (0.0::Float, 1.0::Float) generator
                let (v, newGenerator') = randomR (0.0::Float, 1.0::Float) newGenerator
                put newGenerator'
                return (u, v)

-- Find a diffuse reflection direction in the hemisphere of the normal
-- Realistic Image Synthesis Using Photon Mapping - Eq 2.24
diffuseReflectionDirection :: StdGen -> TangentSpace -> (Direction, StdGen)
diffuseReflectionDirection !stdGen !tanSpace = (transformDir dir tanSpace, stdGen')
    where
      ((u, v), stdGen') = runState generateUV stdGen
      theta = acos (sqrt u)
      phi = 2 * pi * v
      dir = sphericalToDirection (theta, phi)

-- Main working photon tracing function
tracePhoton :: [Photon] -> Photon -> SceneGraph -> StdGen -> (Int, Int) -> [Photon]
tracePhoton !currentPhotons (Photon !photonPower !photonPosDir) sceneGraph !rndState !(bounce, maxBounces) = 
    -- See if the photon intersects any surfaces
    case findNearestIntersection sceneGraph ray of
      Nothing -> currentPhotons
      Just (obj, t, subId) -> case photonFate of
                                -- Diffuse reflection. Here, we store the photon that got reflected, and trace a new photon - but only if it's bright enough to be worthwhile
                                DiffuseReflect -> if Colour.magnitude newPhotonPower > brightnessEpsilon && (bounce + 1) <= maxBounces
                                                  then tracePhoton (storedPhoton : currentPhotons) reflectedPhoton sceneGraph rndState'' (bounce + 1, maxBounces)
                                                  else storedPhoton : currentPhotons
                                    where
                                      !reflectedPhoton = Photon newPhotonPower (surfacePos, reflectedDir)
                                      !(reflectedDir, rndState'') = diffuseReflectionDirection rndState' tanSpace

                                -- Specular reflection. Here, we reflect the photon in the fashion that the surface would reflect towards the viewer and
                                -- aim to absorb it somewhere else in the photon map
                                SpecularReflect -> if Colour.magnitude newPhotonPower > brightnessEpsilon && (bounce + 1) <= maxBounces
                                                   then tracePhoton currentPhotons reflectedPhoton sceneGraph rndState' (bounce + 1, maxBounces)
                                                   else currentPhotons
                                    where
                                      !reflectedPhoton = Photon newPhotonPower (surfacePos, reflectedDir)
                                      !reflectedDir = Vector.negate (snd photonPosDir) `reflect` normal

                                -- Absorb. The photon simply gets absorbed into the map
                                Absorb -> storedPhoton : currentPhotons
          where
            !(photonFate, rndState') = runState (choosePhotonFate coefficients) rndState
            coefficients = russianRouletteCoefficients (material obj)
            !newPhotonPower = computeNewPhotonPower photonFate coefficients photonPower (material obj)
            !tanSpace = primitiveTangentSpace (primitive obj) subId hitPosition obj
            !normal = thr tanSpace
            !hitPosition = pointAlongRay ray t
            !surfacePos = hitPosition + (normal Vector.<*> surfaceEpsilon)
            !brightnessEpsilon = 0.1
            storedPhoton = Photon photonPower (surfacePos, snd photonPosDir)
    where
      !ray = rayWithPosDir photonPosDir 10000

-- Trace a list of photos and produce a list of the resulting photon interactions
tracePhotons :: Light -> SceneGraph -> [(Position, Direction, StdGen)] -> [Photon]
tracePhotons !light sceneGraph !posDirsGens = concat (map (\(pos, dir, rndState) -> tracePhoton [] (Photon (colour light Colour.<*> fluxPerPhotonScaler) (pos, dir)) sceneGraph rndState (0, maxBounces)) posDirsGens `using` parListChunk 256 rseq)
    where
      fluxPerPhotonScaler = 1.0 / fromIntegral (length posDirsGens)
      maxBounces = 5

-- Build a list of photons for a light source
tracePhotonsForLight :: Int -> SceneGraph -> Light -> [Photon]
tracePhotonsForLight !numPhotons sceneGraph !light = tracePhotons light sceneGraph (emitPhotons light numPhotons)

-- High-level function to build a photon map
buildPhotonMap :: SceneGraph -> [Light] -> Int -> PhotonMap
buildPhotonMap sceneGraph lights numPhotonsPerLight = PhotonMap photons (buildKDTree photons)
    where
      photons = foldr ((++) . tracePhotonsForLight numPhotonsPerLight sceneGraph) [] lights

-- Make a bounding box of a list of photons
photonsBoundingBox :: [Photon] -> AABB
photonsBoundingBox = foldr (enlargeBoundingBox .fst . posDir) initialInvalidBox

-- Construct a balanced kd tree of photons
buildKDTree :: [Photon] -> PhotonMapTree
buildKDTree photons
    | length photons == 1 = PhotonMapLeaf (Just $ head photons)
    | length photons == 2 = let photon0 : photon1 : [] = photons
                                position0 = (fst . posDir) photon0
                                position1 = (fst . posDir) photon1
                                axis = largestAxis (position0 - position1)
                                midPoint = component ((position0 + position1) Vector.<*> 0.5) axis
                            in if component position0 axis > component position1 axis
                               then PhotonMapNode axis midPoint (buildKDTree [photon0]) (buildKDTree [photon1])
                               else PhotonMapNode axis midPoint (buildKDTree [photon1]) (buildKDTree [photon0])
    | length photons > 2 = let (boxMin, boxMax) = photonsBoundingBox photons
                               axis = largestAxis (boxMax - boxMin)
                               photonsMedian = foldr ((+) . fst . posDir) zeroVector photons Vector.</> fromIntegral (length photons)
                               value = component photonsMedian axis
                               photonsGT = Prelude.filter (\x -> component ((fst . posDir) x) axis > value) photons
                               photonsLE = Prelude.filter (\x -> component ((fst . posDir) x) axis <= value) photons
                           in if length photonsGT > 0 && length photonsLE > 0
                              then PhotonMapNode axis value (buildKDTree photonsGT) (buildKDTree photonsLE)
                              else let (photons0', photons1') = trace "Using degenerate case" $ degenerateSplitList photons in PhotonMapNode axis value (buildKDTree photons0') (buildKDTree photons1')
    | Prelude.null photons = PhotonMapLeaf Nothing
    | otherwise = error ("Invalid case, length of array is " ++ show (length photons) ++ "\n")

data GatheredPhoton = GatheredPhoton Float Photon
type PhotonHeap = MaxHeap GatheredPhoton

instance Ord GatheredPhoton where
    compare (GatheredPhoton dist1 _) (GatheredPhoton dist2 _)
        | dist1 == dist2 = EQ
        | dist1 <= dist2 = LT
        | otherwise = GT

instance Eq GatheredPhoton where
    (GatheredPhoton dist1 _) == (GatheredPhoton dist2 _) = dist1 == dist2

{-
    x <= y =  compare x y /= GT
    x <  y =  compare x y == LT
    x >= y =  compare x y /= LT
    x >  y =  compare x y == GT
    max x y 
         | x >= y    =  x
         | otherwise =  y
    min x y
         | x <  y    =  x
         | otherwise =  y
-}

-- Gather photons into a list for irradiance computations
gatherPhotons :: PhotonMapTree -> Position -> Float -> PhotonHeap -> Int -> PhotonHeap
gatherPhotons (PhotonMapNode !axis !value gtChild leChild) !pos !r !photonHeap !maxPhotons
    | abs (value - posComponent) <= r = let newHeap = union (gatherPhotons gtChild pos r photonHeap maxPhotons) (gatherPhotons leChild pos r photonHeap maxPhotons)
                                        in if size newHeap > maxPhotons
                                           then Data.Heap.drop (size newHeap - maxPhotons) newHeap
                                           else newHeap
    | posComponent > value = gatherPhotons gtChild pos r photonHeap maxPhotons
    | posComponent <= value = gatherPhotons leChild pos r photonHeap maxPhotons
    | otherwise = error "gatherPhotons: Errr.. unexplained/unexpected case here"
    where
      posComponent = component pos axis
gatherPhotons (PhotonMapLeaf (Just !p)) !pos !r !photonHeap !maxPhotons
    | distSq < (r * r) = let newHeap = insert (GatheredPhoton distSq p) photonHeap
                         in if size newHeap > maxPhotons 
                            then Data.Heap.drop 1 newHeap 
                            else newHeap
    | otherwise = photonHeap
    where distSq = pos `distanceSq` (fst . posDir) p
gatherPhotons (PhotonMapLeaf Nothing) _ _ !photonHeap !maxPhotons = photonHeap

photonContribution :: Float -> (Position, TangentSpace) -> Photon -> Colour
photonContribution !kr !(pos, (_, _, normal)) !photon = power photon Colour.<*> (Vector.negate normal `sdot3` (snd . posDir) photon) Colour.<*> weight
    where
      !weight = 1 - (pos `distance` (fst . posDir) photon) / (kr + 0.000000001)

sumPhotonContribution :: Float -> Float -> (Position, TangentSpace) -> [Photon] -> Colour
sumPhotonContribution !r !k !posTanSpace !photons = foldr ((+) .photonContribution (k * r) posTanSpace) colBlack photons Colour.<*> (1.0 / ((1.0 - 2.0 / (3.0 * k)) * pi * r * r))

-- Look up the resulting irradiance from the photon map at a given point
-- Realistic Image Synthesis Using Photon Mapping, e7.6
irradiance :: PhotonMap -> (Position, TangentSpace) -> PhotonMapContext -> Material -> Colour
irradiance photonMap !posTanSpace !photonMapContext !mat = sumPhotonContribution r k posTanSpace gatheredPhotons * diffuse mat
    where
      !r = photonGatherDistance photonMapContext
      !maxPhotons = maxGatherPhotons photonMapContext
      !k = coneFilterK photonMapContext
      !gatheredPhotons = map (\(GatheredPhoton _ photon) -> photon) (Data.Heap.take maxPhotons (gatherPhotons (photonMapTree photonMap) (fst posTanSpace) r Data.Heap.empty maxPhotons))