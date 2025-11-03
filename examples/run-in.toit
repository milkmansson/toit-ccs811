// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ccs811 show *

/**
Show readings in a loop, demonstrating driver use of `is-ready` by using
`--wait=true`.  Measures the time taken for each iteration.

Set the time required: for 1 hours worth of readings for a run in, set
$RUN-IN-DURATION.  Set $SAMPLE-TIME for sample times (as per driver).
*/

RUN-IN-DURATION := (Duration --h=3)   // Run time = 3 hour
SAMPLE-TIME     := Ccs811.MODE-1      // MODE-1   = 1 second reads

main:
  // Enable and drive I2C
  frequency := 400_000
  sda-pin := gpio.Pin 19
  scl-pin := gpio.Pin 20
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency

  if not bus.test Ccs811.I2C-ADDRESS:
    print " No CCS811 device found"
    return
  print " * Found CCS811 on 0x$(%02x Ccs811.I2C-ADDRESS)"

  // Call driver- in this case

  // Don't wait for first read during initialisation
  ccs811-device := bus.device Ccs811.I2C_ADDRESS
  ccs811-driver := Ccs811 ccs811-device --measure-mode=SAMPLE-TIME

  // For testing purposes, examine the values in the status register
  ccs811-driver.dump-status

  // Initialise variables
  time-start/Duration := ?
  time-read-start/Duration := ?
  time-read-finish-s/string := ?
  time-now/Duration := ?
  time-so-far/string := ?
  total-time/string := ?

  ready := false
  count := 0
  eco2 := 0
  etvoc := 0

  // How many times `is-ready` should be checked inside of `wait-timeout`
  wait-divisor := 50
  sleep-time := (ccs811-driver.wait-timeout / wait-divisor)
  repeat-times/int := ((RUN-IN-DURATION.in-ms / (ccs811-driver.wait-timeout.in-ms)).to-int)

  // Show Default Values
  print " Default Temp and Humidity Correction in the driver: Temp: $(%0.2f ccs811-driver.get-temp-calibration)c $(%0.2f ccs811-driver.get-humidity-calibration)%rh"
  total-time = ccs811-driver.duration-to-string (ccs811-driver.wait-timeout * repeat-times)
  print " Repeating $repeat-times times. Est:$(total-time)"

  // Do x reads and see the values.  Monitor time taken.
  // Sleep for a reasonable period between each measurement.
  time-start = Duration --us=Time.monotonic-us
  repeat-times.repeat:
    time-read-start = Duration --us=Time.monotonic-us
    count = 0
    ready = false
    while not ready:
      count += 1
      ready = ccs811-driver.is-data-ready
      sleep sleep-time

    eco2 = ccs811-driver.read-eco2
    etvoc = ccs811-driver.read-etvoc
    time-read-finish-s = ccs811-driver.duration-to-string ((Duration --us=(Time.monotonic-us)) - time-read-start)
    time-so-far = ccs811-driver.duration-to-string ((Duration --us=(Time.monotonic-us)) - time-start)
    print "     Reading $(it + 1)/$(repeat-times):  \teCO2: $(eco2)ppm  \teTVOC: $(etvoc)ppb  \t\t duration: $time-read-finish-s [$time-so-far / $total-time]"
    //print "               :  \t Raw Current: $(ccs811-driver.read-raw-current * 1e6)ua \t Raw Voltage: $(%0.3f ccs811-driver.read-raw-voltage)v"
