// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import bme280
import ccs811 show *

main:
  // Enable and drive I2C
  frequency := 400_000
  sda-pin := gpio.Pin 19
  scl-pin := gpio.Pin 20
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency

  bme280-device := null
  bme280-driver := null
  if not bus.test  bme280.I2C-ADDRESS:
    print "No BME280 device found"
    return
  else:
    print " Found BME280 on 0x$(%02x bme280.I2C-ADDRESS)"
    bme280-device = bus.device bme280.I2C-ADDRESS
    bme280-driver = bme280.Driver bme280-device

  if not bus.test Ccs811.I2C-ADDRESS:
    print "No CCS811 device found"
    return

  print " Found Ccs811 on 0x$(%02x Ccs811.I2C-ADDRESS)"
  ccs811-device := bus.device Ccs811.I2C_ADDRESS
  ccs811-driver := Ccs811 ccs811-device

  if bme280-driver != null :
    print "Current Temperature:       $(bme280-driver.read-temperature) c"
    print "Current Huimidity:         $(bme280-driver.read-humidity) %rh"
    ccs811-driver.set-temp-humidity --humidity=bme280-driver.read-humidity --temp=bme280-driver.read-temperature

  print "CCS811 HW ID:              0x$(%00x ccs811-driver.get-hardware-id)"
  print "CCS811 HW Product:         0x$(%00x ccs811-driver.get-hardware-version-product)"
  print "CCS811 HW Variant:         0x$(%00x ccs811-driver.get-hardware-version-product)"
  print "CCS811 Firmware Boot ver:  $(ccs811-driver.get-firmware-boot-version)"
