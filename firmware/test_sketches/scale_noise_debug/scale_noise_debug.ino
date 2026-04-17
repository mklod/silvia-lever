/*
 * Scale Noise Debug — isolate NAU7802 noise sources
 * Last modified: 2026-04-14--2230
 *
 * Replicates the main firmware's environment (PT1000 SPI + ADS1115 I2C +
 * pot reads + serial telemetry) but with verbose scale output and no UI.
 * Open Serial Monitor at 115200 to see scale readings in real time.
 *
 * ─── SERIAL COMMANDS ─────────────────────────────────────────────
 *
 *   t = tare (calculateZeroOffset 32)
 *   r = reset stats (min/max)
 *   s = toggle PT1000 SPI reads
 *   a = toggle ADS1115 reads
 *   p = toggle pot reads
 *   + = increase IIR filter strength
 *   - = decrease IIR filter strength
 *   h = help
 *
 * Toggle subsystems to find which one is injecting noise into the scale.
 */

#include <SPI.h>
#include <Wire.h>
#include <Adafruit_MAX31865.h>
#include <ADS1115_WE.h>
#include <SparkFun_Qwiic_Scale_NAU7802_Arduino_Library.h>

// ── Pins ────────────────────────────────────────────────────────────
#define PT1000_BREW_CS  10
#define PT1000_STEAM_CS  6
#define I2C_SDA         18
#define I2C_SCL         19
#define POT_PIN         A0

// ── Sensors ─────────────────────────────────────────────────────────
Adafruit_MAX31865 thermoBrew  = Adafruit_MAX31865(PT1000_BREW_CS);
Adafruit_MAX31865 thermoSteam = Adafruit_MAX31865(PT1000_STEAM_CS);
ADS1115_WE adc = ADS1115_WE(0x48);
NAU7802 scale;

// ── Runtime flags — toggleable via serial ───────────────────────────
bool spiEnabled = true;
bool adsEnabled = true;
bool potEnabled = true;
float iirAlpha  = 0.15f;

// ── Scale state ─────────────────────────────────────────────────────
float filteredWeight = 0.0f;
float minRaw =  1e9, maxRaw = -1e9;
float minFiltered = 1e9, maxFiltered = -1e9;
unsigned long sampleCount = 0;
unsigned long lastScaleRead = 0;
unsigned long lastPt1000Read = 0;
unsigned long lastAdsRead = 0;
unsigned long lastPotRead = 0;
unsigned long lastDebugPrint = 0;

float brewTemp = 0.0f, steamTemp = 0.0f, pressureV = 0.0f;
int potValue = 0;

// ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) {}

  // SPI hard-reset (fixes brew PT1000 363°C stale state bug)
  pinMode(PT1000_BREW_CS, OUTPUT);  digitalWrite(PT1000_BREW_CS, HIGH);
  pinMode(PT1000_STEAM_CS, OUTPUT); digitalWrite(PT1000_STEAM_CS, HIGH);
  pinMode(11, OUTPUT); digitalWrite(11, LOW);
  pinMode(12, INPUT);
  pinMode(13, OUTPUT); digitalWrite(13, LOW);
  delay(100);
  SPI.end();
  delay(50);

  Serial.println("=== Scale Noise Debug ===");
  Serial.println();

  // I2C
  Wire.setSDA(I2C_SDA);
  Wire.setSCL(I2C_SCL);
  Wire.begin();
  Wire.setClock(400000);

  // ADS1115
  if (!adc.init()) {
    Serial.println("ADS1115 init FAILED");
    adsEnabled = false;
  } else {
    adc.setVoltageRange_mV(ADS1115_RANGE_4096);
    adc.setCompareChannels(ADS1115_COMP_0_GND);
    adc.setMeasureMode(ADS1115_SINGLE);
    Serial.println("ADS1115 OK");
  }

  // NAU7802 — minimal init matching standalone working test
  if (!scale.begin()) {
    Serial.println("NAU7802 init FAILED");
    while (1);
  }
  scale.setSampleRate(NAU7802_SPS_320);
  scale.calibrateAFE();
  scale.setCalibrationFactor(420.0f);
  Serial.println("NAU7802 OK");

  // PT1000
  thermoBrew.begin(MAX31865_2WIRE);
  delay(200); thermoBrew.clearFault();
  thermoSteam.begin(MAX31865_2WIRE);
  delay(200); thermoSteam.clearFault();
  Serial.println("PT1000 OK");

  printHelp();
  Serial.println();
  Serial.println("Auto-tare in 2s...");
  delay(2000);
  scale.calculateZeroOffset(32);
  Serial.print("Zero offset: ");
  Serial.println(scale.getZeroOffset());
  resetStats();
  Serial.println();
  Serial.println("raw, filtered, min, max, range, brewT, steamT, pot, flags");
}

// ─────────────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  // ── Scale read every 80ms ──────────────────────────────────────
  if (now - lastScaleRead >= 80) {
    lastScaleRead = now;
    if (scale.available()) {
      float raw = scale.getWeight(true, 1);
      filteredWeight = filteredWeight * (1.0f - iirAlpha) + raw * iirAlpha;
      sampleCount++;
      if (raw < minRaw) minRaw = raw;
      if (raw > maxRaw) maxRaw = raw;
      if (filteredWeight < minFiltered) minFiltered = filteredWeight;
      if (filteredWeight > maxFiltered) maxFiltered = filteredWeight;
    }
  }

  // ── PT1000 reads every 500ms (toggleable) ─────────────────────
  if (spiEnabled && now - lastPt1000Read >= 500) {
    lastPt1000Read = now;
    brewTemp  = thermoBrew.temperature(1000.0f, 4300.0f);
    steamTemp = thermoSteam.temperature(1000.0f, 4300.0f);
    thermoBrew.readFault();
    thermoSteam.readFault();
  }

  // ── ADS1115 read every 130ms (toggleable) ─────────────────────
  if (adsEnabled && now - lastAdsRead >= 130) {
    lastAdsRead = now;
    adc.startSingleMeasurement();
    while (adc.isBusy()) {}
    pressureV = adc.getResult_V();
  }

  // ── Pot read every 50ms (toggleable) ──────────────────────────
  if (potEnabled && now - lastPotRead >= 50) {
    lastPotRead = now;
    potValue = analogRead(POT_PIN);
  }

  // ── Serial commands ────────────────────────────────────────────
  if (Serial.available()) {
    handleCommand(Serial.read());
  }

  // ── Debug print every 250ms ────────────────────────────────────
  if (now - lastDebugPrint >= 250) {
    lastDebugPrint = now;
    float rawNow = 0.0f;
    if (scale.available()) {
      rawNow = scale.getWeight(true, 1);
    }
    Serial.print(rawNow, 1);         Serial.print(", ");
    Serial.print(filteredWeight, 1); Serial.print(", ");
    Serial.print(minRaw, 1);         Serial.print(", ");
    Serial.print(maxRaw, 1);         Serial.print(", ");
    Serial.print(maxRaw - minRaw, 1); Serial.print(", ");
    Serial.print(brewTemp, 1);       Serial.print(", ");
    Serial.print(steamTemp, 1);      Serial.print(", ");
    Serial.print(potValue);          Serial.print(", ");
    Serial.print(spiEnabled ? "S" : "-");
    Serial.print(adsEnabled ? "A" : "-");
    Serial.print(potEnabled ? "P" : "-");
    Serial.print(" a=");
    Serial.println(iirAlpha, 2);
  }
}

// ─────────────────────────────────────────────────────────────────────
void handleCommand(char c) {
  switch (c) {
    case 't':
      Serial.println(">>> TARE");
      scale.calculateZeroOffset(32);
      filteredWeight = 0;
      resetStats();
      break;
    case 'r':
      Serial.println(">>> RESET STATS");
      resetStats();
      break;
    case 's':
      spiEnabled = !spiEnabled;
      Serial.print(">>> SPI "); Serial.println(spiEnabled ? "ON" : "OFF");
      resetStats();
      break;
    case 'a':
      adsEnabled = !adsEnabled;
      Serial.print(">>> ADS1115 "); Serial.println(adsEnabled ? "ON" : "OFF");
      resetStats();
      break;
    case 'p':
      potEnabled = !potEnabled;
      Serial.print(">>> POT "); Serial.println(potEnabled ? "ON" : "OFF");
      resetStats();
      break;
    case '+':
      iirAlpha = min(1.0f, iirAlpha + 0.05f);
      Serial.print(">>> alpha="); Serial.println(iirAlpha, 2);
      break;
    case '-':
      iirAlpha = max(0.01f, iirAlpha - 0.05f);
      Serial.print(">>> alpha="); Serial.println(iirAlpha, 2);
      break;
    case 'h':
    case '?':
      printHelp();
      break;
  }
}

void resetStats() {
  minRaw = 1e9; maxRaw = -1e9;
  minFiltered = 1e9; maxFiltered = -1e9;
  sampleCount = 0;
}

void printHelp() {
  Serial.println();
  Serial.println("Commands:");
  Serial.println("  t = tare            r = reset stats");
  Serial.println("  s = toggle SPI      a = toggle ADS1115   p = toggle pot");
  Serial.println("  + = more filter     - = less filter");
  Serial.println("  h = help");
}
