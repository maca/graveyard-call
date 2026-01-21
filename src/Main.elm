module Main exposing (main)

import Base64
import Browser
import Bytes exposing (Bytes)
import File
import FormToolkit.Error
import FormToolkit.Field as Field exposing (Field)
import FormToolkit.Parse as Parse
import FormToolkit.Value as Value
import FormToolkit.View as View
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events as Events
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Process
import Random
import Task
import Time


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
    , placeholderIndex : Int
    }


type Msg
    = FieldsChanged (Field.Msg String)
    | FormSubmitted
    | GotBytes File.File Bytes
    | FormReady (Maybe File)
    | Uploaded (Result Http.Error ())
    | GotProgress Http.Progress
    | CancelUpload
    | GotToken (Result Http.Error String)
    | DismissNotice Notice
    | GotTime Time.Posix


storyPlaceholders : List String
storyPlaceholders =
    [ """Honestly, it felt like my whole world just fell apart when Paris Hilton's Diamond Quest straight-up disappeared. It still hits me like I lost a huge, irreplaceable piece of my life. Who's even responsible for this?? How does stuff like this even happen?? I tried to…"""
    , """I wiped out over ten years of playlists. Every track was handpicked, repping all the phases I been through, y'know, stuff I'll never get back. Sometimes bits of songs get stuck in my head, but I can't remember neither the words nor how…"""
    , """My VRChat world, the place I always hung out with one of my best mates, vanished outta nowhere. I loved that world. Now it's just… vanished, no warning, fam. I can't even…"""
    , """In 2012, my ex nuked my accounts! Ten years of posts, pics, friends whose real names I didn't even know. Security online? Completely insane! But yes… it gets worse…"""
    ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { fields = fields 0
      , notice = NoNotice
      , progress = Nothing
      , jwtToken = Nothing
      , placeholderIndex = 0
      }
    , Cmd.batch
        [ Task.perform GotTime Time.now
        , Task.attempt GotToken (fetchJwtTokenAfter 1000)
        ]
    )


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


fields : Int -> Field String
fields placeholderIndex =
    let
        placeholder =
            storyPlaceholders
                |> List.drop placeholderIndex
                |> List.head
                |> Maybe.withDefault ""
    in
    Field.group
        []
        [ Field.text
            [ Field.identifier "name"
            , Field.label "Enter your name or a username"
            ]
        , Field.text
            [ Field.identifier "email"
            , Field.label "Want to stay connected? Leave your email"
            ]
        , Field.text
            [ Field.identifier "residence"
            , Field.label "Feel free Optionally, share where you are based"
            ]
        , Field.textarea
            [ Field.identifier "story"
            , Field.label "Share the memory of your loss"
            , Field.required True
            , Field.autogrow True
            , Field.placeholder placeholder
            ]
        , Field.file
            [ Field.identifier "file"
            , Field.label "Feel free to upload an Image, Video, 3D Object, or Audio file representing your Experience of Loss"
            , Field.hint "Maximum size: 15 MB."
            , Field.max (Value.int 15728640)
            , Field.accept
                [ "image/jpeg"
                , "image/png"
                , "image/heic"
                , "image/heif"
                , "video/mp4"
                , "video/quicktime"
                , "model/gltf-binary"
                , "audio/mpeg"
                , "audio/mp4"
                , "audio/x-m4a"
                ]
            ]
        , Field.checkbox
            [ Field.identifier "consent"
            , Field.label "I have read and agree to the Consent to Use Submitted Content."
            , Field.required True
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
            formSubmitted { model | fields = Field.validate model.fields }

        GotBytes file bytes ->
            ( model
            , Task.perform identity
                (Task.succeed
                    (FormReady
                        (Just
                            { file = bytes
                            , name = File.name file
                            , mimeType = File.mime file
                            }
                        )
                    )
                )
            )

        FormReady maybeFile ->
            case Parse.parse (parser maybeFile) model.fields of
                Ok value ->
                    ( model
                    , Http.request
                        { method = "POST"
                        , headers =
                            [ Http.header "Authorization"
                                ("Bearer " ++ (model.jwtToken |> Maybe.withDefault ""))
                            ]
                        , url = "/api/submissions"
                        , body = Http.jsonBody value
                        , expect = Http.expectWhatever Uploaded
                        , timeout = Nothing
                        , tracker = Just "submission"
                        }
                    )

                Err err ->
                    showNotice (Error (FormToolkit.Error.toEnglish err)) model

        GotProgress (Http.Sending progress) ->
            ( { model | progress = Just progress }, Cmd.none )

        GotProgress _ ->
            ( model, Cmd.none )

        Uploaded result ->
            let
                ( noticeModel, noticeCmd ) =
                    showNotice
                        (case result of
                            Ok _ ->
                                Notice "Thank you for the memory. It will stay with us. Rest in peace."

                            Err _ ->
                                Error "Oops, something went wrong on our side, please try again."
                        )
                        { model
                            | progress = Nothing
                            , fields = fields model.placeholderIndex
                        }
            in
            ( noticeModel
            , Cmd.batch
                [ noticeCmd
                , Task.attempt GotToken (fetchJwtTokenAfter 0)
                ]
            )

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

        GotTime posix ->
            let
                seed =
                    Random.initialSeed (Time.posixToMillis posix)

                ( index, _ ) =
                    Random.step (Random.int 0 (List.length storyPlaceholders - 1)) seed
            in
            ( { model
                | placeholderIndex = index
                , fields = fields index
              }
            , Cmd.none
            )


formSubmitted : Model -> ( Model, Cmd Msg )
formSubmitted model =
    case
        ( model.jwtToken
        , Parse.parse (Parse.field "file" Parse.file) model.fields
        , Parse.parse (Parse.field "consent" Parse.bool) model.fields
        )
    of
        ( _, _, Err _ ) ->
            showNotice (Error "Please provide a memory and optionally a file upload.") model

        ( _, _, Ok False ) ->
            showNotice (Error "Please agree to the consent to use submitted content.") model

        ( Nothing, _, _ ) ->
            ( model, Task.perform (always FormSubmitted) (Process.sleep 500) )

        ( Just _, Ok file, _ ) ->
            ( model, Task.perform (GotBytes file) (File.toBytes file) )

        ( _, _, _ ) ->
            ( model, Task.perform identity (Task.succeed (FormReady Nothing)) )


type alias File =
    { file : Bytes
    , name : String
    , mimeType : String
    }


parser : Maybe File -> Parse.Parser String Encode.Value
parser file =
    let
        parseMaybe name =
            Parse.field name (Parse.maybe Parse.string)
                |> Parse.map (Maybe.map (Encode.string >> Tuple.pair name))

        encoded =
            file
                |> Maybe.map
                    (.file
                        >> Base64.fromBytes
                        >> Maybe.withDefault ""
                        >> Encode.string
                    )
                |> Maybe.withDefault Encode.null
    in
    Parse.succeed
        (\name email residence story consent ->
            Encode.object
                (List.filterMap identity
                    [ Just ( "file", encoded )
                    , Just
                        ( "file_name"
                        , file
                            |> Maybe.map (.name >> Encode.string)
                            |> Maybe.withDefault Encode.null
                        )
                    , Just
                        ( "file_mime_type"
                        , file
                            |> Maybe.map (.mimeType >> Encode.string)
                            |> Maybe.withDefault Encode.null
                        )
                    , Just ( "consent_given", Encode.bool consent )
                    , Just ( "consent_version", Encode.string "v1.0" )
                    , name
                    , email
                    , residence
                    , story
                    ]
                )
        )
        |> Parse.andMap (parseMaybe "name")
        |> Parse.andMap (parseMaybe "email")
        |> Parse.andMap (parseMaybe "residence")
        |> Parse.andMap (parseMaybe "story")
        |> Parse.andMap (Parse.field "consent" Parse.bool)


showNotice : Notice -> Model -> ( Model, Cmd Msg )
showNotice notice model =
    ( { model | notice = notice }
    , Task.perform (always (DismissNotice notice)) (Process.sleep 5000)
    )


view : Model -> Html Msg
view model =
    Html.div
        [ Attrs.class "content-wrapper" ]
        [ Html.div
            [ Attrs.class "side-text-left" ]
            [ Html.div [ Attrs.class "ornament top-left" ] []
            , Html.div [ Attrs.class "ornament bottom-left" ] []
            , Html.div
                [ Attrs.class "vertical-text" ]
                [ Html.a
                    [ Attrs.href "https://www.argekultur.at/"
                    , Attrs.target "_blank"
                    ]
                    [ Html.text "ARGEkultur Salzburg" ]
                , viewStars 3
                , Html.a
                    [ Attrs.href "https://schauspielhaus-graz.buehnen-graz.com/"
                    , Attrs.target "_blank"
                    ]
                    [ Html.text "Schauspielhaus Graz" ]
                ]
            ]
        , Html.div
            [ Attrs.class "container" ]
            [ viewTitle
            , Html.div [ Attrs.class "emblem-container" ] []
            , viewForm model
            , viewTitle
            ]
        , Html.div
            [ Attrs.class "side-text-right" ]
            [ Html.div [ Attrs.class "ornament top-right" ] []
            , Html.div [ Attrs.class "ornament bottom-right" ] []
            , Html.div
                [ Attrs.class "vertical-text" ]
                [ Html.div
                    []
                    [ Html.a
                        [ Attrs.href "https://www.hebbel-am-ufer.de/en/"
                        , Attrs.target "_blank"
                        ]
                        [ Html.text "HAU Hebbel am Ufer" ]

                    -- , viewStars 3
                    -- , Html.a
                    --     [ Attrs.href "https://theaternetzwerk.digital/"
                    --     , Attrs.target "_blank"
                    --     ]
                    --     [ Html.text "theaternetzwerk.digital" ]
                    , viewStars 3
                    , Html.a
                        [ Attrs.href "https://someonlinearchitecturepractice.com/"
                        , Attrs.target "_blank"
                        ]
                        [ Html.text "SOAP" ]
                    ]
                ]
            ]
        , Html.div [ Attrs.class "ornament right-middle" ] []
        , case model.progress of
            Just progress ->
                viewProgressWindow progress

            Nothing ->
                Html.text ""
        ]


viewStars : Int -> Html Msg
viewStars count =
    Html.div [ Attrs.class "stars-row" ]
        (List.repeat count (Html.div [ Attrs.class "star" ] []))


viewTitle : Html Msg
viewTitle =
    Html.div [ Attrs.class "title" ]
        [ viewStars 6
        , Html.h1 []
            [ Html.div [] [ Html.text "SHARE YOUR" ]
            , Html.div
                [ Attrs.class "char-justify" ]
                [ Html.span [] [ Html.text "S" ]
                , Html.span [] [ Html.text "T" ]
                , Html.span [] [ Html.text "O" ]
                , Html.span [] [ Html.text "R" ]
                , Html.span [] [ Html.text "Y" ]
                ]
            , Html.div [] [ Html.text "OF LOSS" ]
            ]
        ]


viewInvitationText : Html msg
viewInvitationText =
    Html.p
        [ Attrs.class "invitation-text" ]
        [ Html.span [ Attrs.style "text-decoration" "underline" ] [ Html.text "With The last Entry" ]
        , Html.text
            """, SOAP invites you to share your personal experiences of data
            loss on the internet. We want to hear your stories and memories
            shaped by erasure or disappearance in digital environments: lost
            accounts, wiped archives and servers, vanished or sunset platforms,
            no-longer-accessible chat conversations, severed connections, or
            traces quietly erased by algorithms."""
        ]


viewForm : Model -> Html Msg
viewForm model =
    Html.div
        [ Attrs.class "content" ]
        [ viewInvitationText
        , Html.form
            [ Events.onSubmit FormSubmitted
            , Attrs.disabled (model.progress /= Nothing)
            , Attrs.novalidate True
            ]
            [ model.fields
                |> View.fromField FieldsChanged
                |> View.customizeFields
                    (\{ attributes, hintHtml, inputOnCheck } ->
                        case attributes.identifier of
                            Just "consent" ->
                                Just
                                    (Html.div
                                        [ Attrs.class "field" ]
                                        [ Html.label [ Attrs.for "consent-checkbox" ]
                                            [ Html.input
                                                [ Attrs.type_ "checkbox"
                                                , Attrs.id "consent-checkbox"
                                                , attributes.value
                                                    |> Value.toBool
                                                    |> Maybe.map Attrs.checked
                                                    |> Maybe.withDefault (Attrs.class "")
                                                , Events.onCheck inputOnCheck
                                                ]
                                                []
                                            , Html.text "I have read and agree to the "
                                            , Html.a
                                                [ Attrs.href "#consent"
                                                , Attrs.class "consent-link"
                                                ]
                                                [ Html.text "Consent to Use Submitted Content" ]
                                            , Html.text "."
                                            ]
                                        , hintHtml []
                                        ]
                                    )

                            _ ->
                                Nothing
                    )
                |> View.toHtml
            , Html.button
                [ Attrs.type_ "submit" ]
                [ Html.text "Submit your loss" ]
            , Html.p
                [ Attrs.id "consent" ]
                [ Html.text """
                  You confirm that you are the creator of the submitted materials
                  or hold the necessary rights, and that no third-party rights are
                  violated. You grant the artist collective SOAP a non-exclusive,
                  global, and unlimited right to use, reproduce, edit, publish,
                  and publicly present the materials for artistic and documentary
                  purposes, including in virtual environments (e.g., VRChat),
                  while copyright remains with the author."""
                ]
            ]
        , case model.notice of
            NoNotice ->
                Html.text ""

            Error error ->
                Html.div [ Attrs.class "error" ] [ Html.text error ]

            Notice notice ->
                Html.div [ Attrs.class "notice" ] [ Html.text notice ]
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
