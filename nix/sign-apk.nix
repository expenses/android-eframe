{
  runCommand,
  build-tools,
  callPackage,
}:
{
  apk,
  passwd ? "android",
  debug-keystore ? callPackage ./debug-keystore.nix { inherit passwd; },
}:
runCommand "signed-apk" { } ''
  cp ${apk} unsigned.apk
  chmod +w unsigned.apk
  mkdir $out
  ${build-tools}/apksigner sign --ks ${debug-keystore}/debug.keystore \
  --ks-pass pass:${passwd} unsigned.apk
  mv unsigned.apk $out/signed.apk
''
