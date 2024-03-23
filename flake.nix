{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    flake-utils,
    nixpkgs,
    ...
  }: let
    mkDevkit = pkgs: {
      name,
      src,
      includePaths ? [],
    }:
      pkgs.stdenv.mkDerivation (finalAttrs: {
        inherit name;

        src = pkgs.dockerTools.pullImage (pkgs.lib.importJSON src);

        nativeBuildInputs = with pkgs; [autoPatchelfHook];

        phases = ["buildPhase" "fixupPhase"];

        buildPhase = ''
          tar -xf $src

          for archive in $(find *.tar)
          do
            tar -xf $archive
          done

          mkdir -p $out
          cp -r opt $out/opt
          ln -sf $out/opt/devkitpro/tools/bin $out/bin
        '';

        fixupPhase = let
          libPath = pkgs.lib.makeLibraryPath (with pkgs; [
            stdenv.cc.cc.lib
          ]);
        in ''
          for bin in $(find $out -executable -follow -type f)
          do
            file $bin | grep "ELF" && patchelf \
              --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath "${libPath}" \
              $bin || continue
          done
        '';

        passthru = rec {
          CPATH = pkgs.lib.makeSearchPath "include" (builtins.map (x: "${finalAttrs.finalPackage}/opt/devkitpro/${x}") includePaths);

          shellHook = ''
            export DEVKITPRO="${finalAttrs.finalPackage}/opt/devkitpro"
            export DEVKITARM="$DEVKITPRO/devkitARM"
            export CPATH=${CPATH}
          '';
        };
      });

    packages = pkgs: {
      devkitARM = mkDevkit pkgs {
        name = "devkitARM";
        src = ./sources/devkitarm.json;
        includePaths = [
          "devkitARM"
          "devkitARM/arm-none-eabi"
          "libctru"
          "libgba"
          "libmirko"
          "libnds"
          "liborcus"
          "libtonc"
          "portlibs/3ds"
          "portlibs/armv4t"
          "portlibs/gba"
          "portlibs/gp2x"
          "portlibs/nds"
        ];
      };
    };
    packages = pkgs: {
    libctrpf = mkDevkit pkgs {
      name = "libctrpf";
      src = ./sources/libctrpf.json;
      includePaths = [
        "libctrpf/include"
      ];
    };
  };
  in
    (flake-utils.lib.eachDefaultSystem (system: let
      pkgs' = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        inherit (packages pkgs') devkitARM libctrpf;
      };
    }))
    // {
      overlays.default = final: prev: {
        devkitNix = {
          inherit (packages prev) devkitARM libctrpf;
        };
      };
    };
}
