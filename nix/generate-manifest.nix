{ writeTextDir }:
{
  src ? null,
  cargo-toml ? src + "/Cargo.toml",
  cargo-contents ? builtins.fromTOML (builtins.readFile cargo-toml),
  name ? builtins.replaceStrings ["-"] ["_"] cargo-contents.package.name,
  version ? cargo-contents.package.version,
  package-name ? "rust.${name}",
  min-sdk-version ? "23",
  target-sdk-version ? "30",
}:
writeTextDir "AndroidManifest.xml" ''
  <manifest
      xmlns:android="http://schemas.android.com/apk/res/android"
      package="${package-name}"
      android:versionCode="16777475"
      android:versionName="${version}"
  >
      <uses-sdk android:minSdkVersion="${min-sdk-version}" android:targetSdkVersion="${target-sdk-version}"/>
      <application android:debuggable="true" android:hasCode="false" android:label="${name}">
          <activity android:configChanges="orientation|keyboardHidden|screenSize" android:name="android.app.NativeActivity">
              <meta-data android:name="android.app.lib_name" android:value="${name}"/>
              <intent-filter>
                  <action android:name="android.intent.action.MAIN"/>
                  <category android:name="android.intent.category.LAUNCHER"/>
              </intent-filter>
          </activity>
      </application>
  </manifest>
''
