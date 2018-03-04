module Ellie.Adapters.LocalPlatform
  ( Env
  , Workspace
  , initialize
  , destroy
  , compile
  , format
  , result
  ) where

import Prelude

import Control.Monad.Eff.Class (liftEff) as Eff
import Control.Monad.Eff.Exception (Error, error)
import Control.Monad.Eff.Ref (Ref)
import Control.Monad.Eff.Ref as Ref
import Control.Monad.Error.Class (class MonadThrow, throwError, try)
import Control.Monad.Except (runExcept) as Except
import Control.Monad.IO (IO)
import Control.Monad.IO.Class (class MonadIO)
import Control.Monad.IO.Class (liftIO) as IO
import Data.Array as Array
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Either as Either
import Data.FilePath (FilePath, (</>), (<.>))
import Data.FilePath as FilePath
import Data.Foldable (for_, maximum)
import Data.Foreign (F, Foreign)
import Data.Foreign (readArray, renderForeignError) as Foreign
import Data.Foreign.Class (decode) as Foreign
import Data.Foreign.Index ((!))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
import Data.Newtype (unwrap)
import Data.Set (Set)
import Data.Set as Set
import Data.String (Pattern(Pattern))
import Data.String (joinWith, null, split, trim) as String
import Data.String.Class (toString) as String
import Data.String.Murmur as Murmur
import Data.String.Regex (Regex)
import Data.String.Regex (match) as Regex
import Data.String.Regex.Flags (noFlags) as Regex
import Data.String.Regex.Unsafe (unsafeRegex) as Regex
import Data.Traversable (traverse)
import Ellie.Types.User as User
import Elm.Compiler.Error as Compiler
import Elm.Package (Package(..))
import Elm.Package.Name (Name(..))
import Elm.Package.Name as Name
import Elm.Package.Version (Version(..))
import Elm.Package.Version as Version
import System.Cache (Cache)
import System.Cache as Cache
import System.Dom (Document)
import System.Dom as Dom
import System.Elm as Elm
import System.FileSystem as FileSystem
import System.Http as Http
import System.Random as Random


type Workspace =
  { location ∷ FilePath
  , packages ∷ Set Package
  , elmHash ∷ String
  , htmlHash ∷ String
  , currentErrors ∷ Array Compiler.Error
  }

newtype WorkspaceNt =
  WorkspaceNt Workspace

instance showWorkspaceNt ∷ Show WorkspaceNt where
  show (WorkspaceNt { location }) =
    "Workspace " <> location


type Env r =
  { defaultPackages ∷ Cache (Array Package)
  , userWorkspaces ∷ Ref (Map User.Id Workspace)
  , packageSite ∷ String
  | r
  }


hardcodedDefaults ∷ Array Package
hardcodedDefaults =
  [ Package { name: Name.core, version: Version { major: 6, minor: 0, patch: 0 } }
  , Package { name: Name.html, version: Version { major: 3, minor: 0, patch: 0 } }
  , Package { name: Name.browser, version: Version { major: 1, minor: 0, patch: 0 } }
  ]


reloadDefaultPackages ∷ ∀ r. Env r → IO (Array Package)
reloadDefaultPackages env = do
  remoteOrError ←
    try do
      rawPackageData ←
        Http.get $ env.packageSite <> "/search.json"

      packageData ←
        rawPackageData
          # decodeNameAndVersions
          # Except.runExcept
          # lmap (\me → error $ String.joinWith "\n" $ Array.fromFoldable $ map Foreign.renderForeignError me)
          # Either.either throwError pure
      
      packageData
        # Array.filter (\p → Name.isCore p.name || Name.isHtml p.name || Name.isBrowser p.name)
        # map (\p → Package { name: p.name, version: Maybe.fromMaybe Version.zero $ maximum p.versions })
        # pure

  case remoteOrError of
    Left _ → pure hardcodedDefaults
    Right remote → pure remote
  where
    decodeNameAndVersion ∷ Foreign → F { name ∷ Name, versions ∷ Array Version }
    decodeNameAndVersion object = do
      { name: _, versions: _ }
        <$> (object ! "name" >>= Foreign.decode)
        <*> (object ! "versions" >>= Foreign.decode)

    decodeNameAndVersions ∷ Foreign → F (Array { name ∷ Name, versions ∷ Array Version })
    decodeNameAndVersions array =
      Foreign.readArray array >>= traverse decodeNameAndVersion


format ∷ ∀ m. MonadIO m ⇒ String → m (Either String String)
format code =
  IO.liftIO $ Elm.format code


result ∷ ∀ r m. MonadIO m ⇒ MonadThrow Error m ⇒ User.Id → Env r → m { javascript ∷ FilePath, html ∷ FilePath }
result userId env = IO.liftIO do
  workspaces ← Eff.liftEff $ Ref.readRef env.userWorkspaces
  case Map.lookup userId workspaces of
    Just workspace →
      pure
        { javascript: workspace.location </> "build.js"
        , html: workspace.location </> "index.html"
        }
    Nothing →
      throwError $ error "Cannot stream results from an uninitialized workspace"


initialize ∷ ∀ r m. MonadIO m ⇒ MonadThrow Error m ⇒ User.Id → Env r → m (Set Package)
initialize userId env = IO.liftIO do
  defaults ← Cache.read (reloadDefaultPackages env) env.defaultPackages
  let defaultsSet = Set.fromFoldable defaults
  workspaces ← Eff.liftEff $ Ref.readRef env.userWorkspaces
  case Map.lookup userId workspaces of
    Just workspace → do
      let defaultsSet = Set.fromFoldable defaults
      Elm.install workspace.location defaultsSet
      Eff.liftEff $ Ref.modifyRef env.userWorkspaces \workspaces →
        let
          updated =
            workspace
              { packages = defaultsSet
              , elmHash = ""
              , htmlHash = ""
              , currentErrors = []
              }
        in
        Map.insert userId updated workspaces
      pure defaultsSet
    Nothing → do
      root ← FileSystem.createTemporaryDirectory
      Elm.init root
      Eff.liftEff $ Ref.modifyRef env.userWorkspaces \workspaces →
        let
          workspace =
              { location: root
              , packages: defaultsSet
              , elmHash: ""
              , htmlHash: ""
              , currentErrors: []
              }
        in
        Map.insert userId workspace workspaces
      pure defaultsSet


destroy ∷ ∀ m r. MonadIO m ⇒ User.Id → Env r → m Unit
destroy userId env = IO.liftIO do
  workspaces ← Eff.liftEff $ Ref.readRef env.userWorkspaces
  case Map.lookup userId workspaces of
    Just workspace → do
      FileSystem.remove workspace.location
      Eff.liftEff $ Ref.modifyRef env.userWorkspaces (Map.delete userId)
    Nothing →
      pure unit


compile ∷ ∀ m r. MonadIO m ⇒ MonadThrow Error m ⇒ String → String → Array Package → User.Id → Env r → m (Array Compiler.Error)
compile elm html packages userId env = IO.liftIO do
  workspaces ← Eff.liftEff $ Ref.readRef env.userWorkspaces
  
  workspace ←
    workspaces
      # Map.lookup userId
      # map pure
      # Maybe.fromMaybe (throwError (error "trying to compile without a workspace"))

  let packagesSet = Set.fromFoldable packages
  let newElmHash = Murmur.hash elm
  let newHtmlHash = Murmur.hash html
  let elmChanged = newElmHash /= workspace.elmHash
  let htmlChanged = newHtmlHash /= workspace.htmlHash
  let packagesChanged = packagesSet /= workspace.packages
  let needsCompile = packagesChanged || elmChanged
  let elmPath = parseElmPath elm
  let htmlPath = "index.html"

  -- NOTE: if p then action else pure unit == when b action
  -- It's pretty idiomatic to use `when` in these situations
  when packagesChanged
    (Elm.install workspace.location packagesSet)

  if elmChanged
    then do
      FileSystem.write (workspace.location </> elmPath) elm
    else
      pure unit

  newErrors ←
    if needsCompile
      then do
        errors ← Elm.compile { root: workspace.location, entry: elmPath, output: "build.js", debug: true }
        pure $ Array.filter (unwrap >>> _.level >>> (/=) "warning") errors
      else pure workspace.currentErrors

  if htmlChanged
    then do
      fixed ← fixHtml html
      FileSystem.write (workspace.location </> htmlPath) fixed
    else pure unit

  let
    updatedWorkspace =
      workspace
        { elmHash = newElmHash
        , htmlHash = newHtmlHash
        , currentErrors = newErrors 
        , packages = packagesSet
        }
  
  Eff.liftEff $ Ref.modifyRef env.userWorkspaces (Map.insert userId updatedWorkspace)
  pure newErrors
  where
    elmModuleRegex ∷ Regex
    elmModuleRegex =
      Regex.unsafeRegex "module (([A-Z]{1}[a-zA-Z0-9]*\\.?)+) where" Regex.noFlags

    findElmModule ∷ String → String
    findElmModule source = Maybe.fromMaybe "Main" do
      matches ← Regex.match elmModuleRegex source
      secondMatch ← Array.index matches 1 
      secondMatch

    parseElmPath ∷ String → FilePath
    parseElmPath source =
      source
        # findElmModule
        # String.split (Pattern ".")
        # FilePath.joinParts
        # (_ <.> "elm")


fixHtml ∷ String → IO String
fixHtml input = do
  document ← Dom.parseFromString input
  random ← Random.int
  scripts ← Dom.querySelectorAll "script" document
  for_ scripts \script → do
    src ← Dom.getAttribute "src" script
    textContent ← Dom.getTextContent script
    case { hasSrc: Maybe.isNothing src, hasContent: not (String.null (String.trim textContent)) } of
      { hasSrc: false, hasContent: false } →
        Dom.setTextContent (wrapOnReady random textContent) script
      _ →
        pure unit
  onReady random document
  hacksScript ← Dom.createElement "script" document
  Dom.setTextContent openingHacksScript hacksScript

  script ← Dom.createElement "script" document
  Dom.setTextContent writeElmScript script
  
  body ← Dom.body document
  Dom.prepend script body
  Dom.prepend hacksScript body
  
  documentElement ← Dom.documentElement document
  Dom.getOuterHtml documentElement
  where
    wrapOnReady ∷ Int → String → String
    wrapOnReady random script =
      "__ellie_onReady_" <> String.toString random <> "(function () {" <> script <> "})"

    onReady ∷ Int → Document → IO Unit
    onReady random document = do
      let text = onReadyDecl <> String.toString random <> onReadyBody
      script ← Dom.createElement "script" document
      Dom.setTextContent text script
      head ← Dom.head document
      Dom.appendChild script head


writeElmScript ∷ String
writeElmScript =
  """(function () {
  var script = document.createElement('script')
  script.src = '/private-api/workspace/result/javascript?token=' + (new URLSearchParams(window.location.search)).get('token')
  document.write(script.outerHTML)
}())"""


openingHacksScript ∷ String
openingHacksScript =
  """(function () {
  var parent = window.parent
  delete window.parent

  // LOGS

  var oldLog = console.log
  console.log = function () {
    var firstArg = arguments[0]
    if (arguments.length === 1 && typeof firstArg === 'string' && firstArg.indexOf(': ') !== -1) {
      var split = firstArg.split(': ')
      var label = split[0]
      var body = split.slice(1).join(': ')
      parent.postMessage({ tag: 'LogReceived', contents: { label: label, body: body } }, origin)
    }
    oldLog.apply(this, arguments)
  }

  // DEBUGGER

  var debuggerWindowProxy = null
  window.open = function () {
    var iframe = document.createElement('iframe')
    iframe.style.zIndex = 999999999
    iframe.style.width = '100%'
    iframe.style.height = '100%'
    iframe.style.position = 'fixed'
    iframe.style.top = 0
    iframe.style.left = 0
    iframe.style.border = 0
    document.body.appendChild(iframe)
    var onClose = function () {}
    debuggerWindowProxy = Object.defineProperties({}, {
      document: {
        get: function () { return iframe.contentDocument }
      },
      close: {
        value: function () {
          document.body.removeChild(iframe)
          onClose()
        }
      },
      addEventListener: {
        value: function (event, fn) {
          if (event === 'unload') onClose = fn
        }
      }
    })
    return debuggerWindowProxy
  }
  var styles = document.createElement('style')
  styles.textContent = [
    '.elm-mini-controls {',
    '  display: none !important;',
    '}'
  ].join('\n')
  document.head.appendChild(styles)
  window.addEventListener('message', function (event) {
    switch(event.data.tag) {
      case 'SwitchToDebugger':
        var button = document.querySelector('.elm-mini-controls-button')
        if (button) button.click()
        break

      case 'SwitchToProgram':
        if (debuggerWindowProxy) debuggerWindowProxy.close()
        break
    } 
  })
}())
"""

onReadyDecl ∷ String
onReadyDecl =
  "function __ellie_onReady_"


onReadyBody ∷ String
onReadyBody =
  """(cb) {
  function completed() {
    document.removeEventListener("DOMContentLoaded", completed)
    window.removeEventListener("load", completed)
    cb()
  }
  if (document.readyState === "complete" || ( document.readyState !== "loading" && !document.documentElement.doScroll)) {
    setTimeout(completed)
  } else {
    document.addEventListener("DOMContentLoaded", completed)
    window.addEventListener("load", completed)
  }
}"""
