// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ccs811 show *

/**
Shows version information about the CCS811 on the serial monitor
*/

main:
  // Enable and drive I2C
  frequency := 400_000
  sda-pin := gpio.Pin 19
  scl-pin := gpio.Pin 20
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency

  if not bus.test Ccs811.I2C-ADDRESS:
    print "No CCS811 device found"
    return

  print " Found Ccs811 on 0x$(%02x Ccs811.I2C-ADDRESS)"
  ccs811-device := bus.device Ccs811.I2C_ADDRESS
  ccs811-driver := Ccs811 ccs811-device

  print "CCS811 HW ID:              0x$(%00x ccs811-driver.get-hardware-id)"
  print "CCS811 HW Product:         0x$(%00x ccs811-driver.get-hardware-version-product)"
  print "CCS811 HW Variant:         0x$(%00x ccs811-driver.get-hardware-version-product)"
  print "CCS811 Firmware Boot ver:  $(ccs811-driver.get-firmware-boot-version)"
  print "CCS811 Firmware App ver:   $(ccs811-driver.get-firmware-app-version)"
  print "CCS811 Baseline value:     0x$(%02x ccs811-driver.get-baseline)"
