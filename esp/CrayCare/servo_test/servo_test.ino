/*
 * CrayCare — Servo Test
 * Standalone servo dispensing test (0° -> 180° -> 0°)
 * Non-blocking state machine.
 *
 * Wiring:
 *   Servo Signal -> GPIO13
 *   Servo Power  -> External 5V supply (NOT ESP32 5V pin!)
 *   Servo GND    -> Common GND with ESP32
 *
 * Serial (115200 baud):
 *   FEED  - run one dispensing cycle
 *   0/90/180 - manual position
 */

#define SERVO_PIN 13
#define LEDC_CHANNEL 0
#define LEDC_FREQ 50
#define LEDC_RESOLUTION 16
#define PULSE_MIN 500
#define PULSE_MAX 2500
#define PAUSE_FWD 400
#define PAUSE_BWD 150

enum FeedState { IDLE, MOVING_FWD, PAUSE_FWD, MOVING_BWD, PAUSE_BWD };
FeedState state = IDLE;
unsigned long stateStartMs = 0;

void setServoAngle(int angle) {
  angle = constrain(angle, 0, 180);
  int pulseWidth = map(angle, 0, 180, PULSE_MIN, PULSE_MAX);
  int duty = (int)((float)pulseWidth / 20000.0f * 65535.0f);
  ledcWrite(LEDC_CHANNEL, duty);
}

void startFeed() {
  if (state != IDLE) { Serial.println("[FEED] Busy"); return; }
  state = MOVING_FWD;
  stateStartMs = millis();
  setServoAngle(180);
  Serial.println("[FEED] 0 -> 180");
}

void processFeed() {
  unsigned long now = millis();
  switch (state) {
    case MOVING_FWD:
      state = PAUSE_FWD;
      stateStartMs = now;
      break;
    case PAUSE_FWD:
      if (now - stateStartMs >= PAUSE_FWD) {
        setServoAngle(0);
        state = MOVING_BWD;
        stateStartMs = now;
        Serial.println("[FEED] 180 -> 0");
      }
      break;
    case MOVING_BWD:
      state = PAUSE_BWD;
      stateStartMs = now;
      break;
    case PAUSE_BWD:
      if (now - stateStartMs >= PAUSE_BWD) {
        state = IDLE;
        Serial.println("[FEED] Complete!");
      }
      break;
    default:
      state = IDLE;
      break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  ledcSetup(LEDC_CHANNEL, LEDC_FREQ, LEDC_RESOLUTION);
  ledcAttachPin(SERVO_PIN, LEDC_CHANNEL);
  setServoAngle(0);
  Serial.println("\n=== CrayCare Servo Test ===");
  Serial.println("Commands: FEED, 0, 90, 180");
  Serial.println("===========================\n");
}

void loop() {
  processFeed();
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd == "FEED") {
      startFeed();
    } else if (cmd == "0" || cmd == "90" || cmd == "180") {
      setServoAngle(cmd.toInt());
      Serial.printf("[SERVO] %s deg\n", cmd.c_str());
    } else if (cmd.length() > 0) {
      Serial.println("Usage: FEED, 0, 90, 180");
    }
  }
}
