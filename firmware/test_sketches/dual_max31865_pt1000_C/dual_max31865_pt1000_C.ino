
#include <Adafruit_MAX31865.h>

//cs1 10
//cs2 6

//mosi 11, miso 12, clk 13
// Use software SPI: CS, DI, DO, CLK

Adafruit_MAX31865 thermo1 = Adafruit_MAX31865(10, 11, 12, 13);
Adafruit_MAX31865 thermo2 = Adafruit_MAX31865(6, 11, 12, 13);

#define RREF      4300.0
#define RNOMINAL  1000.0

void setup() {
  Serial.begin(115200);
  Serial.println("MAX31865 PT1000 Test");

  thermo1.begin(MAX31865_2WIRE);  // set to 2WIRE or 4WIRE as necessary
  thermo2.begin(MAX31865_2WIRE);  // set to 2WIRE or 4WIRE as necessary
}

void loop() {
  uint16_t rtd1 = thermo1.readRTD();
  uint16_t rtd2 = thermo2.readRTD();

  float ratio1 = rtd1;
  float ratio2 = rtd2;

  ratio1 /= 32768;
  ratio2 /= 32768;

  Serial.print("thermoblock cs10 = "); Serial.println(thermo1.temperature(RNOMINAL, RREF));
  Serial.print("boiler cs6 = "); Serial.println(thermo2.temperature(RNOMINAL, RREF));

  Serial.println();
  delay(500);
}
