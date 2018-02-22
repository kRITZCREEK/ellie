module Pages.Editor.Views.Editors exposing (..)

import Css exposing (..)
import Ellie.Ui.CodeEditor as CodeEditor
import Ellie.Ui.Icon as Icon
import Ellie.Ui.SplitPane as SplitPane
import Ellie.Ui.Theme as Theme
import Elm.Compiler.Error as Error exposing (Error)
import Extra.Markdown as Markdown
import Html.Styled as Html exposing (Attribute, Html, button, div, text)
import Html.Styled.Attributes as Attributes exposing (css)
import Html.Styled.Events exposing (onClick)


type alias Config msg =
    { elmCode : String
    , onElmChange : String -> msg
    , htmlCode : String
    , onHtmlChange : String -> msg
    , ratio : Float
    , onResize : Float -> msg
    , vimMode : Bool
    , onFormat : msg
    , onCollapse : msg
    , elmErrors : List Error
    }


errorToLinterMessage : Error -> CodeEditor.LinterMessage
errorToLinterMessage error =
    let
        region =
            Maybe.withDefault error.region error.subregion
    in
    { from = { line = region.start.line - 1, column = region.start.column - 1 }
    , to = { line = region.end.line - 1, column = region.end.column - 1 }
    , message = Markdown.toString <| error.overview ++ "\n\n" ++ error.details
    , severity =
        case error.level of
            "warning" ->
                CodeEditor.Warning

            _ ->
                CodeEditor.Error
    }


view : Config msg -> Html msg
view { onElmChange, elmCode, onHtmlChange, htmlCode, ratio, onResize, vimMode, onFormat, onCollapse, elmErrors } =
    Html.node "ellie-editors"
        [ css [ display block ] ]
        [ SplitPane.view
            { direction = SplitPane.Vertical
            , ratio = ratio
            , originalRatio = 0.75
            , onResize = onResize
            , minSize = 24
            , first =
                div [ containerStyles ]
                    [ viewEditorHeader "Elm" "Format Elm Code (⇧⌥F)" onFormat <| Icon.view Icon.Format
                    , div [ editorStyles ]
                        [ CodeEditor.view
                            [ CodeEditor.value elmCode
                            , CodeEditor.onChange onElmChange
                            , CodeEditor.mode "elm"
                            , CodeEditor.tabSize 4
                            , CodeEditor.vim vimMode
                            , CodeEditor.linterMessages <| List.map errorToLinterMessage elmErrors
                            ]
                        ]
                    ]
            , second =
                div [ containerStyles ]
                    [ viewEditorHeader "HTML" "Collapse HTML Editor" onCollapse <|
                        if ratio == 1 then
                            div [ css [ transform (rotate (deg 180)) ] ] [ Icon.view Icon.Chevron ]
                        else
                            Icon.view Icon.Chevron
                    , div [ editorStyles ]
                        [ CodeEditor.view
                            [ CodeEditor.value htmlCode
                            , CodeEditor.onChange onHtmlChange
                            , CodeEditor.mode "htmlmixed"
                            , CodeEditor.tabSize 2
                            , CodeEditor.vim vimMode
                            ]
                        ]
                    ]
            }
        ]


editorStyles : Attribute msg
editorStyles =
    css
        [ flexShrink (int 1)
        , height (pct 100)
        , width (pct 100)
        , displayFlex
        ]


containerStyles : Attribute msg
containerStyles =
    css
        [ position relative
        , displayFlex
        , flexDirection column
        , height (pct 100)
        , overflow hidden
        ]


viewEditorHeader : String -> String -> msg -> Html msg -> Html msg
viewEditorHeader name tooltip msg icon =
    div
        [ css
            [ backgroundColor Theme.editorHeaderBackground
            , displayFlex
            , justifyContent spaceBetween
            , alignItems center
            , padding2 zero (px 8)
            , height (px 24)
            , flexShrink (int 0)
            ]
        ]
        [ div
            [ css
                [ fontSize (px 14)
                , lineHeight (num 1)
                , textTransform uppercase
                , fontWeight bold
                , color Theme.primaryForeground
                ]
            ]
            [ text name ]
        , button
            [ css
                [ property "background" "none"
                , border zero
                , outline zero
                , display block
                , width (px 24)
                , height (px 24)
                , padding (px 6)
                , color Theme.secondaryForeground
                , cursor pointer
                , hover
                    [ color Theme.primaryForeground
                    ]
                , active
                    [ transform <| scale 1.2
                    ]
                ]
            , onClick msg
            , Attributes.title tooltip
            ]
            [ icon ]
        ]