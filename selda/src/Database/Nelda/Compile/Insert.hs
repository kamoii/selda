{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Database.Nelda.Compile.Insert where

import Database.Nelda.Types (Sql(..))
import Database.Nelda.Schema (Table(..), Column(..), ColumnNull(..), ColumnDefault(..), TableName(..))
import Database.Nelda.SqlType (SqlParam, SqlType(..))
import Database.Nelda.Compile.Schema (quoteTableName)

-- import qualified Database.Selda.Backend.PPConfig as PPConfig (ppMaxInsertParams)

import Data.Proxy (Proxy(..))
import Data.Maybe (catMaybes)
import Data.Function ((&))
import Data.Kind (Constraint)
import GHC.TypeLits (Symbol, TypeError, ErrorMessage(..))
import qualified Data.Text as Text
import JRec
import JRec.Internal (reflectRec, RecApply)

-- insert' は全フィールドを明示的に指定する必要がある
-- insert  は明示的な指定が必要なフィールドは省略でき,かつ安全に互換性ある型なら許容する。
-- 例えば挿入する場合だけなら Mabye Int の挿入型に対して Int を指定しても問題ない。
--
-- TODO: 各フィールドの検査する前にフィールド名によるソーティングしてもいいかも。
-- コンパイル時間は伸びるかもだが,実行時には影響与えない(実際ソートする必要ないので)

-- * Defaultable/AutoIncrement data type
--
-- Data type to specify columns which has explicit DEFAULT value or AUTO INCREMENT attribute.
-- いずれも Maybe 型と isomorphic だが semantics が異なるための別の型として定義している。
-- 現状 一つのカラムが explicit DEFAULT value と AUTO INCREMENT attribute を同時に持つことはないと仮定している。
-- つまり AutoIncrement (Defaultable Int) みたいなINSERT型はないはず(ToInsertRecordFieldの実装参照)。
-- そのため一つのデータ型で済むはずではあるが,性質を変えて扱いたい場合があるので別々に定義。
--
-- InsertableTable 型クラスを使う限り,ユーザがこれらの型を使うことは稀のはずである。
-- なので型名やコンストラクタが長ったらしくなってもまーいいかな。
--
-- TODO: 定義場所正しいのか？
-- TODO: Defaultable is an awful name..
data Defaultable a
    = UseDefault
    | IgnoreDefaultAndSpecify a
    deriving (Eq, Show)

data AutoIncrement a
    = TriggerAutoIncrement
    | IgnoreAutIncrementAndSpecify a
    deriving (Eq, Show)

-- * Compile functions

compileInsert
    :: InsertableTable (Table name cols) lts
    => Table name cols
    -> [Rec lts]
    -> [(Sql, [SqlParam])]
compileInsert _ [] =
    [ (mempty, []) ]
compileInsert table [row] =
    [ compileInsertSingle table row ]
compileInsert table rows =
    -- TODO: compileInsertBatch をちゃんと定義して使う
    map (compileInsertSingle table) rows

compileInsertSingle
    :: forall name cols a lts
    . InsertableTable (Table name cols) lts
    => Table name cols
    -> Rec lts
    -> (Sql, [SqlParam])
compileInsertSingle Table{tabName} row = unsafeCompileInsertSingle tabName colsAll
    where
      colsAll :: [(String, InsertSqlParam)]
      colsAll = reflectRec
          (Proxy :: Proxy ToInsretSqlParam)
          (\s v -> (s, _toInsretSqlParam v))
          row

-- * Compile functions(explicit)

compileInsert'
    :: InsertableTable' (Table name cols)
    => Table name cols
    -> [Rec (InsertRecordFields (Table name cols))]
    -> [(Sql, [SqlParam])]
compileInsert' _ [] =
    [ (mempty, []) ]
compileInsert' table [row] =
    [ compileInsertSingle' table row ]
compileInsert' table rows =
    -- TODO: compileInsertBatch をちゃんと定義して使う
    map (compileInsertSingle' table) rows

-- TODO: compileInsertSingle
-- TODO: なぜ Single と Batch で実装を分けているか説明(SQLite におけるDefault のせい)
compileInsertSingle'
    :: InsertableTable' (Table name cols)
    => Table name cols
    -> Rec (InsertRecordFields (Table name cols))
    -> (Sql, [SqlParam])
compileInsertSingle' Table{tabName} row = unsafeCompileInsertSingle tabName colsAll
    where
      colsAll :: [(String, InsertSqlParam)]
      colsAll = reflectRec
          (Proxy :: Proxy ToInsretSqlParam)
          (\s v -> (s, _toInsretSqlParam v))
          row

-- * Unsafe Compile(Singile)

unsafeCompileInsertSingle
    :: TableName name
    -> [(String, InsertSqlParam)]
    -> (Sql, [SqlParam])
unsafeCompileInsertSingle tabName colsAll = (sql, params)
    where
      -- TODO: Text ではなくて, SqlFragment のほうがいいかな?
      -- ただ SqlFragment もそこまで恩恵はないかな...
      sql = Sql $ Text.unwords
          [ "INSERT INTO"
          , quoteTableName tabName
          , "(" <>  Text.intercalate ", " names <> ")"
          , "VALUES"
          , "(" <>  Text.intercalate ", " placeholders <> ")"
          ]

      names = map (Text.pack . fst) colsWithParam
      params = map snd colsWithParam
      placeholders = zip [1..] colsWithParam & map (\(i, _) -> Text.pack ('$' : show (i :: Int)))

      colsWithParam :: [(String, SqlParam)]
      colsWithParam = catMaybes $ map (traverse toMaybe) colsAll

      toMaybe ISPUseDefault = Nothing
      toMaybe (ISPSqlParam p) = Just p

-- ** TODO: compileInsertBatch

-- compileInsert
--     :: ( fields ~ ToInsertRecordFields cols )
--     => Table name cols
--     -> [Rec fields]
--     -> [(Sql, [SqlParam])]
-- compileInsert _ [] =
--     [(mempty, [])]
-- compileInsert tbl rows =
--     case PPConfig.ppMaxInsertParams of
--         Nothing -> [_compileInsert tbl rows']
--         Just n  -> map (_compileInsert tbl) (chunk (n `div` rowlen) rows')
--   where
--     rows' = map params rows
--     rowlen = length (head rows')
--     chunk chunksize xs =
--         case splitAt chunksize xs of
--             ([], []) -> []
--             (x, [])  -> [x]
--             (x, xs') -> x : chunk chunksize xs'
--
-- _compileInsert
--     :: Table name cols
--     -> [[Either Param Param]]
--     -> (Sql, [SqlParam])
-- _compileInsert = undefined
-- * InsertableTable' type class/instance
--
-- Table created by table functions should always satisfiy InsertableTable' constraint.
-- InsertRecordFields type family で table に insert可能な完全な field list が得られる。
-- キモは ToInsertRecordField type family で,各フィールドの挿入型を決めている。

class
    ( RecApply (InsertRecordFields table) (InsertRecordFields table) ToInsretSqlParam
    ) => InsertableTable' table where
    type InsertRecordFields table :: [*]

instance
    ( RecApply (InsertRecordFields (Table name cols)) (InsertRecordFields (Table name cols)) ToInsretSqlParam
    ) => InsertableTable' (Table name cols) where
    type InsertRecordFields (Table name cols) = ToInsertRecordFields cols

type family ToInsertRecordFields columns :: [*] where
    ToInsertRecordFields '[] = '[]
    ToInsertRecordFields (column ': cs) = (ToInsertRecordField column ': ToInsertRecordFields cs)

type family ToInsertRecordField column :: * where
    ToInsertRecordField (Column name _ sqlType nullabilty default_ _) =
        name := InsertTypeColumnDefaultWrapping default_ (InsertTypeColumnNullWrapping nullabilty sqlType)

type family InsertTypeColumnNullWrapping (nullabilty :: ColumnNull) (target :: *) :: * where
    InsertTypeColumnNullWrapping 'NotNull t = t
    InsertTypeColumnNullWrapping 'Nullable t = Maybe t
    InsertTypeColumnNullWrapping 'ImplicitNotNull t = t

type family InsertTypeColumnDefaultWrapping (default_ :: ColumnDefault) (target :: *) :: * where
    InsertTypeColumnDefaultWrapping 'NoDefault t = t
    InsertTypeColumnDefaultWrapping 'AutoIncrement t = AutoIncrement t
    InsertTypeColumnDefaultWrapping 'ExplicitDefault t = Defaultable t
    InsertTypeColumnDefaultWrapping 'ImplicitAutoIncrement t = AutoIncrement t

-- * InsertableTable type class/instance
--
-- InsertableTable' 型クラスは InsertRecordFields 型族で"完全な" field list を得る。
-- 各フィールドの型の外側が AutoIncrement, Defaultable や Maybe のものは実際は INSERT SQL上指定する必要はない。
-- (外側が Maybe ということは NULL 許容かつDEFAULT値が指定されていないので,DEFAUTL は NULL になっているはず)。
--
-- また外側が AutoIncrement, Defaultable や Maybe であっても内側の型で指定しても問題ないはずである。
-- つまり Mabye st, Defaultable st は st 型であっても問題なく,
-- Defaultable (Maybe st) は Maybe st/Defaultable st/st 型であっても問題ないはずである。
-- ただし AutoIncrement の場合は通常プライマリキーで使われるカラムであり,誤って指定しないよう,
-- AutoIncrement の外側は残す(ただし AutoIncrement (Maybe a) の挿入型に対して AutoIncrement a は許容する)。
--
-- JRec の fromNative サポートも付けてみたが,これはやりすぎかも。
-- Generic a, FromNative (Rep a) lts 制約で失敗した時のエラーメッセージが多分分かりづらい。
-- 分かりづらそうなら compileFromNative みたいな関数に分けるべきかな。
--
-- あー, OverloadedString と Num type class に弱いな..
-- "foo" や 23 を使うと AsseptableInsertType 適用する際に target のフィールド型が定まらないから,
-- Ambiguous type variable エラーが出てしまう(型注釈付けることで解決するけど微妙だな...)
--
-- e.g. Rec (#name := "Kobayashi", #age := 23, #pet := Just Dragon)
--
-- Ambiguous type variable ‘v2'0’ arising from the literal ‘23’
-- prevents the constraint ‘(Num v2'0)’ from being solved.

-- (1) table関数で作成した table ならこの制約は満たすはず
-- (2) Rec lts を [InsertSqlParam] に変換すのに必要
class
    ( InsertableTable' table            -- (1)
    , RecSub (InsertRecordFields table) lts
    , RecApply lts lts ToInsretSqlParam -- (2)
    ) => InsertableTable table (lts :: [*])

instance
    ( InsertableTable' table
    , RecSub (InsertRecordFields table) lts
    , RecApply lts lts ToInsretSqlParam
    ) => InsertableTable table lts

-- ** RecSub
--
-- subLts が superLts のサブセットになっており かつ共通フィールドの型が制約を満たすもの。
-- エラーメッセージを向上させるためにフィールドの型をチェックする制約にはフィールド名を渡している。
-- サブセットと言っても順序はあっている必要がある。
--

type family RecSub (superLts :: [*]) (subLts :: [*]) :: Constraint where
    RecSub (name  := super ': lts0) (name := sub ': lts1) = (AsseptableInsertType name super sub, RecSub lts0 lts1)
    RecSub (name' := super ': lts0) subLts                = (SkippableInsertType name' super, RecSub lts0 subLts)
    RecSub '[]                      (name := sub ': lts1) = TypeError (ErrorMessageLeftOver name sub)
    RecSub '[]                      '[]                   = ()

type ErrorMessageLeftOver name type_ =
    'Text "Column doesn't exist in table: \""
    ':<>: 'Text name
    ':<>: 'Text "\" :: " ':<>: 'ShowType type_ ':<>: 'Text ". "
    ':$$: ErrorMessageStrictOrderingWarn

type ErrorMessageStrictOrderingWarn =
    'Text "Or there is a possibility that the cause of this error is the order of fields."
    ':$$: 'Text "You can exclude NULLABLE/DEFAULT/AUTO INCREMENT columns, but the remaining columns and corresponding fields of inserting data must match."
    ':$$: 'Text "TODO: Explain why such limit exits."

-- ** AsseptableInsertType

type family AsseptableInsertType (name :: Symbol) (origin :: *) (target :: *) :: Constraint where
    AsseptableInsertType _    Int                       Int               = ()
    AsseptableInsertType _    a                         a                 = ()
    AsseptableInsertType _    (Maybe a)                 a                 = ()
    AsseptableInsertType _    (Defaultable a)           a                 = ()
    AsseptableInsertType _    (Defaultable (Maybe a))   a                 = ()
    AsseptableInsertType _    (Defaultable (Maybe a))   (Defaultable a)   = ()
    AsseptableInsertType _    (AutoIncrement (Maybe a)) (AutoIncrement a) = ()
    -- 意図的に以下は外している
    -- AsseptableInsertType _    (AutoIncrement a) a  = ()  --
    AsseptableInsertType name origin                    target            = TypeError ('Text "ouch")

-- ** SkippableInsertType

type family SkippableInsertType (name :: Symbol) (type_ :: *) :: Constraint where
    SkippableInsertType _    (Maybe _)         = ()
    SkippableInsertType _    (Defaultable _)   = ()
    SkippableInsertType _    (AutoIncrement _) = ()
    SkippableInsertType name type_             = TypeError (ErrorMessageColumnExcluded name type_)

type ErrorMessageColumnExcluded name type_ =
    'Text "Can't exclude column: \""
    ':<>: 'Text name
    ':<>: 'Text "\" :: " ':<>: 'ShowType type_ ':<>: 'Text ". "
    ':$$: 'Text "It's a Non-NULL column which neither have explicit DEFAULT or AUTO INCREMENT attribute."
    ':$$: ErrorMessageStrictOrderingWarn

-- * ToInsretSqlParam type class/instance: JRec record field to InsertSqlParam
--
-- InsertSqlParam に変換する際は DEFAULT も AUTO INCREMENT も一緒くたに扱っている。
-- TODO: これは別個にする必要があるかも

data InsertSqlParam
    = ISPUseDefault
    | ISPSqlParam SqlParam

class ToInsretSqlParam v where
    _toInsretSqlParam :: v -> InsertSqlParam

instance SqlType a => ToInsretSqlParam (Defaultable a) where
    _toInsretSqlParam UseDefault = ISPUseDefault
    _toInsretSqlParam (IgnoreDefaultAndSpecify v) = ISPSqlParam $ toSqlParam v

instance SqlType a => ToInsretSqlParam (AutoIncrement a) where
    _toInsretSqlParam TriggerAutoIncrement = ISPUseDefault
    _toInsretSqlParam (IgnoreAutIncrementAndSpecify v) = ISPSqlParam $ toSqlParam v

instance {-# OVERLAPPABLE #-} SqlType v => ToInsretSqlParam v where
    _toInsretSqlParam = ISPSqlParam . toSqlParam
