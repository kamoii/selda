{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}

module Database.Nelda.SQL.Row where

import Database.Nelda.SQL.Nullability (Nullability)
import Database.Nelda.SQL.Types (UntypedCol)

-- | A database row. A row is a collection of one or more columns.
newtype Row s (n :: Nullability) a = Many [UntypedCol]
