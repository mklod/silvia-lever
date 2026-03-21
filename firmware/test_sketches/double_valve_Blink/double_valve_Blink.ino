

// the setup function runs once when you press reset or power the board
void setup() {
  // initialize digital pin LED_BUILTIN as an output.
  pinMode(21, OUTPUT);
    pinMode(20, OUTPUT);
  pinMode(LED_BUILTIN, OUTPUT);

}

// the loop function runs over and over again forever
void loop() {
    digitalWrite(LED_BUILTIN, HIGH);  // turn the LED on (HIGH is the voltage level)

  digitalWrite(21, HIGH);  // turn the LED on (HIGH is the voltage level)
    delay(500);                      // wait for a second
  digitalWrite(20, HIGH);  // turn the LED on (HIGH is the voltage level)


    delay(1000);                      // wait for a second

  digitalWrite(LED_BUILTIN, LOW);   // turn the LED off by making the voltage LOW

  digitalWrite(21, LOW);   // turn the LED off by making the voltage LOW
    delay(500);                      // wait for a second

    digitalWrite(20, LOW);  // turn the LED on (HIGH is the voltage level)

  delay(1000);                      // wait for a second
}
