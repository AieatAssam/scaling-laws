# Android release builds

The `Android` export preset produces a release-signed APK. `Android AAB` uses Godot's Gradle Android build template to produce the release-signed Android App Bundle for Google Play. Both use package ID `net.aieat.scalinglaws`, min SDK 24, target SDK 36, and arm64-v8a plus armeabi-v7a; the game requests no Android permissions, including `INTERNET`.

## Signing keys

GitHub Actions reads these repository secrets and writes the decoded PKCS12 key only to the runner's temporary directory:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded PKCS12 keystore
- `ANDROID_KEYSTORE_PASSWORD`: store and key password
- `ANDROID_KEY_ALIAS`: upload key alias (`upload`)

Godot receives them through `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER` and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. If secrets are unavailable (such as in a fork), CI builds and uploads a debug APK only; it skips the AAB.

Keep a local copy outside the repository at `~/.keys/scaling-laws/upload.p12`. Create `~/.keys/scaling-laws/signing.env` with:

```sh
export KEYSTORE="$HOME/.keys/scaling-laws/upload.p12"
export ALIAS="upload"
export PASSWORD="your-keystore-password"
```

Restrict access to the files (`chmod 700 ~/.keys/scaling-laws && chmod 600 ~/.keys/scaling-laws/*`). With Godot 4.7.2, Java 17 and the Android SDK packages below installed, run:

```sh
source ~/.keys/scaling-laws/signing.env
tools/android_release.sh
```

The helper writes `build/android/ScalingLaws.apk` and `build/android/ScalingLaws.aab`. It installs the project Gradle template on first run. The generated `android/` directory is ignored by Git.

Godot 4.7's Android config specifies Android SDK Platform 36, Build-Tools 36.1.0, NDK 29.0.14206865 and min SDK 24; the Godot 4.7 export guide recommends JDK 17. Install command-line packages with `sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.1.0" "ndk;29.0.14206865" "cmake;3.22.1"`.

## Google Play

1. Create the app in Play Console and make the first upload manually.
2. Enrol in Play App Signing, using this same key as the **upload key**. Google Play will manage the app-signing key used for installs.
3. Upload `ScalingLaws.aab` for subsequent releases. The APK is for direct sideloading.

The release workflow can also be run with `workflow_dispatch` and `build_android` enabled. That produces downloadable workflow artifacts without creating a GitHub Release.

Android version codes come from the numeric `MAJOR.MINOR.PATCH` project version: `MAJOR*1,000,000 + MINOR*1,000 + PATCH`. Keep each component at 999 or below and increase the semantic version for every release so Play receives a higher code.
