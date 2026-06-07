#include <Arduino.h>

#define N1 26
#define N2 27
#define N3 14

void setup() {
    Serial.begin(115200);
    pinMode(N1, OUTPUT);
    pinMode(N2, OUTPUT);
    pinMode(N3, OUTPUT);
    digitalWrite(N1, HIGH);
    digitalWrite(N2, HIGH);
    digitalWrite(N3, HIGH);
    Serial.println("3-Relay Test Ready (LOW = ON)");
}

void loop() {
    Serial.println("N1 ON");
    digitalWrite(N1, LOW);
    delay(2000);
    digitalWrite(N1, HIGH);
    Serial.println("N1 OFF");
    delay(500);

    Serial.println("N2 ON");
    digitalWrite(N2, LOW);
    delay(2000);
    digitalWrite(N2, HIGH);
    Serial.println("N2 OFF");
    delay(500);

    Serial.println("N3 ON");
    digitalWrite(N3, LOW);
    delay(2000);
    digitalWrite(N3, HIGH);
    Serial.println("N3 OFF");
    delay(500);
}