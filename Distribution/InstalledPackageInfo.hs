-----------------------------------------------------------------------------
-- |
-- Module      :  Distribution.InstalledPackageInfo
-- Copyright   :  (c) The University of Glasgow 2004
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  alpha
-- Portability :  portable
--
-- This is the information about an /installed/ package that
-- is communicated to the @hc-pkg@ program in order to register
-- a package.  @ghc-pkg@ now consumes this package format (as of verison
-- 6.4). This is specific to GHC at the moment.


{- All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.

    * Neither the name of the University nor the names of other
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. -}

-- This module is meant to be local-only to Distribution...

module Distribution.InstalledPackageInfo (
	InstalledPackageInfo_(..), InstalledPackageInfo,
	ParseResult(..), PError(..), PWarning,
	emptyInstalledPackageInfo,
	parseInstalledPackageInfo,
	showInstalledPackageInfo,
	showInstalledPackageInfoField,
  ) where

import Distribution.ParseUtils (
	FieldDescr(..), readFields, ParseResult(..), PError(..), PWarning,
	Field(F), simpleField, listField, parseLicenseQ, ppField, ppFields,
	parseFilePathQ, parseTokenQ, parseModuleNameQ, parsePackageNameQ,
	showFilePath, showToken, boolField, parseOptVersion, parseQuoted,
	showFreeText)
import Distribution.License 	( License(..) )
import Distribution.Package
         ( PackageIdentifier(..), packageName, packageVersion )
import qualified Distribution.Package as Package
         ( Package(..), PackageFixedDeps(..) )
import Distribution.Version
         ( Version(..) )
import Distribution.Text
         ( Text(disp, parse) )
import qualified Distribution.Compat.ReadP as ReadP

import Control.Monad	( foldM )
import Text.PrettyPrint

-- -----------------------------------------------------------------------------
-- The InstalledPackageInfo type

data InstalledPackageInfo_ m
   = InstalledPackageInfo {
	-- these parts are exactly the same as PackageDescription
	package           :: PackageIdentifier,
        license           :: License,
        copyright         :: String,
        maintainer        :: String,
	author            :: String,
        stability         :: String,
	homepage          :: String,
	pkgUrl            :: String,
	description       :: String,
	category          :: String,
	-- these parts are required by an installed package only:
        exposed           :: Bool,
	exposedModules	  :: [m],
	hiddenModules     :: [m],
        importDirs        :: [FilePath],  -- contain sources in case of Hugs
        libraryDirs       :: [FilePath],
        hsLibraries       :: [String],
        extraLibraries    :: [String],
	extraGHCiLibraries:: [String],    -- overrides extraLibraries for GHCi
        includeDirs       :: [FilePath],
        includes          :: [String],
        depends           :: [PackageIdentifier],
        hugsOptions	  :: [String],
        ccOptions	  :: [String],
        ldOptions	  :: [String],
        frameworkDirs     :: [FilePath],
        frameworks	  :: [String],
	haddockInterfaces :: [FilePath],
	haddockHTMLs      :: [FilePath]
    }
    deriving (Read, Show)

instance Package.Package          (InstalledPackageInfo_ str) where
   packageId = package
instance Package.PackageFixedDeps (InstalledPackageInfo_ str) where
   depends   = depends

type InstalledPackageInfo = InstalledPackageInfo_ String

emptyInstalledPackageInfo :: InstalledPackageInfo_ m
emptyInstalledPackageInfo
   = InstalledPackageInfo {
        package           = PackageIdentifier "" noVersion,
        license           = AllRightsReserved,
        copyright         = "",
        maintainer        = "",
	author		  = "",
        stability         = "",
	homepage	  = "",
	pkgUrl		  = "",
	description	  = "",
	category	  = "",
        exposed           = False,
	exposedModules	  = [],
	hiddenModules     = [],
        importDirs        = [],
        libraryDirs       = [],
        hsLibraries       = [],
        extraLibraries    = [],
        extraGHCiLibraries= [],
        includeDirs       = [],
        includes	  = [],
        depends           = [],
        hugsOptions       = [],
        ccOptions         = [],
        ldOptions         = [],
        frameworkDirs     = [],
        frameworks        = [],
	haddockInterfaces = [],
	haddockHTMLs      = []
    }

noVersion :: Version
noVersion = Version{ versionBranch=[], versionTags=[] }

-- -----------------------------------------------------------------------------
-- Parsing

parseInstalledPackageInfo :: String -> ParseResult InstalledPackageInfo
parseInstalledPackageInfo inp = do
  stLines <- readFields inp
	-- not interested in stanzas, so just allow blank lines in
	-- the package info.
  foldM (parseBasicStanza all_fields) emptyInstalledPackageInfo stLines

parseBasicStanza :: [FieldDescr a]
		    -> a
		    -> Field
		    -> ParseResult a
parseBasicStanza ((FieldDescr name _ set):fields) pkg (F lineNo f val)
  | name == f = set lineNo val pkg
  | otherwise = parseBasicStanza fields pkg (F lineNo f val)
parseBasicStanza [] pkg _ = return pkg
parseBasicStanza _ _ _ = 
    error "parseBasicStanza must be called with a simple field."

-- -----------------------------------------------------------------------------
-- Pretty-printing

showInstalledPackageInfo :: InstalledPackageInfo -> String
showInstalledPackageInfo pkg = render (ppFields pkg all_fields)

showInstalledPackageInfoField
	:: String
	-> Maybe (InstalledPackageInfo -> String)
showInstalledPackageInfoField field
  = case [ (f,get') | (FieldDescr f get' _) <- all_fields, f == field ] of
	[]      -> Nothing
	((f,get'):_) -> Just (render . ppField f . get')

-- -----------------------------------------------------------------------------
-- Description of the fields, for parsing/printing

all_fields :: [FieldDescr InstalledPackageInfo]
all_fields = basicFieldDescrs ++ installedFieldDescrs

basicFieldDescrs :: [FieldDescr InstalledPackageInfo]
basicFieldDescrs =
 [ simpleField "name"
                           text                   parsePackageNameQ
                           packageName            (\name pkg -> pkg{package=(package pkg){pkgName=name}})
 , simpleField "version"
                           disp                   parseOptVersion
                           packageVersion         (\ver pkg -> pkg{package=(package pkg){pkgVersion=ver}})
 , simpleField "license"
                           disp                   parseLicenseQ
                           license                (\l pkg -> pkg{license=l})
 , simpleField "copyright"
                           showFreeText           parseFreeText
                           copyright              (\val pkg -> pkg{copyright=val})
 , simpleField "maintainer"
                           showFreeText           parseFreeText
                           maintainer             (\val pkg -> pkg{maintainer=val})
 , simpleField "stability"
                           showFreeText           parseFreeText
                           stability              (\val pkg -> pkg{stability=val})
 , simpleField "homepage"
                           showFreeText           parseFreeText
                           homepage               (\val pkg -> pkg{homepage=val})
 , simpleField "package-url"
                           showFreeText           parseFreeText
                           pkgUrl                 (\val pkg -> pkg{pkgUrl=val})
 , simpleField "description"
                           showFreeText           parseFreeText
                           description            (\val pkg -> pkg{description=val})
 , simpleField "category"
                           showFreeText           parseFreeText
                           category               (\val pkg -> pkg{category=val})
 , simpleField "author"
                           showFreeText           parseFreeText
                           author                 (\val pkg -> pkg{author=val})
 ]

parseFreeText :: ReadP.ReadP s String
parseFreeText = ReadP.munch (const True)

installedFieldDescrs :: [FieldDescr InstalledPackageInfo]
installedFieldDescrs = [
   boolField "exposed"
	exposed     	   (\val pkg -> pkg{exposed=val})
 , listField   "exposed-modules"
	text               parseModuleNameQ
	exposedModules     (\xs    pkg -> pkg{exposedModules=xs})
 , listField   "hidden-modules"
	text               parseModuleNameQ
	hiddenModules      (\xs    pkg -> pkg{hiddenModules=xs})
 , listField   "import-dirs"
	showFilePath       parseFilePathQ
	importDirs         (\xs pkg -> pkg{importDirs=xs})
 , listField   "library-dirs"
	showFilePath       parseFilePathQ
	libraryDirs        (\xs pkg -> pkg{libraryDirs=xs})
 , listField   "hs-libraries"
	showFilePath       parseTokenQ
	hsLibraries        (\xs pkg -> pkg{hsLibraries=xs})
 , listField   "extra-libraries"
	showToken          parseTokenQ
	extraLibraries     (\xs pkg -> pkg{extraLibraries=xs})
 , listField   "extra-ghci-libraries"
	showToken          parseTokenQ
	extraGHCiLibraries (\xs pkg -> pkg{extraGHCiLibraries=xs})
 , listField   "include-dirs"
	showFilePath       parseFilePathQ
	includeDirs        (\xs pkg -> pkg{includeDirs=xs})
 , listField   "includes"
	showFilePath       parseFilePathQ
	includes           (\xs pkg -> pkg{includes=xs})
 , listField   "depends"
	disp               parsePackageId'
	depends            (\xs pkg -> pkg{depends=xs})
 , listField   "hugs-options"
	showToken	   parseTokenQ
	hugsOptions        (\path  pkg -> pkg{hugsOptions=path})
 , listField   "cc-options"
	showToken	   parseTokenQ
	ccOptions          (\path  pkg -> pkg{ccOptions=path})
 , listField   "ld-options"
	showToken	   parseTokenQ
	ldOptions          (\path  pkg -> pkg{ldOptions=path})
 , listField   "framework-dirs"
	showFilePath       parseFilePathQ
	frameworkDirs      (\xs pkg -> pkg{frameworkDirs=xs})
 , listField   "frameworks"
	showToken          parseTokenQ
	frameworks         (\xs pkg -> pkg{frameworks=xs})
 , listField   "haddock-interfaces"
	showFilePath       parseFilePathQ
	haddockInterfaces  (\xs pkg -> pkg{haddockInterfaces=xs})
 , listField   "haddock-html"
	showFilePath       parseFilePathQ
	haddockHTMLs       (\xs pkg -> pkg{haddockHTMLs=xs})
 ]

parsePackageId' :: ReadP.ReadP [PackageIdentifier] PackageIdentifier
parsePackageId' = parseQuoted parse ReadP.<++ parse