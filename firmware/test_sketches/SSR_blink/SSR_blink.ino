
void setup() {
  pinMode(15, OUTPUT);
    pinMode(16, OUTPUT);

    pinMode(LED_BUILTIN, OUTPUT);

}

void loop() {
    digitalWrite(LED_BUILTIN, HIGH);  // turn the LED on (HIGH is the voltage level)

  digitalWrite(15, HIGH);   // turn the LED on (HIGH is the voltage level)
    delay(300);                       // wait for a second

    digitalWrite(16, HIGH);   // turn the LED on (HIGH is the voltage level)

  delay(3000);                       // wait for a second
  digitalWrite(15, LOW);    // turn the LED off by making the voltage LOW
      delay(300);                       // wait for a second

  digitalWrite(16, LOW);    // turn the LED off by making the voltage LOW

    digitalWrite(LED_BUILTIN, LOW);  // turn the LED on (HIGH is the voltage level)

  delay(3000);                       // wait for a second
}


