{ runCommand, build-tools }:
apk:
runCommand "aligned.apk" { } ''
  mkdir $out
  ${build-tools}/zipalign -f -v 4 ${apk} $out/aligned.apk
''
