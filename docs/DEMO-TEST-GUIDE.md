# O₂ Platform: Demo Testing Guide

Follow this guide to successfully run all three components of the O₂ pitch demo (The Web Dashboard, The Telegram Bot, and the Android App).

## Prerequisites
1. Ensure your WSL environment is running.
2. Open your terminal in Windows (PowerShell or Git Bash).
3. Ensure you have the Telegram App installed on your phone.
4. Ensure you have Android Studio installed on your Windows machine.

---

## Component 1 & 2: The Core Backend & Telegram Bot (Run via WSL)

Both the PHC Dashboard and the Telegram bot are powered by the FastAPI backend in your WSL environment.

### Step 1: Start the Backend and Dashboard
Open a WSL terminal and run:
```bash
cd ~/dev/AAVISHKAR-PRAVAH/apps/o2_backend
source ../../.venv/bin/activate
python main.py
```
*Wait until you see `Uvicorn running on http://0.0.0.0:8000`.*

### Step 2: Open the Dashboard
On your laptop browser, navigate to:
👉 **http://localhost:8000/dashboard/**
*You should see the premium dark-themed dashboard. Leave this tab open on your screen during the pitch.*

### Step 3: Start the Telegram Bot
Open a **second** WSL terminal and run:
```bash
cd ~/dev/AAVISHKAR-PRAVAH/apps/o2_backend
source ../../.venv/bin/activate
python telegram_bot.py
```
*Wait until you see `Starting polling...`.*

### Step 4: Test the Bot on Your Phone
1. Open Telegram on Phone 1 and search for your bot.
2. Send the command `/start`.
3. Test Voice Triage: Hold the microphone button and say *"I am experiencing a severe headache and my vision is blurry."*
4. **The Magic Moment:** Watch the Telegram bot transcribe and triage the audio, and simultaneously watch the Laptop Dashboard automatically update with a pulsing red "HIGH RISK" alert for patient Lakshmi!

---

## Component 3: The Android Mobile App (Run via Windows Android Studio)

Since we skipped the native WSL Android build, we will build the app natively using Android Studio on your Windows machine.

### Step 1: Open the Project in Android Studio
1. Open **Android Studio** on your Windows laptop.
2. Click **Open** (or File -> Open).
3. In the directory browser, navigate to your WSL filesystem. You can type this directly into the path bar:
   👉 `\\wsl.localhost\Ubuntu\home\syed\dev\AAVISHKAR-PRAVAH\apps\o2_app`
4. Wait for Android Studio to index the project.

### Step 2: Fetch Dependencies
1. Open the Android Studio terminal (at the bottom) or use the GUI.
2. Run `flutter pub get` to ensure all packages are downloaded on the Windows side.

### Step 3: Connect Your Phone
1. Enable **Developer Options** and **USB Debugging** on Phone 2.
2. Connect Phone 2 to your laptop via USB.
3. Ensure your phone appears in the device dropdown menu at the top of Android Studio.

### Step 4: Build and Run
1. Click the green **Play (Run)** button at the top of Android Studio.
2. Gradle will download necessary build tools and compile the app.
3. The app will automatically launch on Phone 2.

### Step 5: Test the App
*   Navigate through the patient list.
*   Demonstrate adding a new vital sign (e.g., Blood Pressure) while the phone's Wi-Fi is turned off to prove the **Offline-First** capability.

---

## Troubleshooting During Pitch
*   **Dashboard not updating:** Ensure the terminal running `python main.py` hasn't crashed. Hard refresh the browser (Ctrl+F5).
*   **Telegram bot not responding:** Ensure the terminal running `python telegram_bot.py` is active. Check your internet connection.
*   **App won't build in Android Studio:** Ensure you opened the `o2_app` folder specifically, not the root `AAVISHKAR-PRAVAH` folder.