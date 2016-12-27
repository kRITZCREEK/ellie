port module App.Subs exposing (subscriptions)

import Window
import Mouse
import Json.Decode as Decode exposing (Decoder, Value)
import Json.Decode.Pipeline as Decode
import Shared.MessageBus as MessageBus
import App.Model as Model exposing (Model)
import App.Update as Update exposing (Msg(..))
import Effects.ClickOutside as ClickOutside


port windowUnloadedIn : (() -> msg) -> Sub msg


port windowMessageIn : (Value -> msg) -> Sub msg


port online : (Bool -> msg) -> Sub msg


windowMessageDecoder : Model -> Decoder Msg
windowMessageDecoder model =
    (Decode.field "type" Decode.string)
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "click" ->
                        if model.notificationsOpen then
                            Decode.succeed ToggleNotifications
                        else
                            Decode.succeed NoOp

                    "mouseup" ->
                        if model.resultDragging then
                            Decode.succeed ResultDragEnded
                        else if model.editorDragging then
                            Decode.succeed EditorDragEnded
                        else
                            Decode.succeed NoOp

                    "mousemove" ->
                        Decode.decode Mouse.Position
                            |> Decode.required "x" Decode.int
                            |> Decode.required "y" Decode.int
                            |> Decode.map
                                (\position ->
                                    if model.resultDragging then
                                        ResultDragged position
                                    else if model.editorDragging then
                                        EditorDragged position
                                    else
                                        NoOp
                                )

                    _ ->
                        Decode.fail "unrecognized message"
            )


windowMessage : Model -> Sub Msg
windowMessage model =
    if model.resultDragging || model.editorDragging || model.notificationsOpen then
        windowMessageIn (Decode.decodeValue (windowMessageDecoder model) >> Result.withDefault NoOp)
    else
        Sub.none


windowSize : Model -> Sub Msg
windowSize model =
    Window.resizes WindowSizeChanged


editorDrags : Model -> Sub Msg
editorDrags model =
    if model.editorDragging then
        Sub.batch
            [ Mouse.moves EditorDragged
            , Mouse.ups (\_ -> EditorDragEnded)
            ]
    else
        Sub.none


resultDrags : Model -> Sub Msg
resultDrags model =
    if model.resultDragging then
        Sub.batch
            [ Mouse.moves ResultDragged
            , Mouse.ups (\_ -> ResultDragEnded)
            ]
    else
        Sub.none


clickOutsideNotifications : Model -> Sub Msg
clickOutsideNotifications model =
    if model.notificationsOpen then
        ClickOutside.clickOutside "notifications" ToggleNotifications
    else
        Sub.none


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ online OnlineChanged
        , windowUnloadedIn (\_ -> WindowUnloaded)
        , MessageBus.notifications NotificationReceived
        , windowSize model
        , resultDrags model
        , editorDrags model
        , windowMessage model
        , clickOutsideNotifications model
        ]