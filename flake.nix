{
  description = "Keycard — smartcard authentication module for Logos Basecamp";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";

    # Follow the builder's nixpkgs to avoid Qt ABI mismatches
    nixpkgs.follows = "logos-module-builder/nixpkgs";

    # keycard-qt source (non-flake) — pinned to our fork (xAlisher/keycard-qt)
    # This commit adds Schnorr/BIP340 TLV-unwrap + ECDSA DER fix (not merged upstream).
    # URL uses xAlisher fork explicitly; do NOT switch to status-im/keycard-qt until
    # both fixes land upstream (track: status-im/keycard-qt#96, #132 equivalents).
    keycard-qt-src = {
      url = "github:xAlisher/keycard-qt/5cd0b0d22659fd8564c749787fc86c1374b00223";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, nixpkgs, keycard-qt-src, ... }:
    let
      # Build keycard-qt as a pre-compiled static library for each target system.
      # The builder's mkExternalLib machinery stages it into lib/ before cmake runs;
      # LogosModule.cmake's EXTERNAL_LIBS finds libkeycard-qt.a + include/keycard-qt/*.h.
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      keycardQtPackages = builtins.listToAttrs (map (system:
        let
          pkgs = import nixpkgs { inherit system; };
          drv = pkgs.stdenv.mkDerivation {
            pname = "keycard-qt";
            version = "0.1.0";
            src = keycard-qt-src;

            nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config ];
            buildInputs = [
              pkgs.qt6.qtbase
              pkgs.openssl
              pkgs.pcsclite
            ];

            # Library only — no app wrapping, no tests, no examples
            dontWrapQtApps = true;
            cmakeFlags = [
              "-GNinja"
              "-DCMAKE_BUILD_TYPE=Release"
              "-DBUILD_TESTING=OFF"
              "-DBUILD_EXAMPLES=OFF"
            ];

            # Remove cmake package config files — only lib + headers are needed by
            # the builder's EXTERNAL_LIBS mechanism.  Keeping them would cause the
            # module's cmake setup-hook to fail trying to patch read-only store files.
            postInstall = ''
              rm -rf $out/lib/cmake
            '';
          };
        in { name = system; value = { default = drv; }; }
      ) systems);

    in logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # keycard-qt resolved per-system above.
      # The builder copies $drv/lib/* into lib/ and $drv/include/* into lib/
      # so that LogosModule.cmake EXTERNAL_LIBS finds libkeycard-qt.a + headers.
      externalLibInputs = {
        "keycard-qt" = { packages = keycardQtPackages; };
      };
    };
}
