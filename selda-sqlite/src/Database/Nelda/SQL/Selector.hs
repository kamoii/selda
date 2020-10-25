{-# LANGUAGE TypeFamilies #-}
module Database.Nelda.SQL.Selector where

import Database.Nelda.Query.ResultRow (ResultRow)
import Database.Nelda.SqlType (SqlType)
import Database.Nelda.SQL.Row (Row(Many), Row)
import Database.Nelda.SQL.Col (Col(One), Col)
import Database.Nelda.SQL.Types (UntypedCol(Untyped))
import Unsafe.Coerce (unsafeCoerce)

-- | A column selector. Column selectors can be used together with the '!' and
--   'with' functions to get and set values on rows, or to specify
--   foreign keys.
newtype Selector t a = Selector {selectorIndex :: Int}

-- | A selector indicating the nth (zero-based) column of a table.
--
--   Will cause errors in queries during compilation, execution, or both,
--   unless handled with extreme care. You really shouldn't use it at all.
unsafeSelector :: (ResultRow t, SqlType a) => Int -> Selector t a
unsafeSelector = Selector

-- | Extract the given column from the given row.
-- TODO: coerce でいいかと思ったがコンパイルエラーになる。
(!) :: SqlType a => Row s t -> Selector t a -> Col s a
(Many xs) ! (Selector i) = case xs !! i of Untyped x -> One (unsafeCoerce x)
infixl 9 !

-- | Extract the given column from the given nullable row.
--   Nullable rows usually result from left joins.
--   If a nullable column is extracted from a nullable row, the resulting
--   nested @Maybe@s will be squashed into a single level of nesting.
(?) :: SqlType a => Row s (Maybe t) -> Selector t a -> Col s (CoalesceMaybe (Maybe a))
(Many xs) ? (Selector i) = case xs !! i of Untyped x -> One (unsafeCoerce x)
infixl 9 ?

-- | CoalesceMaybe nested nullable column into a single level of nesting.
type family CoalesceMaybe a where
    CoalesceMaybe (Maybe (Maybe a)) = CoalesceMaybe (Maybe a)
    CoalesceMaybe a                 = a
