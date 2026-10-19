# CrayCare User Manual — Final Content

Copy-paste ready text for every spread. Bracketed `[BOLD TEAL]` marks are the
words that are highlighted in teal in the layout. `⚠ FIX` marks a change needed
in the current PNG (already applied in `pages/`).

All product behaviour below was verified against the app source, not guessed:

| Claim | Source |
|---|---|
| Bottom nav = Dashboard / Analytics / Tank / Controls / Notifications | `lib/screens/main_shell.dart:53-57` |
| Controls has two tabs: Feeding, Actuators | `lib/screens/controls_screen.dart:1062-1063` |
| Aeration = Aerator 1 + Aerator 2, Filtration = Water Pump | `lib/widgets/controls/actuators_tab.dart:35,50` |
| Actuator modes = off / auto / on | `lib/widgets/controls/actuator_group.dart:303` |
| Feed amount 1–200 g, whole grams, 1 swing per gram | `functions/notifications/feeder_schedule_mutation.js:27-33` |
| Feed Now sheet: "Feed amount (g)", hint "Enter 1–200", button "Dispense Feed" | `lib/widgets/controls/feed_now_sheet.dart:76,77,128` |
| "View all N schedules" | `lib/widgets/controls/feeder_tab.dart:868` |
| Schedules anchored to Asia/Manila | `lib/screens/controls_screen.dart:29` |
| "Feeder Offline" / "Feed Blocked" | `lib/widgets/controls/feeder_tab.dart:564,571` |
| Dashboard sections | `lib/screens/dashboard_screen.dart:209-251` |
| Tank tabs = Overview / Sampling / Growth | `lib/screens/production_screen.dart:276-277` |
| WQAD statuses = Normal / Unusual / Insufficient | `lib/widgets/dashboard/water_quality_anomaly_detection_card.dart:121` |
| WQAD card = Insight + Suggested Checks | `lib/widgets/dashboard/water_quality_anomaly_detection_card.dart:379,386` |
| Analytics charts = Temperature, pH, DO₂, Turbidity, Water Level, Feed Level | `lib/screens/analytics_screen.dart:706-755` |
| Settings menu = Edit Profile, Change/Create Password, Notifications, Sensor Thresholds, Logout | `lib/widgets/settings/settings_menu.dart:39-93` |

---

## SPREAD 1 — Cover (right) / About CrayCare (left)

**Back cover — ABOUT CRAYCARE**

> **[BOLD TEAL]CrayCare** is an IoT- and mobile-based system that helps crayfish
> farmers monitor water quality, manage feeding, control tank devices, view
> real-time and historical data, and receive alerts for unusual water conditions.

**DEVELOPERS**

- Montante, Justine Bong
- Montipalco, Jenny Rose
- Nuite, Bryan Ace
- Petallano, Dave
- Vilan, Sofia

**Front cover** — logo lockup, `CrayCare`, `USER MANUAL`.

---

## SPREAD 2 — Downloading the CrayCare Application

**Section header:** `DOWNLOADING THE CRAYCARE APPLICATION`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **SCAN QR CODE** | Open your phone's camera and scan the [BOLD TEAL]qr code |
| 2 | **VISIT THE LINK** | Tap the link above to open the CrayCare [BOLD TEAL]download page in your mobile browser. |
| 3 | **TAP THE DOWNLOAD BUTTON** | Tap the [BOLD TEAL]Download for Android button to begin downloading the latest CrayCare APK to your Android device. |

> ⚠ **FIX (page 1):** the "VISIT THE LINK" badge has **no number** and the
> download button is numbered **2**. It must read **2 VISIT THE LINK** and
> **3 TAP THE DOWNLOAD BUTTON**. Already patched in `pages/page-02-fixed.png`.

> **Left half of the spread is empty** — use it for the **TABLE OF CONTENTS**
> (see the TOC block at the end of this file).

---

## SPREAD 3 — Installing and Opening the Application

**Section header (right page):** `OPENING THE APPLICATION`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN THE CRAYCARE APP** | Find the CrayCare app icon on your phone, then tap it to open the application. |
| 2 | **WAIT FOR THE APP TO LOAD** | Wait for the CrayCare [BOLD TEAL]splash screen to finish loading. The application will automatically proceed to the login screen. |
| 3 | **TAP "DOWNLOAD ANYWAY"** | When this prompt appears, tap [BOLD TEAL]"Download anyway" to continue. |
| 4 | **SECURITY WARNING** | Tap [BOLD TEAL]"Settings" to allow installation from this source. |
| 5 | **ALLOW FROM THIS SOURCE** | Turn on [BOLD TEAL]"Allow from this source". Then, go back and continue. |
| 6 | **TAP "INSTALL"** | Tap [BOLD TEAL]"Install" to start installing the CrayCare application. |
| 7 | **INSTALLING THE APP** | Please wait while CrayCare is being installed on your device. |

> 📌 **NOTE:** Please wait until the loading process is complete. Do not close the
> application during initialization to ensure proper startup.

> ⚠ **LOGIC FIX (recommended):** steps 1–2 tell the reader to open an app that
> is not installed yet, and steps 3–7 are installation steps. Split the section:
>
> - **Section A — `INSTALLING THE APPLICATION`** = steps 1–5 above
>   (Download anyway → Security warning → Allow from this source → Tap Install →
>   Installing)
> - **Section B — `OPENING THE APPLICATION`** = steps 1–2 above
>   (Open the CrayCare app → Wait for the app to load)
>
> Alternatively, keep one section but move steps 1–2 **after** step 7.

---

## SPREAD 4 — Account Registration / Account Login

**Left header:** `ACCOUNT REGISTRATION`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **FILL IN YOUR DETAILS** | Enter your [BOLD TEAL]Full Name, [BOLD TEAL]Email Address and [BOLD TEAL]Password. Then tap [BOLD TEAL]"Sign up" to create your account. |
| 2 | **VERIFY YOUR EMAIL** | Check your email [BOLD TEAL]inbox (and spam folder) for a message from CrayCare. Tap the verification link in the email to continue. |
| 3 | **RETURN TO THE APP** | After clicking the verification link, return to the CrayCare app. Tap [BOLD TEAL]"I have clicked the link" button to continue your registration. |
| 4 | **EMAIL VERIFIED** | Once the email has been verified, you will see the [BOLD TEAL]"Email Verified!" confirmation message. Tap [BOLD TEAL]"Go to Dashboard" to start using CrayCare. |

> 📌 **NOTE (step 1):** You can also sign up using your google account.
> 📌 **NOTE (step 2):** If you can't find the email, check your Spam folder.
> 📌 **NOTE (step 3):** If you didn't receive the email, you can resend the link.

**Right header:** `ACCOUNT LOGIN / FORGOT PASSWORD`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **ENTER YOUR CREDENTIALS** | Enter your registered [BOLD TEAL]Email Address and [BOLD TEAL]Password in the corresponding fields. Then Tap [BOLD TEAL]"Sign In" to access your account. |
| 2 | **FORGOT YOUR PASSWORD?** | If you forgot your password, tap [BOLD TEAL]"Forgot Password?" on the login screen to request a password reset. |
| 3 | **SEND RESET LINK** | After clicking [BOLD TEAL]"Forgot Password?", the [BOLD TEAL]"Send Reset Link" dialog will appear. Enter your registered email address, then tap [BOLD TEAL]"Send Reset Link" to receive a password reset link via email. |
| 4 | **RESET LINK VIA EMAIL** | Open the password reset email from CrayCare. Tap the [BOLD TEAL]Reset Link to continue to the password reset page. After that, create your [BOLD TEAL]New Password then save. You can now use your new password to sign in to CrayCare. |

> 📌 **NOTE (step 1):** Enable [BOLD TEAL]"Remember me" to stay signed in and avoid
> entering your credentials every time you open the app.
> 📌 **NOTE (step 3):** Check your inbox and Spam folder if you don't receive the email.

---

## SPREAD 5 — Getting Started with the Dashboard

**Left header:** `GETTING STARTED WITH THE DASHBOARD`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **ENABLE NOTIFICATIONS** | After signing in, the notification prompt appears. Tap [BOLD TEAL]"Enable Notifications" to receive tank updates and reminders, or tap [BOLD TEAL]"Maybe Later" to continue without enabling them. |
| 2 | **OPEN THE TANK MODULE** | From the Dashboard, tap [BOLD TEAL]"Tank" in the bottom navigation bar to open Tank Management. |
| 3 | **TAP "INITIALIZE TANK"** | On the Tank Management screen, tap [BOLD TEAL]"Initialize Tank" to open the Grow-Out Initialization form. |
| 4 | **INITIAL TANK SETUP** | After tapping [BOLD TEAL]"Initialize Tank", the Grow-Out Initialization form appears. Enter the [BOLD TEAL]batch name, [BOLD TEAL]initial population, and [BOLD TEAL]sample size, then record each sampled crayfish's weight and length. |

**Right page (continuation) — header should read
`GETTING STARTED WITH THE DASHBOARD (cont.)` instead of "Cont..."**

| # | Badge title | Instruction |
|---|---|---|
| 5 | **INITIALIZE GROW-OUT** | Review the batch details and sample measurements, then tap [BOLD TEAL]"Initialize Grow-Out" to save the batch. |
| 6 | **VIEW THE INITIALIZED TANK** | After initialization, the Tank Overview displays the saved batch details and starting population. |

**Right header (lower):** `RECORDING MORTALITY AND HARVEST`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **LOG MORTALITY** | From the Overview tab, tap the [BOLD TEAL]"Log Mortality" button. Enter the number of [BOLD TEAL]dead crayfish, then tap [BOLD TEAL]"Confirm Logging" to save the record. |
| 2 | **RECORD HARVEST** | From the Overview tab, tap the [BOLD TEAL]"Record Harvest" button. Enter the [BOLD TEAL]harvest date, [BOLD TEAL]number harvested, and [BOLD TEAL]total weight, then tap [BOLD TEAL]"Save Harvest" to record the harvest. |

> ⚠ **FIX:** replace the "Cont…" placeholder with the real section title.

---

## SPREAD 6 — Weekly Sampling / Configure Settings

**Left header:** `WEEKLY SAMPLING`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN SAMPLING** | In Tank Management, tap the [BOLD TEAL]"Sampling" Tab to view the sampling schedule and growth overview. When sampling is due, tap [BOLD TEAL]"Sample Now" to open the record form. |
| 2 | **RECORD SAMPLE MEASUREMENTS** | The sample size is fixed to the initial baseline. Enter the [BOLD TEAL]weight and [BOLD TEAL]length of each crayfish. The next sampling becomes available after [BOLD TEAL]seven days. |
| 3 | **VIEW GROWTH TRENDS** | In the [BOLD TEAL]"Growth" tab, review the trend chart based on your sampling records. Use the [BOLD TEAL]ABW/ABGL toggle to view changes in average body weight or average body length. |
| 4 | **CHECK BIOMASS AND MORTALITY** | Review [BOLD TEAL]Estimated Biomass, calculated as live crayfish count × ABW, and check the [BOLD TEAL]Mortality Trend to monitor recorded losses. Continue weekly sampling and recording mortalities to keep the growth information updated. |

> 📌 **NOTE:** Perform sampling every seven days using the fixed sample size set
> during the initial sampling.

**Right header:** `CONFIGURE SETTINGS`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN SETTINGS** | Tap the [BOLD TEAL]Profile/Settings icon at the top of the screen to access the settings menu. |
| 2 | **VIEW PROFILE & SETTINGS OPTIONS** | After tapping the Profile icon, the Profile & Settings page will open. From this page, select the setting you want to manage, such as [BOLD TEAL]Edit Profile, [BOLD TEAL]Create Password, [BOLD TEAL]Notifications, [BOLD TEAL]Sensor Thresholds, or [BOLD TEAL]Logout. |
| 3 | **EDIT PROFILE** | From the Profile & Settings page, tap [BOLD TEAL]Edit Profile. Update your profile picture and [BOLD TEAL]Full Name as needed, then tap [BOLD TEAL]Save Changes to apply the updates. |
| 4 | **CREATE PASSWORD** | From the Profile & Settings page, tap [BOLD TEAL]Create Password. Enter and confirm the password in the required fields, then tap the button provided to save or create the password. |

---

## SPREAD 7 — Configure Settings (cont.) / Controlling Your Tank: Feeding

**Left page — header should read `CONFIGURE SETTINGS (cont.)` instead of "Cont..."**

| # | Badge title | Instruction |
|---|---|---|
| 5 | **MANAGE NOTIFICATIONS** | Use the switches to choose which alerts and reminders to receive, including [BOLD TEAL]water-quality alerts, [BOLD TEAL]feeding reminders, [BOLD TEAL]sampling reminders, and [BOLD TEAL]system updates. You can also control notification sound and vibration. |
| 6 | **OPEN SENSOR THRESHOLDS** | From the Profile & Settings page, tap [BOLD TEAL]Sensor Thresholds to view and adjust the safe ranges for water-quality and tank levels. |
| 7 | **EDIT WATER-QUALITY THRESHOLDS** | Tap the [BOLD TEAL]pencil beside a physical parameter—such as [BOLD TEAL]Temperature, [BOLD TEAL]pH Level, [BOLD TEAL]Dissolved Oxygen, or [BOLD TEAL]Turbidity—to adjust its minimum and maximum thresholds. Tap [BOLD TEAL]Update to save your changes. |
| 8 | **UPDATE YOUR CHANGES** | Tap the pencil beside a physical parameter—such as [BOLD TEAL]Water Level or [BOLD TEAL]Feed Level—to adjust its low and critical thresholds. Tap [BOLD TEAL]Update to save your changes. |

> ⚠ **FIX:** badge **8** currently has an empty title bar. It must read
> **"UPDATE YOUR CHANGES"**. Already patched in `pages/page-10-11-fixed.png`.

**Right page — NEW section header:** `CONTROLLING YOUR TANK: FEEDING`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN THE CONTROLS TAB** | From the Dashboard, tap [BOLD TEAL]"Controls" in the bottom navigation bar. The screen opens on the [BOLD TEAL]Feeding tab. |
| 2 | **VIEW YOUR FEEDING SCHEDULES** | The Feeding tab lists every auto-feed schedule with its time, repeat days, feed amount, and an on/off switch. Tap [BOLD TEAL]"View all … schedules" to open the full list. |
| 3 | **ADD A FEEDING SCHEDULE** | Tap the [BOLD TEAL]add button, choose the feeding time, tap the day chips to select the repeat days, and enter the feed amount in grams ([BOLD TEAL]1–200 g, whole grams — one gate swing per gram). Tap [BOLD TEAL]Save. |
| 4 | **FEED NOW (MANUAL FEEDING)** | Tap [BOLD TEAL]Feed Now, enter the amount in grams, and tap [BOLD TEAL]"Dispense Feed". The ESP32 dispenses the dose and the app waits for the device to confirm. |

> 📌 **NOTE:** Feeding times use [BOLD TEAL]Philippine time (Asia/Manila). If the
> ESP32 is offline or the hopper is empty or insufficient, CrayCare shows
> [BOLD TEAL]"Feeder Offline" or [BOLD TEAL]"Feed Blocked" and nothing is
> dispensed. If you tap Feed Now within one minute of a scheduled feeding, the
> app asks you to confirm first so that two feeds cannot run at once.

> ⚠ The 4 empty badges on page 11 are filled with the content above. Already
> patched in `pages/page-10-11-fixed.png`.

---

## SPREAD 8 — Controlling Your Tank: Actuators

**Section header:** `CONTROLLING YOUR TANK: ACTUATORS`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **SWITCH TO THE ACTUATORS TAB** | Tap [BOLD TEAL]"Actuators" at the top of the Controls screen. |
| 2 | **CHOOSE AN ACTUATOR MODE** | Each device has a mode pill: [BOLD TEAL]Auto (the app and the threshold rules decide when it runs), [BOLD TEAL]On (runs continuously), or [BOLD TEAL]Off (stays off). |
| 3 | **SEE THE LIVE STATE** | The badge beside each device shows the state the ESP32 last reported. When the device is offline, a [BOLD TEAL]"not connected" badge appears and the mode pill is disabled. |
| 4 | **VIEW THE ACTUATOR LOG** | Tap a group header — [BOLD TEAL]Aeration (Aerator 1, Aerator 2) or [BOLD TEAL]Filtration (Water Pump) — to open the log of every manual and automatic activation with its time and source. |

---

## SPREAD 9 — Viewing Sensor History (Analytics)

**Section header:** `VIEWING SENSOR HISTORY`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN THE ANALYTICS TAB** | From the Dashboard, tap [BOLD TEAL]"Analytics" in the bottom navigation bar. |
| 2 | **SELECT A TIME RANGE** | Tap the filter selector and choose the period you want to review, such as the last 24 hours, 7 days, or 30 days. |
| 3 | **READ THE CHARTS** | Scroll through the charts for [BOLD TEAL]Temperature, [BOLD TEAL]pH Level, [BOLD TEAL]Dissolved O₂, [BOLD TEAL]Turbidity, [BOLD TEAL]Water Level, and [BOLD TEAL]Feed Level. |
| 4 | **SPOT A TREND** | Compare each chart with its average-value card to see whether the tank is improving, holding steady, or drifting toward a limit. |

---

## SPREAD 10 — Water Quality Anomaly Detection

**Section header:** `WATER QUALITY ANOMALY DETECTION`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **FIND THE ANALYSIS CARD** | On the Dashboard, scroll to the [BOLD TEAL]Water Quality Analysis section. The card shows the newest anomaly-detection result. |
| 2 | **READ THE STATUS** | The result is one of three statuses: [BOLD TEAL]Normal, [BOLD TEAL]Unusual, or [BOLD TEAL]Insufficient. [BOLD TEAL]Insufficient means there is not yet enough sensor history for the model to judge the tank. |
| 3 | **VIEW DETAILS** | Tap [BOLD TEAL]"View details" to expand the card and read the [BOLD TEAL]Insight, the [BOLD TEAL]Suggested Checks, and the sensors that contributed most to the result. |
| 4 | **OPEN THE HISTORY** | Tap the [BOLD TEAL]History button to open the full list of past results, newest first, and tap any entry to see the reasoning behind that reading. |

> 📌 **NOTE:** The anomaly detection reports unusual combined behaviour of pH,
> temperature, dissolved oxygen, and turbidity. It does not classify biological
> safety and it does not switch your actuators — alerts and the threshold layer
> do that.

---

## SPREAD 11 — Notifications / Setting Up Your Hardware

**Left header:** `NOTIFICATIONS`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **OPEN THE NOTIFICATIONS TAB** | From the Dashboard, tap [BOLD TEAL]"Notifications" in the bottom navigation bar to see your alert history. |
| 2 | **FILTER YOUR ALERTS** | Use the filter chips to switch between [BOLD TEAL]All and [BOLD TEAL]Unread notifications. |
| 3 | **READ A NOTIFICATION** | Tap an entry to open the full alert, including the sensor reading and the recommended action. |
| 4 | **MARK ALL READ** | Tap [BOLD TEAL]"Mark all read" to clear the unread badge on the Notifications tab. |

**Right header:** `SETTING UP YOUR HARDWARE (ESP32)`

| # | Badge title | Instruction |
|---|---|---|
| 1 | **INSTALL THE SENSORS** | Connect the temperature, pH, dissolved oxygen, turbidity, and water-level sensors to the ESP32 following the pin assignments, then power the board. |
| 2 | **ASSIGN THE DEVICE** | The ESP32 signs in with its own device account and reports the hardware it belongs to. An administrator assigns that hardware to your account, and the tank appears on your Dashboard. |
| 3 | **CALIBRATE THE SENSORS** | Compare each live reading with a reference instrument and adjust the values before use. |
| 4 | **WORK OFFLINE** | After one successful sync, the ESP32 keeps sensing and runs cached feeding schedules during an outage, then uploads its backlog oldest-first when the connection returns. |

> 📌 Use the sensor calibration values in `docs/Deliverables/SENSOR CALIBRATION TABLE.docx`.

---

## SPREAD 12 — Troubleshooting & FAQ / Safety Notes

**Left header:** `TROUBLESHOOTING`

| Problem | What to do |
|---|---|
| "Sign in before changing schedules" | Sign out and sign in again to refresh your session, then retry. |
| "Feeder Offline" or "Feed Blocked" | Check the ESP32 power and Wi-Fi connection, and confirm the hopper still contains feed. |
| Reading shows "No reading" | The ESP32 has not uploaded a value yet. It usually appears within a few seconds of the device syncing. |
| A schedule cannot be enabled | The stored schedule is missing a repeat day or feed amount. Edit the schedule, choose at least one day, and save it again. |
| The app shows "Tank not set up yet" | Tap **Tank → Initialize Tank** and complete the Grow-Out Initialization form. |

**Right header:** `SAFETY NOTES`

- CrayCare is an assistive monitoring tool. Verify water conditions with a
  reference instrument before acting on any alert.
- Do not open, modify, or expose the ESP32 enclosure while it is powered.
- Keep the water-level sensor clear of debris and check the feed hopper
  regularly.
- A feeding schedule runs on the ESP32 clock, not on the phone. Keep the device
  powered and connected so that its schedule stays in sync.
- Disconnecting the internet does not stop the feeder, the aerators, or the
  sensor logging.

---

## Table of Contents (for the empty left half of spread 2)

```
About CrayCare ........................................ 1
Downloading the CrayCare Application .................. 1
Installing and Opening the Application ................. 2
Account Registration .................................... 4
Account Login / Forgot Password ....................... 5
Getting Started with the Dashboard .................... 6
Recording Mortality and Harvest ....................... 7
Weekly Sampling ........................................ 8
Configure Settings ...................................... 9
Controlling Your Tank: Feeding ....................... 10
Controlling Your Tank: Actuators ..................... 12
Viewing Sensor History ............................... 13
Water Quality Anomaly Detection ...................... 14
Notifications ......................................... 15
Setting Up Your Hardware (ESP32) ..................... 15
Troubleshooting & FAQ / Safety Notes .................. 16
```
