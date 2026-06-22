#pragma once

#include <Arduino.h>

extern const int PH_PIN;
extern float pHValue;
extern float phNeutralVoltage;
extern float phSlope;

void initPHSensor();
float readPH();
float readPHRawVoltage();
void calibratePH7();
void calibratePH4();
void loadPHCalibration();
void savePHCalibration();

// 686 / 401 calibration functions
void calibratePH686();
void calibratePH401();
void readPHVoltage();
void showPHCalibration();
void resetPHCalibration();