{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    gradle2nix-flake.url = "github:expenses/gradle2nix/overrides-fix";
    android-nixpkgs.url = "github:HPRIOR/android-nixpkgs";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cargo-apk-src = {
      url = "path:///home/ashley/projects/cargo-apk";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      gradle2nix-flake,
      android-nixpkgs,
      crane,
      fenix,
      cargo-apk-src,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (gradle2nix-flake.packages.${system}) gradle2nix;
        android-sdk = android-nixpkgs.sdk.${system} (
          sdkPkgs: with sdkPkgs; [
            cmdline-tools-latest
            platform-tools
            platforms-android-30
            emulator
            ndk-bundle
            build-tools-34-0-0
          ]
        );

        environment = rec {
          ANDROID_HOME = "${android-sdk}";
          NDK_HOME = "${android-sdk}/share/android-sdk/ndk-bundle";
          cargo =
            let
              llvm-dir = "${NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64";
              bin-dir = "${llvm-dir}/bin";
            in
            {
              CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER = "${bin-dir}/clang";
              
            };
        };

        rust-targets = [
          #"aarch64-linux-android"
          #"armv7-linux-androideabi"
          #"i686-linux-android"
          "x86_64-linux-android"
        ];

        rust-toolchain =
          with fenix.packages.${system};
          combine (
            [
              stable.cargo
              stable.rustc
            ]
            ++ (builtins.map (target: targets.${target}.stable.toolchain) rust-targets)
          );

        crane-lib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;

        cargo-xbuild = pkgs.callPackage ./nix/cargo-xbuild.nix { crane-lib = (crane.mkLib pkgs); };

        cargo-apk-patched = pkgs.callPackage ./nix/cargo-apk-10.nix {
          crane-lib = (crane.mkLib pkgs);
          inherit cargo-apk-src;
        };

        build-tools = "${android-sdk}/share/android-sdk/build-tools/34.0.0";
      in
      {
        devShells.minimal =
          with pkgs;
          mkShell {
            CARGO_HOME = (crane-lib.vendorCargoDeps { src = ./.; });
            nativeBuildInputs = [
              pkgs.gcc
              rust-toolchain
            ];
            inherit (environment.cargo) CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER;
            RUSTFLAGS = "-Clink-arg=--target=${"x86_64-linux-android"}23";
          };
        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              #gradle2nix
              openjdk
              android-sdk
              rust-toolchain
              # for pnpm
              #corepack
              #cargo-apk-patched
              #cargo-xbuild
            ];
            inherit (environment) ANDROID_HOME NDK_HOME;
            # Setup nix ld for running aapt2
            #NIX_LD = with pkgs;
            #  lib.fileContents "${stdenv.cc}/nix-support/dynamic-linker";
          };
        packages = rec {
          apk = pkgs.runCommand "empty-apk" { } ''
            mkdir $out
            ${build-tools}/aapt package -f -F $out/unaligned.apk -M ${./.}/AndroidManifest.xml -I ${android-sdk}/share/android-sdk/platforms/android-30/android.jar
          '';

          apk-with-lib = pkgs.runCommand "apk-with-lib" { } ''
            cp ${apk}/unaligned.apk .
            chmod +w unaligned.apk
            mkdir lib
            cp -r ${./.}/lib lib/x86_64
            ${build-tools}/aapt add -0 "" unaligned.apk lib/x86_64/libandriud.so
            mkdir $out
            mv unaligned.apk $out
          '';

          aligned-apk = pkgs.runCommand "aligned-apk" { } ''
            mkdir $out
            ${build-tools}/zipalign -f -v 4 ${apk-with-lib}/unaligned.apk $out/aligned.apk
          '';

          debug-key =
            let
              passwd = "android";
            in
            pkgs.runCommand "debug.keystore" { } ''
              mkdir $out
              ${pkgs.openjdk}/bin/keytool -genkey -v -keystore $out/debug.keystore -storepass ${passwd} -alias \
              androiddebugkey -keypass ${passwd} -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA \
              -keysize 2048 -validity 10000
            '';

          signed-apk =
            let
              passwd = "android";
            in
            pkgs.runCommand "signed-apk" { } ''
              cp ${aligned-apk}/aligned.apk .
              chmod +w aligned.apk
              mkdir $out
              ${build-tools}/apksigner sign --ks ${debug-key}/debug.keystore \
              --ks-pass pass:${passwd} aligned.apk
              mv aligned.apk $out
            '';

          cargo-apk-build = crane-lib.buildPackage {
            src = ./.;
            buildPhaseCargoCommand = "cargo apk build --target x86_64-linux-android";
            nativeBuildInputs = [ pkgs.cargo-apk ];
            installPhaseCommand = "mv target/debug/apk $out";
            doCheck = false;
            ANDROID_HOME = "${android-sdk}/share/android-sdk";
            NDK_HOME = environment.NDK_HOME;
            #RUSTFLAGS = "-Clink-arg=--target=${CARGO_BUILD_TARGET}23";
            CARGO_APK_DEV_KEYSTORE = "${debug-key}/debug.keystore";
            CARGO_APK_DEV_KEYSTORE_PASSWORD = "android";
          };
        };
      }
    );
}
