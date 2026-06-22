#pragma once

#include <Arduino.h>

extern const int DO_PIN;
extern float DOValue;
extern float doAirVoltage;

void initDOSensor();
float readDO(float temperatureC);
void calibrateDOInAir();
void loadDOCalibration();
void saveDOCalibration();
float saturationDO(float tempC);
float readDORaw();
