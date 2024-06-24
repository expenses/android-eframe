{ writeTextDir }:
{
  src ? null,
  cargo-toml ? src + "/Cargo.toml",
  cargo-contents ? builtins.fromTOML (builtins.readFile cargo-toml),
  name ? cargo-contents.package.name,
  package-name ? "rust.${name}",
  min-sdk-version ? "23",
  target-sdk-version ? "30",
}:
writeTextDir "AndroidManifest.xml" ''
  <manifest
      xmlns:android="http://schemas.android.com/apk/res/android"
      package="${package-name}"
      android:versionCode="16777475"
      android:versionName="0.1.3"
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
