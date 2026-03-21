
#include <ADS1115_WE.h>
#include <Wire.h>

#define I2C_ADDRESS 0x48
ADS1115_WE adc = ADS1115_WE(I2C_ADDRESS);

// Sensor Voltage-Pressure Calibration
float V_ZERO = 0.0;  // Will be auto-calibrated
#define V_MAX 4.5    // Max pressure voltage
#define P_MIN 0      // Minimum pressure (bar)
#define P_MAX 16     // Maximum pressure (bar)
float error_diff = 0.20;  // error difference

#define ANALOGPIN      A0  //D14
#define PWM 9

int delayval = 5;        // loop delay

void setup() {
   Serial.begin(9600);    // open the serial port at 9600 bps
    pinMode(PWM, OUTPUT);
    analogWrite(PWM, 0);

 Wire.setSDA(18);
  Wire.setSCL(19);
  Wire.begin();
  Serial.begin(9600);

  if (!adc.init()) {
    Serial.println("ADS1115 not connected!");
    while (1)
      ;
  }

  adc.setVoltageRange_mV(ADS1115_RANGE_4096);
  adc.setCompareChannels(ADS1115_COMP_0_GND);
  adc.setMeasureMode(ADS1115_SINGLE);

  // Auto-Calibrate Zero Pressure Voltage
  Serial.println("Calibrating... Keep sensor at zero pressure!");
  float sumVoltage = 0;
  int numSamples = 50;

  for (int i = 0; i < numSamples; i++) {
    adc.startSingleMeasurement();
    while (adc.isBusy()) { delay(1); }
    sumVoltage += adc.getResult_V();
    delay(50);
  }

  V_ZERO = sumVoltage / numSamples;
  Serial.print("Calibrated Zero Voltage: ");
  Serial.println(V_ZERO, 3);

}

void loop() {
   
  int value;

  adc.startSingleMeasurement();
  while (adc.isBusy()) { delay(1); }
  float voltage = adc.getResult_V();
  int rawResult = adc.getRawResult();
  Serial.print("Raw ADC: ");
  Serial.print(rawResult);
  // Convert to Pressure

  float pressure = mapPressure(voltage);
  // Serial.print("  Pressure [bar] : ");
  // Serial.println(pressure, 2);
  if (pressure > 0.25) {
    pressure = pressure - error_diff;
  }

  Serial.print(" Pressure [bar] : ");
  Serial.println(pressure, 2);

  //read pot
  value = analogRead(ANALOGPIN); // analog read of potentiometer
  Serial.print("  pot ");
  Serial.println(value);   // print value
  analogWrite(PWM, value/4);
  
  
  delay(delayval);         // Delay for a period of time (in milliseconds).

}

// Function to Convert Voltage to Pressure
float mapPressure(float voltage) {
  if (voltage < V_ZERO) voltage = V_ZERO;  // Prevents negative pressures
  return ((voltage - V_ZERO) / (V_MAX - V_ZERO)) * (P_MAX - P_MIN) + P_MIN;
}
