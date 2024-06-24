{
  runCommand,
  build-tools,
  platforms-android-30,
  lib,
  callPackage,
  generate-manifest,
}:
{
  src ? ./.,
  android-manifest ? "${generate-manifest { inherit src; }}/AndroidManifest.xml",
  libraries,
}:
runCommand "create-apk" { } ''
  cp ${android-manifest} AndroidManifest.xml
  ${build-tools}/aapt package -f -F apk.apk -M AndroidManifest.xml -I ${platforms-android-30}/android.jar        
  mkdir lib
  ${
    let
      commands = builtins.attrValues (
        builtins.mapAttrs (name: path: ''
          cp -r ${path}/lib lib/${name}
          ${build-tools}/aapt add -0 "" apk.apk lib/${name}/$(basename $(ls lib/${name}/*.so))
        '') libraries
      );
    in
    lib.strings.concatStringsSep "\n" commands
  }
  mkdir $out
  mv apk.apk $out
''
