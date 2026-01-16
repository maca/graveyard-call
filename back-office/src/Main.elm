port module Main exposing (main)

import PostgRestAdmin


port loggedIn : String -> Cmd msg


port loggedOut : () -> Cmd msg


main : PostgRestAdmin.Program
main =
    PostgRestAdmin.configure
        |> PostgRestAdmin.withClientHeaders []
        |> PostgRestAdmin.onLogin loggedIn
        |> PostgRestAdmin.onLogout loggedOut
        |> PostgRestAdmin.buildProgram
