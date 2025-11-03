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

  // Initialise variables
  timestart-us := 0
  timetaken/Duration := ?
  ready := false
  count := 0
  eco2 := 0
  etvoc := 0

  // Do x reads and see the values between each.  Monitor time taken.
  // Sleep for a reasonable period between each measurement.
  10.repeat:
    timestart-us = Time.monotonic-us
    count = 0
    ready = false
    print " ...waiting $(ccs811-driver.wait-timeout.in-ms)ms seconds for fresh data:"
    while not ready:
      count += 1
      ready = ccs811-driver.is-data-ready
      // Check more often to help see differences in read time:
      sleep (ccs811-driver.wait-timeout / 50)

    eco2 = ccs811-driver.read-eco2
    etvoc = ccs811-driver.read-etvoc
    timetaken = Duration --us=(Time.monotonic-us - timestart-us)
    print "     Reading $(it + 1):  \teCO2: $(eco2)ppm  \teTVOC: $(etvoc)ppb  \t[time taken = $(ccs811-driver.duration-to-string timetaken)]"
