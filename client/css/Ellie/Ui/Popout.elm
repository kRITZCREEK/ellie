module Ellie.Ui.Popout exposing (..)

import Colors
import Css exposing (..)
import Css.File exposing (..)


container : UniqueClass
container =
    uniqueClass
        [ position relative
        ]


content : UniqueClass
content =
    uniqueClass
        [ outline zero
        , position relative
        , zIndex (int 2)
        ]


tooltip =
    uniqueClass
        [ position absolute
        , display none
        , zIndex (int 2)
        , backgroundColor Colors.darkGray
        , padding2 (px 12) (px 8)
        , Colors.boxShadow |> .popout
        , top (pct 100)
        , marginTop (px 8)
        , borderLeft3 (px 1) solid Colors.pink
        ]


open =
    uniqueClass
        [ display block |> important
        ]


overlay =
    uniqueClass
        [ position fixed
        , width (pct 100)
        , height (pct 100)
        , left zero
        , top zero
        , zIndex (int 1)
        ]
