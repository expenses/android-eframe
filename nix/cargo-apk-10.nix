{
  crane-lib,
  lib,
  cargo-apk-src,
}:
crane-lib.buildPackage rec {
  #pname = "cargo-apk";
  #version = "1.0.0";
  src = cargo-apk-src;
  #cargoToml = src + "/cargo-apk/Cargo.toml";
  doCheck = false;
  cargoExtraArgs = "-p cargo-apk";
  #buildPhaseCargoCommand = "cargo build --release -p cargo-apk";
}
