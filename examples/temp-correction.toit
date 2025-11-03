// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import bme280
import ccs811 show *

/**
Show readings in a loop, demonstrating manual use of is-ready, and wait-timeout.

Measures the time taken for the code to run.

Note:
  - wait-timeout.in-ms is the suggested timeout based on the mode.  This code
    manually shows this time but does not use it as a timeout.  This is why the
    first iteration may take longer than the wait time.

*/

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
  // Default: MODE-1 - 1 second reads
  // Don't wait for first read during initialisation
  ccs811-device := bus.device Ccs811.I2C_ADDRESS
  ccs811-driver := Ccs811 ccs811-device --measure-mode=Ccs811.MODE-1 --wait-for-first-sample=false

  // For testing purposes, examine the values in the status register
  ccs811-driver.dump-status

  // Initialise BME280 Driver (Change if your device is not this device)
  bme280-device := null
  bme280-driver := null
  if not bus.test  bme280.I2C-ADDRESS:
    print " No BME280 device found"
    return
  else:
    print " * Found BME280 on 0x$(%02x bme280.I2C-ADDRESS)"
    bme280-device = bus.device bme280.I2C-ADDRESS
    bme280-driver = bme280.Driver bme280-device
    print " BME280 Current Temperature: $(%02f bme280-driver.read-temperature) c"
    print " BME280 Current Huimidity:   $(%02f bme280-driver.read-humidity) %rh"


  // Initialise variables
  timestart-us := 0
  timetaken/Duration := ?
  ready := false
  count := 0
  eco2 := 0
  etvoc := 0

  // Show Default Values
  print
  print " Default Temp and Humidity Correction in the driver: Temp: $(%0.2f ccs811-driver.get-temp-calibration)c $(%0.2f ccs811-driver.get-humidity-calibration)%rh"
  print

  // Do x reads and see the values.  Monitor time taken.
  // Sleep for a reasonable period between each measurement.
  3.repeat:
    timestart-us = Time.monotonic-us
    count = 0
    ready = false
    while not ready:
      count += 1
      ready = ccs811-driver.is-data-ready
      sleep (ccs811-driver.wait-timeout / 50)

    eco2 = ccs811-driver.read-eco2
    etvoc = ccs811-driver.read-etvoc
    timetaken = Duration --us=(Time.monotonic-us - timestart-us)
    print "     Reading $(it + 1):  \teCO2: $(eco2)ppm  \teTVOC: $(etvoc)ppb  \t[time taken = $(ccs811-driver.duration-to-string timetaken)]"

  print
  temp := bme280-driver.read-temperature
  humid := bme280-driver.read-humidity
  print " Set Temp and Humidity Correction in the driver: Temp: $(%0.2f temp)c $(%0.2f humid)%rh"
  ccs811-driver.set-temp-humidity --humidity=humid --temp=temp
  print

  // Do x reads and see the values.  Monitor time taken.
  // Sleep for a reasonable period between each measurement.
  3.repeat:
    timestart-us = Time.monotonic-us
    count = 0
    ready = false
    while not ready:
      count += 1
      ready = ccs811-driver.is-data-ready
      sleep (ccs811-driver.wait-timeout / 50)

    eco2 = ccs811-driver.read-eco2
    etvoc = ccs811-driver.read-etvoc
    timetaken = Duration --us=(Time.monotonic-us - timestart-us)
    print "     Reading $(it + 1):  \teCO2: $(eco2)ppm  \teTVOC: $(etvoc)ppb  \t[time taken = $(ccs811-driver.duration-to-string timetaken)]"
