-- Various assorted bits and pieces

module Misc where

degreesToRadians :: Float -> Float
degreesToRadians x = x * pi / 180

xor :: Bool -> Bool -> Bool
xor True a = not a
xor False a = a

--fst :: (x, y, z) -> x
--fst (a, _, _) = a

--snd :: (x, y, z) -> y
--snd (_, b, _) = b

thr :: (x, y, z) -> z
thr (_, _, c) = c

-- Little helper for saturation
saturate :: (Num t, Ord t) => t -> t
saturate x = Prelude.max 0 (Prelude.min x 1)