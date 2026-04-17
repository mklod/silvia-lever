/*
 * Pump Enable + PWM Test
 * Last modified: 2026-04-08--0100
 *
 * Tests pump enable (optoisolator on pin 3) and PWM (pin 9).
 * Cycles through combinations to find the correct polarity.
 *
 * Sequence (5 seconds each, watch for pump running):
 *   1. ENA HIGH + PWM 255   — if pump runs here, ENA is active-HIGH
 *   2. ENA LOW  + PWM 255   — if pump runs here, ENA is active-LOW (inverted)
 *   3. ENA HIGH + PWM 128   — half speed test
 *   4. ENA LOW  + PWM 128   — half speed test (inverted)
 *   5. ALL OFF
 *   (repeats)
 */

#define PUMP_PWM_PIN           9
#define PUMP_ENA_PIN           3
#define VALVE_PUMP_PIN        21
#define VALVE_THERMOBLOCK_PIN 20

int step = 0;
unsigned long lastChange = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) {}

  pinMode(PUMP_ENA_PIN, OUTPUT);
  digitalWrite(PUMP_ENA_PIN, LOW);
  pinMode(PUMP_PWM_PIN, OUTPUT);
  analogWrite(PUMP_PWM_PIN, 0);

  // Match brew priming valve state: pump→thermoblock, thermoblock→drain
  pinMode(VALVE_PUMP_PIN, OUTPUT);
  digitalWrite(VALVE_PUMP_PIN, HIGH);          // pump routes to thermoblock
  pinMode(VALVE_THERMOBLOCK_PIN, OUTPUT);
  digitalWrite(VALVE_THERMOBLOCK_PIN, LOW);    // thermoblock routes to drain

  Serial.println("=== Pump Enable + PWM Test ===");
  Serial.println("Valves set to brew priming path (pump→thermoblock→drain)");
  Serial.println("Watch/listen for pump. 5 seconds per step.");
  Serial.println("---");
}

void loop() {
  unsigned long now = millis();
  if (now - lastChange >= 5000) {
    lastChange = now;
    step = (step + 1) % 6;

    switch (step) {
      case 1:
        Serial.println("[1] ENA=HIGH  PWM=255  (full speed, active-HIGH)");
        digitalWrite(PUMP_ENA_PIN, HIGH);
        analogWrite(PUMP_PWM_PIN, 255);
        break;
      case 2:
        Serial.println("[2] ENA=LOW   PWM=255  (full speed, active-LOW)");
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 255);
        break;
      case 3:
        Serial.println("[3] ENA=HIGH  PWM=128  (half speed, active-HIGH)");
        digitalWrite(PUMP_ENA_PIN, HIGH);
        analogWrite(PUMP_PWM_PIN, 128);
        break;
      case 4:
        Serial.println("[4] ENA=LOW   PWM=128  (half speed, active-LOW)");
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 128);
        break;
      default:
        Serial.println("[0] ALL OFF");
        digitalWrite(PUMP_ENA_PIN, LOW);
        analogWrite(PUMP_PWM_PIN, 0);
        break;
    }
  }
}
