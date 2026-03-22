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
  };

  outputs = { self, nixpkgs, flake-utils, logos-cpp-sdk, logos-liblogos }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosHeaders = logos-liblogos.packages.${system}.default;

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

        # Packages will be added in Phase 5
        packages = {
          # TODO: keycard-core LGX package
          # TODO: keycard-ui LGX package
        };
      }
    );
}
