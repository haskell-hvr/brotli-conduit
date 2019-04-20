{-# LANGUAGE Trustworthy #-}

-- |
-- Module      : Data.Conduit.Brotli
-- Copyright   : © 2016 Herbert Valerio Riedel
--
-- Maintainer  : hvr@gnu.org
--
-- Compression and decompression of data streams in the \"Brotli\" format (<https://tools.ietf.org/html/rfc7932 RFC7932>)
--
module Data.Conduit.Brotli
    ( -- * Simple interface
      compress
    , decompress

      -- * Extended interface
      -- ** Compression
    , compressWith

    , Brotli.defaultCompressParams
    , Brotli.CompressParams
    , Brotli.compressLevel
    , Brotli.compressWindowSize
    , Brotli.compressMode
    , Brotli.compressSizeHint
    , Brotli.CompressionLevel(..)
    , Brotli.CompressionWindowSize(..)
    , Brotli.CompressionMode(..)

      -- ** Decompression
    , decompressWith

    , Brotli.defaultDecompressParams
    , Brotli.DecompressParams
    , Brotli.decompressDisableRingBufferReallocation

    ) where

import qualified Codec.Compression.Brotli     as Brotli
import           Control.Applicative          as App
import           Control.Monad.IO.Class       (MonadIO (liftIO))
import           Control.Monad.Trans.Resource
import           Data.ByteString              (ByteString)
import qualified Data.ByteString              as B
import           Data.Conduit
import           Data.Conduit.List            (peek)

-- | Decompress a 'ByteString' from a compressed Brotli stream.
decompress :: (MonadThrow m, MonadIO m) => ConduitM ByteString ByteString m ()
decompress = decompressWith Brotli.defaultDecompressParams

-- | Like 'decompress' but with the ability to specify various decompression
-- parameters. Typical usage:
--
-- > decompressWith defaultDecompressParams { decompress... = ... }
decompressWith :: (MonadThrow m, MonadIO m) => Brotli.DecompressParams -> ConduitM ByteString ByteString m ()
decompressWith parms = do
    c <- peek
    case c of
      Nothing -> throwM $ userError $ "Data.Conduit.Brotli.decompress: invalid empty input"
      Just _  -> liftIO (Brotli.decompressIO parms) >>= go
  where
    go s@(Brotli.DecompressInputRequired more) = do
        mx <- await
        case mx of
          Just x
            | B.null x  -> go s -- ignore/skip empty bytestring chunks
            | otherwise -> liftIO (more x) >>= go
          Nothing       -> liftIO (more B.empty) >>= go
    go (Brotli.DecompressOutputAvailable output cont) = do
        yield output
        liftIO cont >>= go
    go (Brotli.DecompressStreamEnd rest) = do
        if B.null rest
          then App.pure ()
          else leftover rest
    go (Brotli.DecompressStreamError ecode) =
        throwM $ userError $ "Data.Conduit.Brotli.decompress: error (" ++ Brotli.showBrotliDecoderErrorCode ecode ++ ")"


-- | Compress a 'ByteString' into a Brotli container stream.
compress :: (MonadIO m) => ConduitM ByteString ByteString m ()
compress = compressWith Brotli.defaultCompressParams

-- | Like 'compress' but with the ability to specify various compression
-- parameters. Typical usage:
--
-- > compressWith defaultCompressParams { compress... = ... }
compressWith :: MonadIO m => Brotli.CompressParams -> ConduitM ByteString ByteString m ()
compressWith parms = do
    s <- liftIO (Brotli.compressIO parms)
    go s
  where
    go s@(Brotli.CompressInputRequired _flush more) = do
        mx <- await
        case mx of
          Just x
            | B.null x     -> go s -- ignore/skip empty bytestring chunks
            | otherwise    -> liftIO (more x) >>= go
          Nothing          -> liftIO (more B.empty) >>= go
    go (Brotli.CompressOutputAvailable output cont) = do
        yield output
        liftIO cont >>= go
    go Brotli.CompressStreamEnd = pure ()
