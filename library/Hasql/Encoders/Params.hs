module Hasql.Encoders.Params where

import qualified Database.PostgreSQL.LibPQ as A
import qualified Hasql.Encoders.Value as C
import qualified Hasql.PTI as D
import Hasql.Prelude
import qualified PostgreSQL.Binary.Encoding as B
import qualified Text.Builder as E

-- |
-- Encoder of some representation of a parameters product.
data Params a = Params
  { size :: !Int,
    columnsMetadata :: !(DList (A.Oid, A.Format)),
    serializer :: Bool -> a -> DList (Maybe ByteString),
    printer :: a -> DList Text
  }

instance Contravariant Params where
  contramap fn (Params size columnsMetadata oldSerializer oldPrinter) = Params {..}
    where
      serializer idt = oldSerializer idt . fn
      printer = oldPrinter . fn

instance Divisible Params where
  divide
    divisor
    (Params leftSize leftColumnsMetadata leftSerializer leftPrinter)
    (Params rightSize rightColumnsMetadata rightSerializer rightPrinter) =
      Params
        { size = leftSize + rightSize,
          columnsMetadata = leftColumnsMetadata <> rightColumnsMetadata,
          serializer = \idt input -> case divisor input of
            (leftInput, rightInput) -> leftSerializer idt leftInput <> rightSerializer idt rightInput,
          printer = \input -> case divisor input of
            (leftInput, rightInput) -> leftPrinter leftInput <> rightPrinter rightInput
        }
  conquer =
    Params
      { size = 0,
        columnsMetadata = mempty,
        serializer = mempty,
        printer = mempty
      }

instance Semigroup (Params a) where
  Params leftSize leftColumnsMetadata leftSerializer leftPrinter <> Params rightSize rightColumnsMetadata rightSerializer rightPrinter =
    Params
      { size = leftSize + rightSize,
        columnsMetadata = leftColumnsMetadata <> rightColumnsMetadata,
        serializer = \idt input -> leftSerializer idt input <> rightSerializer idt input,
        printer = \input -> leftPrinter input <> rightPrinter input
      }

instance Monoid (Params a) where
  mempty = conquer

value :: C.Value a -> Params a
value (C.Value valueOID _ serialize print) =
  Params
    { size = 1,
      columnsMetadata = pure (pqOid, format),
      serializer = \idt -> pure . Just . B.encodingBytes . serialize idt,
      printer = pure . E.run . print
    }
  where
    D.OID _ pqOid format = valueOID

nullableValue :: C.Value a -> Params (Maybe a)
nullableValue (C.Value valueOID _ serialize print) =
  Params
    { size = 1,
      columnsMetadata = pure (pqOid, format),
      serializer = \idt -> pure . fmap (B.encodingBytes . serialize idt),
      printer = pure . maybe "null" (E.run . print)
    }
  where
    D.OID _ pqOid format = valueOID
