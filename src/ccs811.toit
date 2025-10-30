// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import log
import math show *
import binary
import serial.device as serial
import serial.registers as registers
import io.buffer


class Ccs811:
  static I2C-ADDRESS          ::= 0x5a
  static I2C-ADDRESS-ALT      ::= 0x5b    // When pin AD0 is high

  static REG-STATUS_          ::= 0x00 // R 1 byte Status register
  static REG-MEAS-MODE_       ::= 0x01 // R/W 1 byte Measurement mode and conditions register
  static REG-ALG-RESULT-DATA_ ::= 0x02 // R <= 8 bytes - Algorithm result.
  // The most significant 2 bytes contain a ppm estimate of the equivalent CO 2 (eCO 2) level, and
  // the next two bytes contain a ppb estimate of the total VOC level.
  static REG-RAW-DATA_        ::= 0x03 // R 2 bytes Raw ADC data values for resistance and current source used.
  static REG-ENV-DATA_        ::= 0x05 // W 4 bytes Temperature and humidity data can be written to enable compensation
  static REG-THRESHOLDS_      ::= 0x10 // W 4 bytes Thresholds for operation when interrupts are only
  // generated when eCO 2 ppm crosses a threshold
  static REG-BASELINE_        ::= 0x11 // R/W 2 bytes The encoded current baseline value can be read. A
  // previously saved encoded baseline can be written.
  static REG-HW-ID_           ::= 0x20 // R 1 byte Hardware ID. The value is 0x81
  static REG-HW-VERSION_      ::= 0x21 // R 1 byte Hardware Version. The value is 0x1X
  static REG-BOOT-VERSION_    ::= 0x23 // R 2 bytes Firmware Boot Version.
  // The first 2 bytes contain the firmware version number for the boot code.
  static REG-FW-APP-VERSION_  ::= 0x24 // R 2 bytes Firmware Application Version.
  // The first 2 bytes contain the firmware version number for the application code
  static REG-INTERNAL-STATE_  ::= 0xA0 // R 1 byte Internal Status register
  static REG-ERROR-ID_        ::= 0xE0 // R 1 byte Error ID.
  // When the status register reports an error its
  //source is located in this register
  static REG-SW-RESET_        ::= 0xFF // W 4 bytes
  // If the correct 4 bytes (0x11 0xE5 0x72 0x8A) are written
  // to this register in a single sequence the device will reset
  // and return to BOOT mode

  static DEFAULT-REGISTER-WIDTH_ ::= 8

  // Globals
  reg_/registers.Registers := ?
  logger_/log.Logger := ?

  constructor
      device/serial.Device
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "ccs811"
    reg_ = device.registers





  /**
  Reads and optionally masks/parses register data
  */
  read-register_
      register/int
      --mask/int?=null
      --offset/int?=null
      --width/int=DEFAULT-REGISTER-WIDTH_
      --signed/bool=false -> any:
    assert: (width == 8) or (width == 16)
    if mask == null:
      mask = (width == 16) ? 0xFFFF : 0xFF
    if offset == null:
      offset = mask.count-trailing-zeros

    register-value/int? := null
    if width == 8:
      if signed:
        register-value = reg_.read-i8 register
      else:
        register-value = reg_.read-u8 register
    if width == 16:
      if signed:
        register-value = reg_.read-i16-be register
      else:
        register-value = reg_.read-u16-be register

    if register-value == null:
      logger_.error "read-register_: Read failed."
      throw "read-register_: Read failed."

    if ((mask == 0xFFFF) or (mask == 0xFF)) and (offset == 0):
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      return masked-value

  /**
  Writes register data (masked or full register writes)
  */
  write-register_
      register/int
      value/any
      --mask/int?=null
      --offset/int?=null
      --width/int=DEFAULT-REGISTER-WIDTH_
      --signed/bool=false -> none:
    assert: (width == 8) or (width == 16)
    if mask == null:
      mask = (width == 16) ? 0xFFFF : 0xFF
    if offset == null:
      offset = mask.count-trailing-zeros

    field-mask/int := (mask >> offset)
    assert: ((value & ~field-mask) == 0)  // fit check

    // Full-width direct write
    if ((width == 8)  and (mask == 0xFF)  and (offset == 0)) or
      ((width == 16) and (mask == 0xFFFF) and (offset == 0)):
      if width == 8:
        signed ? reg_.write-i8 register (value & 0xFF) : reg_.write-u8 register (value & 0xFF)
      else:
        signed ? reg_.write-i16-be register (value & 0xFFFF) : reg_.write-u16-be register (value & 0xFFFF)
      return

    // Read Reg for modification
    old-value/int? := null
    if width == 8:
      if signed :
        old-value = reg_.read-i8 register
      else:
        old-value = reg_.read-u8 register
    else:
      if signed :
        old-value = reg_.read-i16-be register
      else:
        old-value = reg_.read-u16-be register

    if old-value == null:
      logger_.error "write-register_: Read existing value (for modification) failed."
      throw "write-register_: Read failed."

    new-value/int := (old-value & ~mask) | ((value & field-mask) << offset)

    if width == 8:
      signed ? reg_.write-i8 register new-value : reg_.write-u8 register new-value
      return
    else:
      signed ? reg_.write-i16-be register new-value : reg_.write-u16-be register new-value
      return

    throw "write-register_: Unhandled Circumstance."
