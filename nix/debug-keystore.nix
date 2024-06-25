{
  runCommand,
  openjdk
}:
{
  passwd ? "android"
}:
runCommand "debug.keystore" { } ''
  mkdir $out
  ${openjdk}/bin/keytool -genkey -v -keystore $out/debug.keystore -storepass ${passwd} -alias \
  androiddebugkey -keypass ${passwd} -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA \
  -keysize 2048 -validity 10000
''
