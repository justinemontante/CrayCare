#pragma once

#include <Arduino.h>

extern const int PH_PIN;
extern float pHValue;
extern float phNeutralVoltage;
extern float phSlope;

void initPHSensor();
float readPH();
void calibratePH7();
void calibratePH4();
void loadPHCalibration();
void savePHCalibration();
