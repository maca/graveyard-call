module Main exposing (main)

import Base64
import Browser
import Bytes exposing (Bytes)
import File
import FormToolkit.Field as Field exposing (Field)
import FormToolkit.Parse as Parse
import FormToolkit.Value as Value
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events as Events
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Task


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions =
            \_ -> Http.track "submission" GotProgress
        }


type Notice
    = Error String
    | Notice String
    | NoNotice


type alias Model =
    { fields : Field String
    , notice : Notice
    , progress : Maybe { sent : Int, size : Int }
    , jwtToken : Maybe String
    }


type Msg
    = FieldsChanged (Field.Msg String)
    | FormSubmitted
    | GotBytes Bytes
    | Uploaded (Result Http.Error ())
    | GotProgress Http.Progress
    | CancelUpload
    | GotToken (Result Http.Error String)
    | DismissNotice Notice


init : () -> ( Model, Cmd Msg )
init _ =
    ( { fields = fields
      , notice = NoNotice
      , progress = Nothing
      , jwtToken = Nothing
      }
    , Task.attempt GotToken (fetchJwtTokenAfter tokenTTL)
    )


tokenTTL : number
tokenTTL =
    10000


fetchJwtTokenAfter : Float -> Task.Task Http.Error String
fetchJwtTokenAfter delayMs =
    Process.sleep delayMs
        |> Task.andThen
            (\_ ->
                Http.task
                    { method = "POST"
                    , headers = []
                    , url = "/api/rpc/submission_jwt"
                    , body = Http.jsonBody (Encode.object [])
                    , resolver =
                        Http.stringResolver
                            (\response ->
                                case response of
                                    Http.GoodStatus_ _ body ->
                                        Decode.decodeString (Decode.field "token" Decode.string) body
                                            |> Result.mapError (\_ -> Http.BadBody "Failed to decode token")

                                    Http.BadUrl_ url ->
                                        Err (Http.BadUrl url)

                                    Http.Timeout_ ->
                                        Err Http.Timeout

                                    Http.NetworkError_ ->
                                        Err Http.NetworkError

                                    Http.BadStatus_ metadata _ ->
                                        Err (Http.BadStatus metadata.statusCode)
                            )
                    , timeout = Nothing
                    }
            )


fields : Field String
fields =
    Field.group
        []
        [ Field.text
            [ Field.identifier "name"
            , Field.label "Name"
            , Field.hint "It's up to you to tell us who you are"
            ]
        , Field.text
            [ Field.identifier "email"
            , Field.label "Email"
            , Field.hint "You can provide your if email if you like"
            ]
        , Field.file
            [ Field.identifier "file"
            , Field.label "Upload"
            , Field.required True
            , Field.hint "Please upload a file"
            , Field.max (Value.int 5242880)
            ]
        , Field.textarea
            [ Field.identifier "comment"
            , Field.label "Comment"
            , Field.autogrow True
            , Field.hint "Feel free to add a comment to your submission"
            ]
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FieldsChanged innerMsg ->
            ( { model | fields = Field.update innerMsg model.fields }
            , Cmd.none
            )

        FormSubmitted ->
            case ( model.jwtToken, Parse.parse (Parse.field "file" Parse.file) model.fields ) of
                ( Just _, Ok file ) ->
                    ( model, Task.perform GotBytes (File.toBytes file) )

                ( Nothing, _ ) ->
                    ( { model | progress = Just { sent = 0, size = 100 } }
                    , Task.perform (always FormSubmitted) (Process.sleep 500)
                    )

                _ ->
                    showNotice (Error "Please select a file.") model

        GotBytes bytes ->
            ( model
            , Http.request
                { method = "POST"
                , headers =
                    [ Http.header "Authorization"
                        ("Bearer " ++ (model.jwtToken |> Maybe.withDefault ""))
                    ]
                , url = "/api/submissions"
                , body = Http.jsonBody (encodeSubmission model.fields bytes)
                , expect = Http.expectWhatever Uploaded
                , timeout = Nothing
                , tracker = Just "submission"
                }
            )

        GotProgress (Http.Sending progress) ->
            ( { model | progress = Just progress }, Cmd.none )

        GotProgress _ ->
            ( model, Cmd.none )

        Uploaded result ->
            showNotice
                (case result of
                    Ok _ ->
                        Notice "Thanks for your submission!"

                    Err _ ->
                        Error "Ohh! Something went wrong, please try again."
                )
                { model | progress = Nothing, fields = fields }

        CancelUpload ->
            ( { model | progress = Nothing }, Http.cancel "submission" )

        GotToken (Ok token) ->
            ( { model | jwtToken = Just token }
            , Task.attempt GotToken (fetchJwtTokenAfter 600000)
            )

        GotToken (Err _) ->
            ( model, Cmd.none )

        DismissNotice notice ->
            ( { model
                | notice =
                    if notice == model.notice then
                        NoNotice

                    else
                        model.notice
              }
            , Cmd.none
            )


encodeSubmission : Field String -> Bytes -> Encode.Value
encodeSubmission formFields file =
    let
        parseField name =
            Parse.field name (Parse.maybe Parse.string)
                |> Parse.map (Maybe.map (Encode.string >> Tuple.pair name))

        encoded =
            file
                |> Base64.fromBytes
                |> Maybe.withDefault ""
                |> Encode.string
    in
    Parse.parse
        (Parse.map3
            (\name email comment ->
                Encode.object
                    (List.filterMap identity
                        [ Just ( "file", encoded ), name, email, comment ]
                    )
            )
            (parseField "name")
            (parseField "email")
            (parseField "comment")
        )
        formFields
        |> Result.withDefault Encode.null


showNotice : Notice -> Model -> ( Model, Cmd Msg )
showNotice notice model =
    ( { model | notice = notice }
    , Task.perform (always (DismissNotice notice)) (Process.sleep 5000)
    )


view : Model -> Html Msg
view model =
    Html.div
        [ Attrs.class "container"
        ]
        [ Html.div
            []
            [ Html.h1
                []
                [ Html.text "Title" ]
            , Html.form
                [ Events.onSubmit FormSubmitted
                , Attrs.disabled (model.progress /= Nothing)
                ]
                [ Field.toHtml FieldsChanged model.fields
                , Html.button
                    [ Attrs.type_ "submit" ]
                    [ Html.text "Submit" ]
                ]
            , case model.notice of
                NoNotice ->
                    Html.text ""

                Error error ->
                    Html.div [ Attrs.class "error" ] [ Html.text error ]

                Notice notice ->
                    Html.div [ Attrs.class "notice" ] [ Html.text notice ]
            ]
        , case model.progress of
            Just progress ->
                viewProgressWindow progress

            Nothing ->
                Html.text ""
        ]


viewProgressWindow : { sent : Int, size : Int } -> Html Msg
viewProgressWindow progress =
    let
        percentage =
            if progress.size > 0 then
                toFloat progress.sent / toFloat progress.size * 100

            else
                0

        percentageInt =
            round percentage
    in
    Html.div
        [ Attrs.class "progress-overlay" ]
        [ Html.div
            [ Attrs.class "progress-window" ]
            [ Html.div
                [ Attrs.class "progress-title" ]
                [ Html.text "UPLOADING..." ]
            , Html.div
                [ Attrs.class "progress-bar-container" ]
                [ Html.div
                    [ Attrs.class "progress-bar"
                    , Attrs.style "width" (String.fromInt percentageInt ++ "%")
                    ]
                    []
                ]
            , Html.div
                [ Attrs.class "progress-percentage" ]
                [ Html.text (String.fromInt percentageInt ++ "%") ]
            , Html.div
                [ Attrs.class "progress-actions" ]
                [ Html.button
                    [ Events.onClick CancelUpload
                    , Attrs.class "btn-cancel"
                    ]
                    [ Html.text "CANCEL" ]
                ]
            ]
        ]
