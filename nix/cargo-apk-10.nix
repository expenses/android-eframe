{
  crane-lib,
  lib,
  cargo-apk-src,
}:
crane-lib.buildPackage rec {
  src = cargo-apk-src;
  doCheck = false;
  cargoExtraArgs = "-p cargo-apk";
}
