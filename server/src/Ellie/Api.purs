module Ellie.Api where

import Prelude

import Control.Monad.Except (runExcept) as Except
import Control.Monad.Trans.Class (lift)
import Data.Either (Either(..))
import Data.Entity (Entity)
import Data.Entity as Entity
import Data.Foreign (Foreign, MultipleErrors)
import Data.Foreign (toForeign) as Foreign
import Data.Foreign.Class (decode, encode) as Foreign
import Data.Foreign.Generic (encodeJSON) as Foreign
import Data.Foreign.Index ((!))
import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
import Data.String (Pattern(Pattern))
import Data.String (stripPrefix) as String
import Data.TemplateString.Unsafe (template) as String
import Data.Url as Url
import Ellie.Domain.Assets (class Assets)
import Ellie.Domain.Assets as Assets
import Ellie.Domain.Platform (class Platform)
import Ellie.Domain.Platform as Platform
import Ellie.Domain.RevisionRepo (class RevisionRepo)
import Ellie.Domain.RevisionRepo as RevisionRepo
import Ellie.Domain.Search (class Search)
import Ellie.Domain.Search as Search
import Ellie.Domain.UserRepo (class UserRepo)
import Ellie.Domain.UserRepo as UserRepo
import Ellie.Types.Revision as Revision
import Ellie.Types.TermsVersion as TermsVersion
import Ellie.Types.User (User(..))
import Ellie.Types.User as User
import Server.Action (ActionT)
import Server.Action as Action
import System.Jwt (Jwt(..))
import Debug as Debug


getRevision ∷ ∀ m. Monad m ⇒ RevisionRepo m ⇒ ActionT m Unit
getRevision = do
  projectId ← Action.getParam "projectId"
  revisionNumber ← Action.getParam "revisionNumber"
  let
    maybeRevisionId =
      { projectId: _, revisionNumber: _ }
        <$> projectId
        <*> revisionNumber
        <#> Revision.Id
  case maybeRevisionId of
    Just revisionId → do
      maybeRevision ← lift $ RevisionRepo.retrieve revisionId
      case maybeRevision of
        Just entity → do
          Action.setStatus 200
          Action.setStringBody $ Foreign.encodeJSON entity
        Nothing →
          Action.setStatus 404
    Nothing →
      Action.setStatus 400


searchPackages ∷ ∀ m. Monad m ⇒ Search m ⇒ ActionT m Unit
searchPackages = do
  maybeQuery ← Action.getParam "query"
  case maybeQuery of
    Just query → do
      packages ← lift $ Search.search query
      Action.setStatus 200
      Action.setStringBody $ Foreign.encodeJSON packages
    Nothing →
      Action.setStatus 400


me ∷ ∀ m. Monad m ⇒ UserRepo m ⇒ ActionT m Unit
me = do
  maybeToken ← Action.getParam "token"
  maybeUserId ← Maybe.maybe (pure Nothing) (lift <<< UserRepo.verify) maybeToken
  maybeUserEntity ← Maybe.maybe (pure Nothing) (lift <<< UserRepo.retrieve) maybeUserId
  { token, user } ←
    case maybeUserEntity of
      Just entity → do
        token ← lift $ UserRepo.sign (Entity.key entity)
        pure { token, user: entity }
      Nothing → do
        entity ← lift $ UserRepo.create
        token ← lift $ UserRepo.sign (Entity.key entity)
        pure { token, user: entity }
  Action.setStatus 201
  Action.setStringBody
    $ Foreign.encodeJSON
    $ Foreign.toForeign { token: Foreign.encode token, user: Foreign.encode user }


saveSettings ∷ ∀ m. Monad m ⇒ UserRepo m ⇒ ActionT m Unit
saveSettings = do
  maybeUser ← authorize
  case maybeUser of
    Nothing → Action.setStatus 401
    Just entity → do
      let userId = Entity.key entity
      let (User user) = Entity.record entity
      eitherSettings ← Action.getBody
      case eitherSettings of
        Left errors → Action.setStatus 400
        Right settings → do
          let newUser = User $ user { settings = settings }
          lift $ UserRepo.save userId newUser
          Action.setStatus 204
  where
    authorize ∷ ActionT m (Maybe (Entity User.Id User))
    authorize = do
      maybeTokenHeader ← Action.getHeader "Authorization"
      let maybeToken = maybeTokenHeader >>= String.stripPrefix (Pattern "Bearer ")
      case maybeToken of
        Nothing → pure Nothing
        Just token → do
          maybeUserId ← lift $ UserRepo.verify (Jwt token)
          case maybeUserId of
            Nothing → pure Nothing
            Just userId → lift $ UserRepo.retrieve userId


formatCode ∷ ∀ m. Monad m ⇒ Platform m ⇒ ActionT m Unit
formatCode = do
  (rawBody ∷ Either MultipleErrors Foreign) ← Action.getBody
  let code = rawBody >>= \body → Except.runExcept (body ! "code" >>= Foreign.decode)
  case code of
    Left errors →
      Action.setStatus 400
    Right code → do
      result ← lift $ Platform.format code
      case result of
        Left message → do
          Action.setStatus 400
          Action.setHeader "Content-Type" "application/json"
          Action.setStringBody $ Foreign.encodeJSON $ Foreign.toForeign { error: message }
        Right code → do
          Action.setStatus 200
          Action.setHeader "Content-Type" "application/json"
          Action.setStringBody $ Foreign.encodeJSON $ Foreign.toForeign { code }


result ∷ ∀ m. Monad m ⇒ UserRepo m ⇒ Platform m ⇒ ActionT m Unit
result = do
  maybeUser ← authorizeParam 
  case maybeUser of
    Nothing → Action.setStatus 401
    Just entity → do
      { javascript, html } ← lift $ Platform.result $ Entity.key entity
      format ← Action.getParam "format"
      case (Debug.log format) of
        Just "javascript" → Action.setFileBody javascript
        Just "html" → Action.setFileBody html
        _ → Action.setStatus 404


newUi ∷ ∀ m. Monad m ⇒ Assets m ⇒ UserRepo m ⇒ ActionT m Unit
newUi = do
  Action.setStatus 200
  (lift htmlContent) >>= Action.setStringBody
  where
    htmlTemplate ∷ String
    htmlTemplate =
        """
        <html>
          <head>
            <meta charset="utf-8" />
            <base href="/" />
            <link rel="icon" href="${favicon}" />
            <title>Ellie - The Elm Live Editor</title>
            <meta property="og:image" content="${logo}" itemprop="thumbnailUrl" />
            <meta property="og:title" content="Ellie - The Elm Live Editor" />
            <meta property="og:url" content="https://ellie-app.com/new" />
            <meta property="og:site_name" content="Ellie" />
            <meta property="og:description" content="Ellie puts the Elm platform in your browser so you can try Elm, share ideas, and bring your programs to life." />
            <meta name="twitter:card" content="summary" />
            <meta name="twitter:url" content="https://ellie-app.com/new" />
            <meta name="twitter:title" content="Ellie - The Elm Live Editor" />
            <meta name="twitter:description" content="Ellie puts the Elm platform in your browser so you can try Elm, share ideas, and bring your programs to life." />
            <meta name="twitter:image" content="${logo}" />
            <meta name="latest_terms_version" content="1" />
            <meta name="accepted_terms_version" content="1" />
            <script src="https://cdnjs.cloudflare.com/ajax/libs/custom-elements/1.0.8/custom-elements.min.js"></script>
            <script async src="${javascript}"></script>
            <link href="https://fonts.googleapis.com/css?family=Quicksand" rel="stylesheet" />
          </head>
          <body>
          </body>
        </html>
        """

    htmlContent ∷ m String
    htmlContent = do
      parameters ←
        { javascript: _, latestTermsVersion: _, favicon: _, logo: _ }
          <$> (Url.href <$> Assets.assetUrl "editor.js")
          <*> pure (show TermsVersion.latest)
          <*> (Url.href <$> Assets.assetUrl "images/favicon.ico")
          <*> (Url.href <$> Assets.assetUrl "images/logo.png")
      pure $ String.template htmlTemplate parameters


authorizeParam ∷ ∀ m. Monad m ⇒ UserRepo m ⇒ ActionT m (Maybe (Entity User.Id User))
authorizeParam = do
  maybeToken ← Action.getParam "token"
  case maybeToken of
    Nothing → pure Nothing
    Just token → do
      maybeUserId ← lift $ UserRepo.verify (Jwt token)
      case maybeUserId of
        Nothing → pure Nothing
        Just userId → lift $ UserRepo.retrieve userId