// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import ccs811 show *

main:
  // Enable and drive I2C
  frequency := 400_000
  sda-pin := gpio.Pin 19
  scl-pin := gpio.Pin 20
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency

  // Initialise Display - stop if not present.
  if not bus.test Ssd1306.I2C-ADDRESS:
    logger.error "No SSD1306 display found"
    return
