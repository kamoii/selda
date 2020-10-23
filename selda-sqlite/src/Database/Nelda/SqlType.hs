{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Database.Nelda.SqlType
    ( module Database.Nelda.Backend.Types
    , module Database.Nelda.SqlTypeClass
    , module Database.Nelda.SqlTypeRep
    ) where

import Database.Nelda.Backend.Types
import Database.Nelda.SqlTypeClass
import Database.Nelda.SqlTypeRep
import Data.Text as Text (pack, replace)
import Data.Text (Text)
import Database.SQLite3

instance SqlType Int where
    type OriginSqlType Int = Int
    sqlTypeRep = TInteger
    toSqlParam i = SQLInteger $ fromIntegral i -- TODO: いいのか？
    fromSqlValue (SQLInteger i) = fromIntegral i  -- TODO: いいのか？
    toSqlExpression i = Text.pack $ show i

instance SqlType Text where
    type OriginSqlType Text = Text
    sqlTypeRep = TText
    toSqlParam t = SQLText t
    fromSqlValue (SQLText t) = t
    -- https://sqlite.org/lang_expr.html
    -- 3. Literal Values (Constants)
    --
    -- A string constant is formed by enclosing the string in single quotes (').
    -- A single quote within the string can be encoded by putting two single quotes in a row - as in Pascal.
    -- C-style escapes using the backslash character are not supported because they are not standard SQL.
    toSqlExpression t = "'" <> Text.replace "'" "''" t <> "'"

instance SqlType Double where
    type OriginSqlType Double = Double
    sqlTypeRep = TFloat
    toSqlParam d = SQLFloat d
    fromSqlValue (SQLFloat d) = d
    -- https://sqlite.org/lang_expr.html
    -- 3. Literal Values (Constants)
    --
    -- 複数のリテラル形式が取れる。取りあえず単純に show する
    toSqlExpression d = Text.pack $ show d

instance SqlType Bool where
    type OriginSqlType Bool = Bool
    sqlTypeRep = TBoolean
    toSqlParam b = SQLInteger $ if b then 1 else 0
    fromSqlValue (SQLInteger i) = not (i==0)
    -- https://sqlite.org/lang_expr.html
    -- 14. Boolean Expressions
    -- TRUE/FALSE 識別子は使えなくないが,互換性のため意味が変わる可能性がある。
    -- 単に 1/0 を使うのよさげ
    toSqlExpression b = if b then "1" else "0"
