{
  runCommand,
  build-tools,
  gen-debug-keystore,
}:
{
  apk,
  passwd ? "android",
  debug-keystore ? gen-debug-keystore { inherit passwd; },
}:
runCommand "signed-apk" { } ''
  cp ${apk} unsigned.apk
  chmod +w unsigned.apk
  mkdir $out
  ${build-tools}/apksigner sign --ks ${debug-keystore}/debug.keystore \
  --ks-pass pass:${passwd} unsigned.apk
  mv unsigned.apk $out/signed.apk
''
