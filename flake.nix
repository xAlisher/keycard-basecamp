{
  description = "Keycard Basecamp — standalone Keycard smartcard authentication module";

  inputs = {
    # Follow logos-cpp-sdk for Qt compatibility
    nixpkgs.follows = "logos-cpp-sdk/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos = {
      url = "github:logos-co/logos-liblogos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Testing tools (Phase 1 - pinned versions for reproducibility)
    logos-logoscore-cli = {
      url = "github:logos-co/logos-logoscore-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    logos-standalone-app = {
      url = "github:logos-co/logos-standalone-app";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    logos-module = {
      url = "github:logos-co/logos-module";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, logos-cpp-sdk, logos-liblogos, logos-logoscore-cli, logos-standalone-app, logos-module }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosHeaders = logos-liblogos.packages.${system}.default;

        # Fetch keycard-qt dependency
        keycard-qt-src = pkgs.fetchFromGitHub {
          owner = "status-im";
          repo = "keycard-qt";
          rev = "3c01bc114f0a38e91147793e96d7a4ebd68301a6";
          sha256 = "sha256-ZwR7Rt///TkUAp80TMT3i9TamngNoyxvGyhN+mZzb6w=";
        };

        # Development shell with all dependencies
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.qt6.qtbase
            pkgs.libsodium
            pkgs.pcsclite        # PC/SC library
            pkgs.pcsclite.dev    # PC/SC headers
          ];

          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_HEADERS="${logosHeaders}/include"
            export PKG_CONFIG_PATH="${pkgs.pcsclite.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"

            echo "Keycard Basecamp development environment"
            echo "  Logos SDK: $LOGOS_CPP_SDK_ROOT"
            echo "  Logos Headers: $LOGOS_LIBLOGOS_HEADERS"
            echo "  PC/SC: ${pkgs.pcsclite.dev}"
            echo ""
            echo "Build commands:"
            echo "  cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug"
            echo "  cmake --build build"
            echo "  cmake --install build --prefix ~/.local/share/Logos/LogosBasecampDev"
          '';
        };

      in {
        # Development shell
        devShells.default = devShell;

        packages = {
          # Core module for nix-bundle-lgx: lib/keycard_plugin.so + lib/manifest.json
          lib = pkgs.stdenv.mkDerivation {
          pname = "keycard-core";
          version = "1.0.0";
          src = ./.;
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.openssl
            pkgs.libsodium
            pkgs.pcsclite
          ];
          cmakeFlags = [
            "-GNinja"
            "-DCMAKE_BUILD_TYPE=Release"
            "-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}"
          ];
          # This is a library (plugin), not an application
          dontWrapQtApps = true;
          preConfigure = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_HEADERS="${logosHeaders}/include"
          '';
          # Only build the core plugin target
          buildPhase = ''
            cmake --build . --target keycard_plugin -j$NIX_BUILD_CORES
          '';
          installPhase = ''
            mkdir -p $out/lib
            cp keycard-core/keycard_plugin.so $out/lib/
            cp ${./metadata.json} $out/lib/metadata.json
            cp ${./keycard-core/modules/keycard/manifest.json} $out/lib/manifest.json
          '';

          # IMPORTANT: libpcsclite bundling limitation
          # The portable bundler automatically includes libpcsclite.so.1 because
          # keycard_plugin.so depends on it via keycard-qt. However, bundled
          # libpcsclite cannot connect to the system pcscd daemon socket, breaking
          # smart card detection.
          #
          # Canonical packaging command (single-step, produces working LGX):
          #   nix run .#package-lgx
          #
          # This command bundles with portable bundler, then automatically removes
          # libpcsclite from the LGX, producing a shippable artifact that uses
          # system libpcsclite for proper pcscd connectivity.
        };

          # UI plugin for nix-bundle-lgx: lib/Main.qml + lib/metadata.json
          ui = pkgs.stdenv.mkDerivation {
            pname = "keycard-ui";
            version = "1.0.0";
            src = ./keycard-ui/plugins/keycard-ui;
            dontBuild = true;
            dontConfigure = true;
            installPhase = ''
              mkdir -p $out/lib
              cp ${./keycard-ui/qml/Main.qml} $out/lib/Main.qml
              cp metadata.json $out/lib/
            '';
          };

          # Default package
          default = pkgs.stdenv.mkDerivation {
            pname = "keycard-core";
            version = "1.0.0";
            src = ./.;
            nativeBuildInputs = [
              pkgs.cmake
              pkgs.ninja
              pkgs.pkg-config
            ];
            buildInputs = [
              pkgs.qt6.qtbase
              pkgs.openssl
              pkgs.libsodium
              pkgs.pcsclite
            ];
            cmakeFlags = [
              "-GNinja"
              "-DCMAKE_BUILD_TYPE=Release"
              "-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}"
            ];
            dontWrapQtApps = true;
            preConfigure = ''
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              export LOGOS_LIBLOGOS_HEADERS="${logosHeaders}/include"
            '';
            buildPhase = ''
              cmake --build . --target keycard_plugin -j$NIX_BUILD_CORES
            '';
            installPhase = ''
              mkdir -p $out/lib
              cp keycard-core/keycard_plugin.so $out/lib/
              cp ${./metadata.json} $out/lib/metadata.json
              cp ${./keycard-core/modules/keycard/manifest.json} $out/lib/manifest.json
            '';
          };
        };

        # Canonical LGX packaging command (single-step, produces working artifacts)
        apps = {
          package-lgx = {
            type = "app";
            program = "${pkgs.writeShellScript "package-lgx" ''
              ${builtins.readFile ./scripts/package-lgx.sh}
            ''}";
          };

          # Phase 1: Testing infrastructure (pinned tools)
          test-with-logoscore = {
            type = "app";
            program = "${pkgs.writeShellScript "test-with-logoscore" ''
              # Test keycard module with logoscore (headless)
              echo "Testing keycard module with logoscore..."
              ${logos-logoscore-cli.packages.${system}.default}/bin/logoscore \
                --module result/lib/Logos/Modules/keycard
            ''}";
          };

          test-ui-standalone = {
            type = "app";
            program = "${pkgs.writeShellScript "test-ui-standalone" ''
              # Test QML UI in isolation
              echo "Testing keycard UI with logos-standalone-app..."
              ${logos-standalone-app.packages.${system}.default}/bin/logos-standalone-app \
                --ui result/lib/Logos/Plugins/keycard-ui \
                --module result/lib/Logos/Modules/keycard
            ''}";
          };

          inspect-module = {
            type = "app";
            program = "${pkgs.writeShellScript "inspect-module" ''
              # Inspect module with lm CLI
              MODULE_SO="result/lib/Logos/Modules/keycard/keycard_plugin.so"

              if [ ! -f "$MODULE_SO" ]; then
                echo "Error: Module not found at $MODULE_SO"
                echo "Run 'nix build' first"
                exit 1
              fi

              echo "=== Module Info ==="
              ${logos-module.packages.${system}.default}/bin/lm info "$MODULE_SO"

              echo -e "\n=== Available Methods ==="
              ${logos-module.packages.${system}.default}/bin/lm methods "$MODULE_SO"

              echo -e "\n=== Validation ==="
              ${logos-module.packages.${system}.default}/bin/lm validate "$MODULE_SO"
            ''}";
          };
        };
      }
    );
}
