{-# LANGUAGE RecordWildCards, DeriveDataTypeable #-}

-- | Nix configuration
module Stack.Config.Nix
       (nixOptsFromMonoid
       ,StackNixException(..)
       ) where

import Control.Applicative
import Control.Monad (join, when)
import qualified Data.Text as T
import Data.Maybe
import Data.Typeable
import Distribution.System (OS (..))
import Stack.Types
import Control.Exception.Lifted
import Control.Monad.Catch (throwM,MonadCatch)
import Prelude

-- | Interprets NixOptsMonoid options.
nixOptsFromMonoid
    :: (Monad m, MonadCatch m)
    => Maybe Project
    -> NixOptsMonoid
    -> OS
    -> m NixOpts
nixOptsFromMonoid mproject NixOptsMonoid{..} os = do
    let nixEnable = fromMaybe nixMonoidDefaultEnable nixMonoidEnable
        defaultPure = case os of
          OSX -> False
          _ -> True
        nixPureShell = fromMaybe defaultPure nixMonoidPureShell
        nixPackages = fromMaybe [] nixMonoidPackages
        nixInitFile = nixMonoidInitFile
        nixShellOptions = fromMaybe [] nixMonoidShellOptions
                          ++ prefixAll (T.pack "-I") (fromMaybe [] nixMonoidPath)
        nixCompiler resolverOverride compilerOverride =
          let mresolver = resolverOverride <|> fmap projectResolver mproject
              mcompiler = compilerOverride <|> join (fmap projectCompiler mproject)
          in case (mresolver, mcompiler)  of
               (_, Just (GhcVersion v)) ->
                 T.filter (== '.') (versionText v)
               (Just (ResolverCompiler (GhcVersion v)), _) ->
                 T.filter (== '.') (versionText v)
               (Just (ResolverSnapshot (LTS x y)), _) ->
                 T.pack ("haskell.packages.lts-" ++ show x ++ "_" ++ show y ++ ".ghc")
               _ -> T.pack "ghc"
    when (not (null nixPackages) && isJust nixInitFile) $
       throwM NixCannotUseShellFileAndPackagesException
    return NixOpts{..}
  where prefixAll p (x:xs) = p : x : prefixAll p xs
        prefixAll _ _      = []

-- Exceptions thown specifically by Stack.Nix
data StackNixException
  = NixCannotUseShellFileAndPackagesException
    -- ^ Nix can't be given packages and a shell file at the same time
    deriving (Typeable)

instance Exception StackNixException

instance Show StackNixException where
  show NixCannotUseShellFileAndPackagesException =
    "You cannot have packages and a shell-file filled at the same time in your nix-shell configuration."
