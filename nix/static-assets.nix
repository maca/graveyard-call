{ pkgs }:

let
  icono = pkgs.stdenv.mkDerivation {
    pname = "icono";
    version = "1.3.0";

    src = pkgs.fetchurl {
      url = "https://cdnjs.cloudflare.com/ajax/libs/icono/1.3.0/icono.min.css";
      sha256 = "sha256-Dyy0zD6bW58Q4LIezBxY4nGzwBoQlgbBHKVOEwg5l1U=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/icono.min.css
    '';
  };

  milligram = pkgs.stdenv.mkDerivation {
    pname = "milligram";
    version = "1.4.1";

    src = pkgs.fetchurl {
      url = "https://cdnjs.cloudflare.com/ajax/libs/milligram/1.4.1/milligram.min.css";
      sha256 = "sha256-baSxKEISHdSAWiipPkWRuquIMjgNIR//a++CyhnQdIM=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/milligram.min.css
    '';
  };

  # Fetch postgrest-admin.min.js from GitHub releases
  postgrestAdmin = pkgs.stdenv.mkDerivation {
    pname = "postgrest-admin";
    version = "latest";

    src = pkgs.fetchurl {
      url = "https://github.com/maca/postgrest-admin/releases/latest/download/postgrest-admin.min.js";
      sha256 = "sha256-AcKJmEihMwsBiiMuWWtSoTsT4D9qjGLQWZLDJJvrBXc=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/postgrest-admin.min.js
    '';
  };

in
{
  inherit icono milligram postgrestAdmin;
}
