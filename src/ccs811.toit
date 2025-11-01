// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import log
import serial.device as serial
import serial.registers as registers

class Ccs811:
  static I2C-ADDRESS          ::= 0x5a
  static I2C-ADDRESS-ALT      ::= 0x5b    // When pin AD0 is high

  // APP MODE REGISTERS
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

  // BOOT MODE REGISTERS
  static REG-APP-ERASE_  ::= 0xF1
  static REG-APP-DATA_   ::= 0xF1
  static REG-APP-VERIFY_ ::= 0xF1
  static REG-APP-START_  ::= 0xF1




  static STATUS-FW-MODE-MASK_       ::= 0b10000000  // 0 = boot mode, 1 = app mode
  static STATUS-APP-ERASE-MASK_     ::= 0b01000000  // Boot mode only
  static STATUS-APP-VERIFY-MASK_    ::= 0b00100000  // Boot mode only
  static STATUS-APP-VALID-MASK_     ::= 0b00010000  // Boot mode only
  static STATUS-DATA-READY-MASK_    ::= 0b00001000  // 0 = no new samples 1= new samples, clears on read
  static STATUS-ERROR-MASK_         ::= 0b00000001  // 1= error, read ERROR-ID to obtain error and/or clear

  static MEAS-MODE-DRIVE-MODE-MASK_ ::= 0b01110000
  static INT-DATA-READY-MASK_       ::= 0b01110000
  static MEAS-MODE-THRESH-MASK_     ::= 0b01110000

  static RAW-DATA-CURRENT-SELECTED-MASK_ ::= 0b11111100_00000000  // Sensor current: 0uA to 63uA
  static RAW-ADC-READING-MASK_           ::= 0b00000011_11111111  // LSB 1023 = 1.65V
  static RAW-ADC-VOLTAGE-LSB_            ::= 1023 / 1.65

  static ENV-DATA-HUMIDITY-MASK_         ::= 0b11111111_11111111_00000000_00000000  // LSB 1023 = 1.65V
  static ENV-DATA-TEMPERATURE-MASK_      ::= 0b00000000_00000000_11111111_11111111  // LSB 1023 = 1.65V

  static HW-VERSION-PRODUCT-MASK_ ::= 0b11110000
  static HW-VERSION-VARIANT-MASK_ ::= 0b00001111

  static FW-BOOT-VERSION-MAJOR-MASK_   ::= 0b11110000_00000000
  static FW-BOOT-VERSION-MINOR-MASK_   ::= 0b00001111_00000000
  static FW-BOOT-VERSION-TRIVIAL-MASK_ ::= 0b00000000_11111111

  static ERROR-WRITE-REG-INVALID-MASK_ ::= 0b10000000
  static ERROR-READ-REG-INVALID-MASK_  ::= 0b01000000
  static ERROR-MEAS-MODE-INVALID-MASK_ ::= 0b00100000
  static ERROR-MAX-RESISTANCE-MASK_    ::= 0b00010000
  static ERROR-HEATER-FAULT-MASK_      ::= 0b00001000
  static ERROR-HEATER-SUPPLY-MASK_     ::= 0b00000100

  static SW-BOOT-MODE-RESET_ ::= #[0x11, 0xe5, 0x72, 0x8a]

  static RH-LSB_  ::= 512.0 // 1/512% RH

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
  Reads the current across the sensor (0uA to 63uA)
  */
  read-raw-sensor-current -> float:
    raw := read-register_ REG-RAW-DATA_ --mask=RAW-DATA-CURRENT-SELECTED-MASK_ --width=16
    return raw

  /**
  Reads the raw voltage across the sensor (1023 = 1.65V)
  */
  read-raw-sensor-voltage -> float:
    raw := read-register_ REG-RAW-DATA_ --mask=RAW-ADC-READING-MASK_ --width=16
    return raw * RAW-ADC-VOLTAGE-LSB_

  /**
  Set the humidity value for the sensor to calibrate with
  */
  set-humidity value/float -> none:
    rel-hum := clamp-value_ value --lower=0.0 --upper=100.0
    raw := ((rel-hum * 512.0).round).to-int
    //write-register_ REG-ENV-DATA_ raw --mask=ENV-DATA-HUMIDITY-MASK_ --width=32
    write-register_ REG-ENV-DATA_ raw --width=16

  /**
  Returns the value of the BASELINE register.

  A two byte read/write register which contains an encoded version of the
    current baseline used in Algorithm Calculations.

  A previously stored value may be written back to this two byte register and
    the Algorithms will use the new value in its calculations (until it adjusts
    it as part of its internal Automatic Baseline Correction).

  For more information, refer to ams application note AN000370: CCS811 Clean Air
    Baseline Save and Restore.
  */
  get-baseline -> int:
    return read-register_ REG-BASELINE_  --width=16

  /**
  Returns the value of the BASELINE register.

  See $get-baseline
  */
  set-baseline value/int -> none:
    assert: 0x0 <= value <= 0xFFFF
    write-register_ REG-BASELINE_ value --width=16


  /**
  Returns the value of the HARDWARE-ID register.
  */
  get-hardware-id -> int:
    return read-register_ REG-HW-ID_ --width=8

  /**
  Returns the value of the HARDWARE-ID (PRODUCT) register.
  */
  get-hardware-version-product -> int:
    return read-register_ REG-HW-VERSION_ --mask=HW-VERSION-PRODUCT-MASK_ --width=8

  /**
  Returns the value of the HARDWARE-ID (VARIANT) register.
  */
  get-hardware-version-variant -> int:
    return read-register_ REG-HW-VERSION_ --mask=HW-VERSION-VARIANT-MASK_ --width=8

  /**
  Returns the value of the HARDWARE-ID (VARIANT) register.
  */
  get-firmware-boot-version -> int:
    raw := read-register_ REG-BOOT-VERSION_ --width=16
    major := raw & FW-BOOT-VERSION-MAJOR-MASK_
    minor := raw & FW-BOOT-VERSION-MINOR-MASK_
    trivial := raw & FW-BOOT-VERSION-TRIVIAL-MASK_
    return "$major.$minor.$trivial"


  /**
  Set the temperature value for the sensor to calibrate with
  */
  set-temperature temp/float -> none:
    assert: temp >= -25.0
    raw := (((temp + 25.0) * 512.0).round).to-int
    //write-register_ REG-ENV-DATA_ raw --mask=ENV-DATA-TEMPERATURE-MASK_ --width=32
    write-register_ (REG-ENV-DATA_ + 2) raw --width=16

  read-alg-register_ -> none:
    ba := reg_.read-bytes REG-ALG-RESULT-DATA_ 8
    // ba[0] << ba[1]   eCO2
    // ba[2] << ba[3]   eTVOC
    // ba[4]            Status
    // ba[5]            Status
    // ba[6] << ba[7]   RAW-DATA




  /**
  Parse big-endian 16bit from two separate bytes - eg when reading from FIFO.
  */
  i16-be_ high-byte/int low-byte/int --signed/bool=false -> int:
    high := high-byte & 0xFF
    low := low-byte & 0xFF
    value := (high << 8) | low
    if signed:
      return (value >= 0x8000) ? (value - 0x10000) : value
    else:
      return value

  /**
  Clamps the supplied value to specified limit.
  */
  clamp-value_ value/any --upper/any?=null --lower/any?=null -> any:
    if (upper != null) and (lower != null):
      assert: upper > lower
    if upper != null: if value > upper:  return upper
    if lower != null: if value < lower:  return lower
    return value

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
