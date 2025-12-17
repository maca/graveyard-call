{ pkgs }:

let
  # Build npm dependencies from package.json and package-lock.json
  nodeModules = pkgs.buildNpmPackage {
    pname = "graveyard-deps";
    version = "1.0.0";

    src = ../.;

    npmDepsHash = "sha256-7rauI4lrSZaR83ss4w6uzQg6TJzPkzc/Ll4lDQZ4PK8=";

    # We only want to install dependencies, not build anything
    dontNpmBuild = true;

    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/
    '';
  };

in
{
  inherit nodeModules;

  # Provide elm-watch binary directly
  elmWatch = "${nodeModules}/node_modules/.bin/elm-watch";
}
