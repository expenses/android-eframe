{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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
      android-nixpkgs,
      crane,
      fenix,
      cargo-apk-src,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        inherit (android-nixpkgs.packages.${system}) ndk-bundle;

        build-tools = android-nixpkgs.packages.${system}.build-tools-34-0-0;

        environment = {
          ANDROID_HOME = "${
            android-nixpkgs.sdk.${system} (
              sdkPkgs: with sdkPkgs; [
                cmdline-tools-latest
                platforms-android-30
                build-tools-34-0-0
              ]
            )
          }/share/android-sdk";
          NDK_HOME = "${ndk-bundle}";
        };

        rust-targets = {
          "arm64-v8a" = "aarch64-linux-android";
          "armv7" = "armv7-linux-androideabi";
          "i686" = "i686-linux-android";
          "x86_64" = "x86_64-linux-android";
        };

        rust-toolchain =
          with fenix.packages.${system};
          combine (
            [
              stable.cargo
              stable.rustc
            ]
            ++ (builtins.map (target: targets.${target}.stable.toolchain) (builtins.attrValues rust-targets))
          );

        crane-lib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;

        cargo-apk-patched = pkgs.callPackage ./nix/cargo-apk-10.nix {
          crane-lib = (crane.mkLib pkgs);
          inherit cargo-apk-src;
        };

        fake-libgcc-a = pkgs.writeTextDir "libgcc.a" "INPUT(-lunwind)";

        src = crane-lib.cleanCargoSource ./.;

        gen-debug-keystore = pkgs.callPackage ./nix/debug-keystore.nix { };
        align-apk = pkgs.callPackage ./nix/align-apk.nix { inherit build-tools; };
        sign-apk = pkgs.callPackage ./nix/sign-apk.nix { inherit build-tools gen-debug-keystore; };
        generate-manifest = pkgs.callPackage ./nix/generate-manifest.nix { };
        create-apk = pkgs.callPackage ./nix/create-apk.nix {
          inherit build-tools generate-manifest;
          inherit (android-nixpkgs.packages.${system}) platforms-android-30;
        };
        debug-keystore = gen-debug-keystore {};

        env-vars-for =
          target:
          let
            link-arg = "--target=${target}23";
            target-upper = builtins.replaceStrings [ "-" ] [ "_" ] (pkgs.lib.strings.toUpper target);
            bin-dir = "${ndk-bundle}/toolchains/llvm/prebuilt/linux-x86_64/bin";
          in
          {
            "RUSTFLAGS" = "-Clink-arg=${link-arg}";
            "CARGO_TARGET_${target-upper}_LINKER" = "${bin-dir}/clang";
            #"CARGO_TARGET_${target-upper}_ANDROID_AR" = "${bin-dir}/llvm-ar";
            #"AR_${target}" = "${bin-dir}/llvm-ar";
            #"CC_${target}" = "${bin-dir}/clang";
            #"CFLAGS_${target}" = link-arg;
            #"CXXFLAGS_${target}" = link-arg;
            #"CXX_${target}" = "${bin-dir}/clang++";
          };

        libraries = (
          builtins.mapAttrs (
            name: target:
            crane-lib.buildPackage (
              {
                inherit src;
                CARGO_BUILD_TARGET = target;
                doCheck = false;
              }
              // (env-vars-for target)
            )
          ) rust-targets
        );
      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            CARGO_HOME = (crane-lib.vendorCargoDeps { src = ./.; });
            nativeBuildInputs = [
              rust-toolchain
              cargo-apk-patched
            ];
            inherit (environment) ANDROID_HOME NDK_HOME;
          };
        packages = (
          rec {

            inherit fake-libgcc-a;

            manifest = generate-manifest { inherit src; };

            x86_64-apk = sign-apk { apk =
              "${align-apk "${create-apk {
                inherit src; libraries = {inherit (libraries) x86_64;};}
              }/apk.apk"}/aligned.apk";
            };

            apk-with-lib = create-apk { inherit src libraries; };

            aligned-apk = align-apk "${apk-with-lib}/apk.apk";

            signed-apk = sign-apk { apk = "${aligned-apk}/aligned.apk"; };

            run = pkgs.writeShellScriptBin "run" ''
              adb install ${x86_64-apk}/signed.apk
              adb shell am start -a android.intent.action.MAIN -n "rust.glit/android.app.NativeActivity"
              adb logcat RustStdoutStderr:V glit:D '*:S'
            '';

            cargo-apk-build = crane-lib.buildPackage {
              inherit src;
              doCheck = false;
              buildPhaseCargoCommand = "cargo apk build --target x86_64-linux-android";
              nativeBuildInputs = [ cargo-apk-patched ];
              installPhaseCommand = "mv target/debug/apk $out";
              inherit (environment) ANDROID_HOME NDK_HOME;
              CARGO_APK_DEV_KEYSTORE = "${debug-keystore}/debug.keystore";
              CARGO_APK_DEV_KEYSTORE_PASSWORD = "android";
            };
          }
          // libraries
        );
      }
    );
}
