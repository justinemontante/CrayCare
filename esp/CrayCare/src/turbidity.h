#pragma once
#include <Arduino.h>

#include "common.h"
#include <OneWire.h>
#include <DallasTemperature.h>

// Pin definitions (adjust if needed)
extern const int TURBIDITY_PIN; // analog pin for turbidity sensor (e.g., 34)
extern const int ONE_WIRE_PIN; // digital pin for DS18B20 (e.g., 4)

// Calibration voltages (default values – can be overridden via Serial or Firebase)
extern float turbidityVClear; // voltage for clear water (0 NTU)
extern float turbidityVDirty; // voltage for dirty water (~500 NTU)
extern float turbidityVAir;   // voltage threshold for air / no water

extern bool turbidityAir; // true if current reading is considered "air"

// Functions
void loadTurbidityFromNVS();
void saveTurbidityToNVS();
void loadTurbidityFromFirebase();
float readTurbidityVoltage();
float ntuFromVoltage(float V);
String buildSensorJson(float temperatureC, float turbidityNTU);
void updateTurbidityCalibration(float clearV, float dirtyV, float airV);
// Temperature sensor helpers
void initTemperatureSensor();
float readTemperatureC();
