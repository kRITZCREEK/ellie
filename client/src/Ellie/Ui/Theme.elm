module Ellie.Ui.Theme exposing (..)

import Css exposing (..)
import Css.Foreign
import Extra.Css exposing (..)
import Html.Styled as Html exposing (Attribute, Html)
import Html.Styled.Attributes exposing (attribute)


draggableBorder : BasicProperty
draggableBorder =
    var "--theme-color-border-draggable"


staticBorder : BasicProperty
staticBorder =
    var "--theme-color-border-static"


controlBorder : BasicProperty
controlBorder =
    var "--theme-color-border-control"


accent : BasicProperty
accent =
    var "--theme-color-accent"


secondaryBackground : BasicProperty
secondaryBackground =
    var "--theme-color-background-secondary"


primaryBackground : BasicProperty
primaryBackground =
    var "--theme-color-background-primary"


primaryForeground : BasicProperty
primaryForeground =
    var "--theme-color-foreground-primary"


secondaryForeground : BasicProperty
secondaryForeground =
    var "--theme-color-foreground-secondary"


connectionStatusConnected : BasicProperty
connectionStatusConnected =
    var "--theme-color-connection-status-connected"


connectionStatusDisconnected : BasicProperty
connectionStatusDisconnected =
    var "--theme-color-connection-status-disconnected"


buttonBorder : BasicProperty
buttonBorder =
    var "--theme-color-button-border"


buttonBackground : BasicProperty
buttonBackground =
    var "--theme-color-button-background"


editorHeaderBackground : BasicProperty
editorHeaderBackground =
    var "--theme-color-editor-header-background"


workbenchWatermark : BasicProperty
workbenchWatermark =
    var "--theme-color-workbench-watermark"


darkStyles : Css.Foreign.Snippet
darkStyles =
    Css.Foreign.selector ":root"
        [ property "--theme-color-border-draggable" mediumGray.value
        , property "--theme-color-border-static" darkGray.value
        , property "--theme-color-border-control" mediumGray.value
        , property "--theme-color-accent" pink.value
        , property "--theme-color-background-primary" darkMediumGray.value
        , property "--theme-color-background-secondary" darkGray.value
        , property "--theme-color-foreground-primary" lightGray.value
        , property "--theme-color-foreground-secondary" lightMediumGray.value
        , property "--theme-color-connection-status-connected" green.value
        , property "--theme-color-connection-status-disconnected" red.value
        , property "--theme-color-button-border" "#3F3F3F"
        , property "--theme-color-button-background" "#525252"
        , property "--theme-color-editor-header-background" "#222222"
        , property "--theme-color-workbench-watermark" "#252525"
        ]


lightStyles : Css.Foreign.Snippet
lightStyles =
    Css.Foreign.selector ":root"
        [ property "--theme-color-border-draggable" mediumGray.value
        , property "--theme-color-border-static" "#EAEAEA"
        , property "--theme-color-border-control" mediumGray.value
        , property "--theme-color-accent" pink.value
        , property "--theme-color-background-primary" "#F7F7F7"
        , property "--theme-color-background-secondary" "#EAEAEA"
        , property "--theme-color-foreground-primary" darkGray.value
        , property "--theme-color-foreground-secondary" darkMediumGray.value
        ]


darkMediumGray : Color
darkMediumGray =
    hex "292929"


lightGray : Color
lightGray =
    hex "#DDDDDD"


mediumGray : Color
mediumGray =
    hex "#525252"


pink : Color
pink =
    hex "#FC6ECC"


darkGray : Color
darkGray =
    hex "#1D1D1D"


lightMediumGray : Color
lightMediumGray =
    hex "#9C9C9C"


yellow : Color
yellow =
    hex "#decb6b"


green : Color
green =
    hex "#689f8e"


blue : Color
blue =
    hex "#82B1ff"


red : Color
red =
    hex "#ec5f67"