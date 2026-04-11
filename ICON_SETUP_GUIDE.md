# App Icon Setup Guide

## Current Status
The app currently uses the default Flutter logo. To change it to custom MindTwin icons:

## Quick Setup (Option 1: Use Online Icon Generator)

1. **Generate Icon Images:**
   - Go to: https://icon.kitchen or https://appicon.co
   - Create a 1024x1024 icon with:
     - Background: Dark blue/purple (#1a1a2e)
     - Foreground: Brain/mind symbol or "MT" text in teal (#4FC3F7)
   
2. **Download and Place Icons:**
   ```
   mindtwin/
   └── assets/
       └── icon/
           ├── app_icon.png (1024x1024)
           └── app_icon_foreground.png (1024x1024, transparent bg)
   ```

3. **Generate Platform Icons:**
   ```powershell
   cd C:\mindtwin
   flutter pub get
   flutter pub run flutter_launcher_icons
   ```

4. **Rebuild APKs:**
   ```powershell
   flutter build apk --dart-define=APP_MODE=patient --dart-define=MINDTWIN_API_BASE_URL=http://192.168.1.5:5000 --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
   flutter build apk --dart-define=APP_MODE=therapist --dart-define=MINDTWIN_API_BASE_URL=http://192.168.1.5:5000 --dart-define=MINDTWIN_CLINIC_CODE=CLINIC001
   ```

## Option 2: Simple Colored Icons (Temporary)

If you want quick placeholder icons with just colors:

1. **Create simple colored squares:**
   - Patient icon: Teal background (#4FC3F7)
   - Therapist icon: Indigo background (#5C6BC0)

2. **Use any image editor (Paint, Photoshop, GIMP, Canva):**
   - Create 1024x1024 image
   - Fill with the color
   - Add white text "P" for patient or "T" for therapist
   - Save as `app_icon.png`

3. **For foreground (adaptive icon):**
   - Same design but with transparent background
   - Just the letter/symbol in the center
   - Save as `app_icon_foreground.png`

## Option 3: Different Icons for Patient vs Therapist

To have different icons per build mode, create:

```yaml
# In pubspec.yaml, update flutter_icons section:
flutter_icons:
  android: true
  ios: true
  image_path_android: "assets/icon/app_icon.png"
  image_path_ios: "assets/icon/app_icon.png"
```

Then manually replace icons before each build, or use build flavors (advanced).

## Icon Specifications

### Android
- **Launcher icon**: 1024x1024 PNG
- **Adaptive icon foreground**: 1024x1024 PNG with transparency
- **Adaptive icon background**: Solid color or 1024x1024 PNG

### iOS  
- **App icon**: 1024x1024 PNG (no transparency)

## Colors for MindTwin
- Patient theme: Teal `#4FC3F7`
- Therapist theme: Indigo `#5C6BC0`
- Background: Dark `#1a1a2e`
- Accent: Purple `#7E57C2`

## Troubleshooting

**Icon not updating after rebuild:**
1. Uninstall old app from phone
2. Clean build: `flutter clean`
3. Rebuild: `flutter build apk ...`
4. Install fresh APK

**"assets/icon/app_icon.png not found" error:**
- Ensure you created the `assets/icon` folder at project root
- Ensure `app_icon.png` file exists in that folder
- Run `flutter pub get` after adding files
