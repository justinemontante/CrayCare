# CrayCare pH ESP32 node

This firmware runs on the second ESP32 and reads only the DFRobot SEN0161 pH
module. The normal main firmware remains untouched. The main ESP runs the
`esp32dev_main_no_ph` variant and owns the LCD, Firestore, ten-minute history,
and offline SD/LittleFS queue. This pH node sends calibrated samples to it over
a dedicated UART link; it does not connect to Wi-Fi or write to Firebase.

## Wiring

| pH node | Main no-pH ESP | Purpose |
| --- | --- | --- |
| GPIO26 / UART2 TX | GPIO35 / UART2 RX | Calibrated pH data, 115200 baud |
| GND | GND | Shared signal reference |

Connect the pH module's analog output to GPIO35 on the **pH node**, not the
main ESP. Power the pH module as specified by the verified project wiring and
keep its analog output within the ESP32 input limit. The GPIO26 TX signal is
3.3V logic. Do not connect the two ESP32 USB/serial pins together.

## Calibration commands

Open this ESP's USB Serial Monitor at 115200 baud. Commands are sent on Enter.

Two-point, default pH 4.01 + 9.18:

1. In pH 4.01 buffer, wait until `stable=YES blocks=60/60`, then enter `phcal4`.
2. Rinse the probe; in pH 9.18 buffer, wait for the same stable status, then
   enter `phcal9 9.18`.
3. Check saved points and fit with `phshow`.

For 4.01 + 6.86, capture `phcal4` and `phcal686`, then enter `phpair 6.86`.
For 6.86 + 9.18, capture `phcal686` and `phcal9 9.18`, then enter
`phpair 6.86-9.18`. Three-point mode requires all three points, then `phmode 3`.
`phmode 2` selects two-point mode. Calibration points and fit stay in this
node's `phonly` NVS namespace across resets.

## Build, upload, and monitor

Run from this folder:

```powershell
pio run -e esp32dev_ph_only
pio run -e esp32dev_ph_only -t upload --upload-port COM4
pio device monitor -b 115200 --port COM4 --filter send_on_enter
```

Replace `COM4` with this ESP's port. Close the monitor before uploading.
The monitor commands are separate from the UART2 link to the main ESP.

## Data link and storage

The pH node emits `PH1,<sequence>,<pH>,<FIT_V>,<valid>,<stable>` once per
second. It sends `valid=0` until a valid calibration fit and sensor voltage
are available. The main ESP averages valid pH samples with its live sensor
window and ten-minute history window. It updates Firestore latest/history
when online; when offline, its SD card is the preferred history queue and
LittleFS is the fallback if SD is unavailable. The main ESP reports pH as
unavailable when no valid UART frame arrives for 3.5 seconds.
