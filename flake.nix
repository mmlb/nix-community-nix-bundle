{
  description = "The purely functional package manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;

      getExe =
        x:
        lib.getExe' x (
          x.meta.mainProgram or (lib.warn
            "nix-bundle: Package ${
              lib.strings.escapeNixIdentifier x.meta.name or x.pname or x.name
            } does not have the meta.mainProgram attribute. Assuming you want '${lib.getName x}'."
            lib.getName
            x
          )
        );
    in
    inputs.utils.lib.eachDefaultSystem (
      system:
      let
        nixpkgs = inputs.nixpkgs.legacyPackages.${system};
        nix-bundle = import inputs.self { inherit nixpkgs; };
        nix-user-chroot = nix-bundle.nix-user-chroot;
        chrooter =
          drv:
          nixpkgs.writeScript "chroot-${drv.name}" ''
            #!/bin/sh
            .${nix-user-chroot}/bin/nix-user-chroot -n ./nix -- ${lib.getExe drv} "$@"
          '';

        makeTar =
          drv:
          let
            targets = [ drv ];
            closure = nixpkgs.closureInfo { rootPaths = targets; };
            exportReferencesGraph = map (x: [
              ("closure-" + baseNameOf x)
              x
            ]) targets;
          in
          nixpkgs.stdenv.mkDerivation {
            inherit exportReferencesGraph;
            name = "${drv.name}.tar";
            buildCommand =
              #bash
              ''
                storePaths=$(cat ${closure}/store-paths)

                # https://reproducible-builds.org/docs/archives
                tar -cf - \
                  --owner=0 --group=0 --mode=u+rw,uga+r \
                  --hard-dereference \
                  --mtime="@$SOURCE_DATE_EPOCH" \
                  --format=gnu \
                  --sort=name \
                  $storePaths > $out
              '';
          };

        makeTarXz =
          drv:
          nixpkgs.stdenv.mkDerivation {
            name = "${drv.name}.tar.xz";
            nativeBuildInputs = [ nixpkgs.xz ];
            buildCommand = # bash
              ''xz -vv <${makeTar drv} >$out'';
          };

        mkBundle =
          tarballer: drv:
          let
            chrooted = chrooter drv;
            tarball = tarballer chrooted;
            run = chrooted;
          in
          nixpkgs.stdenv.mkDerivation {
            name = "bundle-${tarball.name}";
            buildCommand =
              #bash
              ''
                case ${tarball} in
                *xz) decompressor='xzcat -T0';;
                *) decompressor=cat;;
                esac
                lines=$(wc -l ${./self-extract-and-run.sh} | awk '{print $1+1}')
                sed \
                  -e "/^DECOMPRESSOR=/ s|=.*|='$decompressor'|" \
                  -e "/^NUM_LINES_TO_SKIP=/ s|=.*|=$lines|" \
                  -e "/^RUN=/ s|=.*|=.${run}|" \
                  ${./self-extract-and-run.sh} > $out
                cat ${tarball} >>$out
                chmod +x $out
              '';
          };

        makeBundle = drv: mkBundle makeTar drv;
        makeBundleXz = drv: mkBundle makeTarXz drv;

        nix-bundle-fun =
          drv:
          let
            script = (chrooter drv);
          in
          nix-bundle.makebootstrap {
            drvToBundle = drv;
            targets = [ script ];
            startup = ".${builtins.unsafeDiscardStringContext script} '\"$@\"'";
          };
      in
      {
        bundlers = {
          default = inputs.self.bundlers.${system}.nix-bundle;
          nix-bundle = drv: nix-bundle-fun { inherit drv; };
        };

        packages = {
          inherit nix-user-chroot;
        };

        lib = {
          inherit
            chrooter
            makeBundle
            makeBundleXz
            makeTar
            makeTarXz
            ;
        };

        formatter = inputs.nixpkgs.legacyPackages.${system}.nixfmt-tree;
      }
    );
}
