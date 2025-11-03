// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import log
import serial.device as serial
import serial.registers as registers

class Ccs811:
  static I2C-ADDRESS          ::= 0x5a
  static I2C-ADDRESS-ALT      ::= 0x5b    // When pin ADDR is high

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
  static REG-FW-BOOT-VERSION_ ::= 0x23 // R 2 bytes Firmware Boot Version.
  // The first 2 bytes contain the firmware version number for the boot code.
  static REG-FW-APP-VERSION_  ::= 0x24 // R 2 bytes Firmware Application Version.
  // The first 2 bytes contain the firmware version number for the application code
  static REG-INTERNAL-STATE_  ::= 0xA0 // R 1 byte Internal Status register
  static REG-ERROR-ID_        ::= 0xE0 // R 1 byte Error ID.
  // When the status register reports an error its source is located in this register
  static REG-SW-RESET_        ::= 0xFF // W 4 bytes
  // If the correct 4 bytes (0x11 0xE5 0x72 0x8A) are written
  // to this register in a single sequence the device will reset
  // and return to BOOT mode

  // BOOT MODE REGISTERS
  static REG-APP-ERASE_  ::= 0xF1  // write 4 bytes cookie E7 A7 E6 09
  static REG-APP-DATA_   ::= 0xF2  // write chunks (boot tbl says size 9 bytes)
  static REG-APP-VERIFY_ ::= 0xF3
  static REG-APP-START_  ::= 0xF4  // write with no data to jump to App

  static MEAS-MODE-MASK_              ::= 0b01110000
  static MEAS-INTRPT-DATA-READY-MASK_ ::= 0b00001000
  static MEAS-INTRPT-THRESHOLD-MASK_  ::= 0b00000100

  static MODE-0 ::= 0b000 // Mode 0 – Idle (Measurements are disabled in this mode)
  static MODE-1 ::= 0b001 // Mode 1 – Constant power mode, IAQ measurement every second
  static MODE-2 ::= 0b010 // Mode 2 – Pulse heating mode IAQ measurement every 10 seconds
  static MODE-3 ::= 0b011 // Mode 3 – Low power pulse heating mode IAQ measurement every 60 seconds
  static MODE-4 ::= 0b100 // Mode 4 – Constant power mode, sensor measurement every 250ms
  //static MODE-R ::= 0b1xx Reserved modes (For future use)

  static STATUS-FW-MODE-MASK_       ::= 0b10000000  // 0 = boot mode, 1 = app mode
  static STATUS-APP-ERASE-MASK_     ::= 0b01000000  // Boot mode only
  static STATUS-APP-VERIFY-MASK_    ::= 0b00100000  // Boot mode only
  static STATUS-APP-VALID-MASK_     ::= 0b00010000  // Boot mode only
  static STATUS-DATA-READY-MASK_    ::= 0b00001000  // 0 = no new samples 1= new samples, clears on read
  static STATUS-ERROR-MASK_         ::= 0b00000001  // 1= error, read ERROR-ID to obtain error and/or clear

  static RAW-DATA-CURRENT-SELECTED-MASK_ ::= 0b11111100_00000000  // Sensor current: 0uA to 63uA
  static RAW-ADC-READING-MASK_           ::= 0b00000011_11111111  // LSB 1023 = 1.65V
  static RAW-ADC-VOLTAGE-LSB_            ::= 1.65 / 1023.0

  static ENV-DATA-HUMIDITY-MASK_         ::= 0b11111111_11111111_00000000_00000000 //  1/512 %RH
  static ENV-DATA-TEMPERATURE-MASK_      ::= 0b00000000_00000000_11111111_11111111 //  1/512c with −25c offset.

  static HW-VERSION-PRODUCT-MASK_ ::= 0b11110000
  static HW-VERSION-VARIANT-MASK_ ::= 0b00001111

  static FW-VERSION-MAJOR-MASK_   ::= 0b11110000_00000000
  static FW-VERSION-MINOR-MASK_   ::= 0b00001111_00000000
  static FW-VERSION-TRIVIAL-MASK_ ::= 0b00000000_11111111

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
  alg-byte-array_/ByteArray? := ?
  wait-timeout/Duration? := null
  cached-measure-mode_/int? := null

  // Because this value can't be read, cach values for query (from datasheet)
  cached-humidity-corr-pct_/float := 50.0
  cached-temp-corr-c_/float := 25.0

  constructor
      device/serial.Device
      --measure-mode/int=MODE-1
      --wait-for-first-sample/bool=true
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "ccs811"
    reg_ = device.registers
    alg-byte-array_ = null

    // Check Correct HW ID:
    hw-id := get-hardware-id
    if hw-id != 0x81:
      logger_.error "Incorrect HW ID" --tags={"hw-id":hw-id,"expected":0x81}
      throw "Incorrect HW ID"

    // Check for App Mode
    if not is-app-mode:
      logger_.debug "Initialising." --tags={"initial-mode":"BOOT-MODE"}
      set-app-mode_
    else:
      logger_.debug "Initialising." --tags={"initial-mode":"APP-MODE"}

    // Select Default Measurement mode
    set-measure-mode measure-mode

    // Log Power-On Baseline Value
    logger_.debug "Power-on Baseline Value" --tags={"baseline": "0x$(%04x get-baseline)"}

    // Get first values for alg-byte-array_, with twice the wait time, just in case
    if wait-for-first-sample:
      read-alg-register_ (get-timeout-from-mode_ * 2) --wait=true

  set-app-mode_ -> none:
    // Write register pointer only (no payload)
    reg_.write-bytes REG-APP-START_ #[]    // Zero-length write is required by the bootloader
    sleep --ms=2                           // App start time is ≥ 1 ms

    // Confirm FW_MODE == 1 (App)
    if not is-app-mode:
      logger_.error "set-app-mode_: FAILED still in BOOT mode after setting APP mode"
      throw "set-app-mode_: FAILED still in BOOT mode after setting APP mode"

  /**
  Selects measurement mode and optional interrupt configuration.

  drive-mode: one of MODE-0..MODE-4
  intrpt-data-ready: when true INT pin asserts each time new data is ready
  intrpt-threshold:  when true INT only asserts when thresholds are crossed
  */
  set-measure-mode drive-mode/int --intrpt-data-ready/bool=false --intrpt-threshold/bool=false -> none:
    assert: 0 <= drive-mode <= 0b100
    value := (drive-mode << 4)
    if intrpt-data-ready: value |= MEAS-INTRPT-DATA-READY-MASK_
    if intrpt-threshold: value |= MEAS-INTRPT-THRESHOLD-MASK_
    logger_.debug "Measure mode set." --tags={"register" : "$(bits-16_ value --min-display-bits=8)"}
    write-register_ REG-MEAS-MODE_ value --width=8
    alg-byte-array_ = null
    cached-measure-mode_ = drive-mode
    // Set wait-timeout = read the register instead of using cached value.
    wait-timeout = get-timeout-from-mode_

  /**
  Returns the current drive MODE-0..MODE-4 from MEAS_MODE.
  */
  get-measurement-mode -> int:
    return read-register_ REG-MEAS-MODE_ --mask=MEAS-MODE-MASK_ --width=8

  /**
  Return expected wait timeout by querying measure mode.

  Also adds % margin as these values will typically be used for timeouts.
  */
  get-timeout-from-mode_ measure-mode/int=get-measurement-mode --margin/float=0.1 -> Duration?:
    assert: 0 <= margin < 1.0
    dur/Duration := (Duration --ms=0)
    raw-measure-mode := get-measurement-mode
    if raw-measure-mode == MODE-0:             // Off
      return null
    if raw-measure-mode == MODE-1:             // Typical = 1s
      dur = (Duration --s=1)
      return dur + (dur * margin)
    if raw-measure-mode == MODE-2:             // Typical = 10s
      dur = (Duration --s=10)
      return dur + (dur * margin)
    if raw-measure-mode == MODE-3:             // Typical = 60s
      dur = (Duration --s=60)
      return dur + (dur * margin)
    if raw-measure-mode == MODE-4:             // Typical = 250ms
      dur = (Duration --ms=250)
      return dur + (dur * margin)
    logger_.error "Unexpected measure mode." --tags={"raw-measure-mode":raw-measure-mode}
    throw "Unexpected measure mode."
    return null

  /**
  Returns true when a new sample is ready.

  Clears when REG-ALG-RESULT-DATA_ is read (when in mode 1–3).  When in mode 4
    it flags at 250 ms intervals.  Will work regardless of whether the interrupt
    pin is configured to assert.
  */
  is-data-ready -> bool:
    data-ready := read-register_ REG-STATUS_ --mask=STATUS-DATA-READY-MASK_ --width=8
    return data-ready != 0

  /**
  Returns true when an error has happened.

  Reason stored in REG-ERROR-ID_.  Clears when that is read.
  */
  is-error -> bool:
    iserror := read-register_ REG-STATUS_ --mask=STATUS-ERROR-MASK_ --width=8
    return iserror != 0

  /**
  Returns true when App Firmware is valid.
  */
  is-app-valid -> bool:
    raw := read-register_ REG-STATUS_ --mask=STATUS-APP-VALID-MASK_ --width=8
    return raw != 0

  /**
  Returns true when App Verification has completed successfully.

  Flag is cleared by APP_START, SW_RESET and nRESET.  After issuing a VERIFY
    command the application software must wait 70ms before issuing any further
    transactions to CCS811 over the I²C interface.
  */
  is-app-verified -> bool:
    raw := read-register_ REG-STATUS_ --mask=STATUS-APP-VERIFY-MASK_ --width=8
    return raw != 0

  /**
  Returns true when in boot mode.
  */
  is-boot-mode -> bool:
    raw := read-register_ REG-STATUS_ --mask=STATUS-FW-MODE-MASK_ --width=8
    return raw == 0

  /**
  Returns true when in app mode and ready to take measurements.
  */
  is-app-mode -> bool:
    raw := read-register_ REG-STATUS_ --mask=STATUS-FW-MODE-MASK_ --width=8
    return raw == 1

  /**
  Returns true when app erase is complete/valid.
  */
  is-erase-complete -> bool:
    raw := read-register_ REG-STATUS_ --mask=STATUS-APP-ERASE-MASK_ --width=8
    return raw != 0

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
  Gets error bitmask from the error register.

  Reading REG-ERROR-ID_ clears the error, reading via ALG register doesn't.
  */
  get-error-bitmask_ --clear=true -> int:
    if clear:
      return read-register_ REG-ERROR-ID_ --width=8
    else:
      read-alg-register_
      return alg-byte-array_[5]

  /**
  Gets human readable error text for each flag in the error register.
  */
  get-error-text error-bitmask/int=get-error-bitmask_ -> string:
    error-output := ""
    if (error-bitmask & ERROR-WRITE-REG-INVALID-MASK_) != 0:
      error-output = "WRITE-REG-INVALID,$(error-output)"
    if (error-bitmask & ERROR-READ-REG-INVALID-MASK_) != 0:
      error-output = "READ-REG-INVALID,$(error-output)"
    if (error-bitmask & ERROR-MEAS-MODE-INVALID-MASK_) != 0:
      error-output = "MEAS-MODE-INVALID,$(error-output)"
    if (error-bitmask & ERROR-MAX-RESISTANCE-MASK_) != 0:
      error-output = "ERROR-MAX-RESISTANCE,$(error-output)"
    if (error-bitmask & ERROR-HEATER-FAULT-MASK_) != 0:
      error-output = "ERROR-HEATER-FAULT,$(error-output)"
    if (error-bitmask & ERROR-HEATER-SUPPLY-MASK_) != 0:
      error-output = "ERROR-HEATER-SUPPLY,$(error-output)"
    return error-output

  /**
  Set the temp and humidity values for the sensor to calibrate with.
  */
  set-temp-humidity --humidity/float?=null --temp/float?=null -> none:
    // Check and set cache
    if humidity != null:
      cached-humidity-corr-pct_ = humidity
    if temp != null:
      cached-temp-corr-c_ = temp
    if cached-temp-corr-c_ < -25.0:
      cached-temp-corr-c_ = -25.0

    // Calculate register values
    raw-temp := (((cached-temp-corr-c_ + 25.0) * 512.0).round).to-int
    rel-hum := clamp-value_ cached-humidity-corr-pct_ --lower=0.0 --upper=100.0
    raw-hum := ((rel-hum * 512.0).round).to-int

    // Doing this way - missing 32 bit function in base library
    raw := (raw-hum << 16) | raw-temp
    write-register_ REG-ENV-DATA_ raw --width=32

    // Report changed values
    if humidity != null:
      logger_.info "Set calibration humidity. " --tags={"humidity":cached-humidity-corr-pct_ , "raw":raw-hum}
    if temp != null:
      logger_.info "Set calibration temperature. " --tags={"temp":cached-temp-corr-c_,"raw":raw-temp}

  /**
  Return the temp and humidity values for the sensor to calibrate with.
  */
  get-temp-calibration -> float:
    return cached-temp-corr-c_

  get-humidity-calibration -> float:
    return cached-humidity-corr-pct_

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
  Returns the firmware BOOT version (not the same as App version).
  */
  get-firmware-boot-version -> string:
    raw := read-register_ REG-FW-BOOT-VERSION_ --width=16
    major := (raw & FW-VERSION-MAJOR-MASK_) >> FW-VERSION-MAJOR-MASK_.count-trailing-zeros
    minor := (raw & FW-VERSION-MINOR-MASK_)  >> FW-VERSION-MINOR-MASK_.count-trailing-zeros
    trivial := (raw & FW-VERSION-TRIVIAL-MASK_) >> FW-VERSION-TRIVIAL-MASK_.count-trailing-zeros
    return "$major.$minor.$trivial"

  /**
  Returns the firmware APP version (not the same as Boot version).
  */
  get-firmware-app-version -> string:
    raw := read-register_ REG-FW-APP-VERSION_ --width=16
    major := (raw & FW-VERSION-MAJOR-MASK_) >> FW-VERSION-MAJOR-MASK_.count-trailing-zeros
    minor := (raw & FW-VERSION-MINOR-MASK_)  >> FW-VERSION-MINOR-MASK_.count-trailing-zeros
    trivial := (raw & FW-VERSION-TRIVIAL-MASK_) >> FW-VERSION-TRIVIAL-MASK_.count-trailing-zeros
    return "$major.$minor.$trivial"

  /**
  Caches latest read into $alg-byte-array_
  */
  read-alg-register_ timeout/Duration=get-timeout-from-mode_ --wait/bool=false -> none:
    if not is-app-mode:
      logger_.error "read-alg-register_: Not in APP mode"
      // throw "read-alg-register_: Not in APP mode"
      return
    if get-measurement-mode == MODE-0:
      logger_.error "read-alg-register_: MEAS_MODE is Idle (MODE-0)"
      // throw "read-alg-register_: MEAS_MODE is Idle (MODE-0)"
      return

    if wait:
      deadline := Time.monotonic-us + timeout.in-us
      while Time.monotonic-us < deadline:
        if is-data-ready:
          alg-byte-array_ = reg_.read-bytes REG-ALG-RESULT-DATA_ 8
          if alg-byte-array_ == null or alg-byte-array_.size != 8:
            logger_.debug "read-alg-register_: ALG read failed."
            throw "ALG read failed"
          //else:
            //logger_.debug "read-alg-register_: fresh read-wait executed."
          return
        sleep --ms=250
      logger_.warn "read-alg-register_: timeout expired." --tags={"timeout-ms":timeout.in-ms}

    else:
      alg-byte-array_ = reg_.read-bytes REG-ALG-RESULT-DATA_ 8
      if alg-byte-array_ == null or alg-byte-array_.size != 8:
        logger_.error "read-alg-register_: ALG read failed."
        throw "ALG read failed"
      else:
        //logger_.debug "read-alg-register_: fresh read (non-wait) executed."


  /**
  Gives eco2 read from cache.

  Checks for new sensor data before decoding cached bytes.
  - alg-byte-array_[0] << alg-byte-array_[1] is eCO2.
  */
  read-eco2 --wait/bool=false -> int?:
    if (cached-measure-mode_ < MODE-1) and (cached-measure-mode_ > MODE-3) : return null
    read-alg-register_ --wait=wait
    if (alg-byte-array_ != null):
      return i16-be_ alg-byte-array_[0] alg-byte-array_[1]
    else:
      return null

  /**
  Gives etvoc read from cache.

  Checks for new sensor data before decoding cached bytes.
  - alg-byte-array_[2] << alg-byte-array_[3] is eTVOC.
  */
  read-etvoc --wait/bool=false -> int?:
    if (cached-measure-mode_ < MODE-1) and (cached-measure-mode_ > MODE-3) : return null
    read-alg-register_ --wait=wait
    if alg-byte-array_ != null:
      return i16-be_ alg-byte-array_[2] alg-byte-array_[3]
    else:
      return null

  /**
  Gives status data read from cache.

  Checks for new sensor data before decoding cached bytes. Reading ALG-DATA will
   clear DATA_READY so function reads REG-STATUS_ instead.  (To read via ALG
   data array, set --cached to TRUE).

  - alg-byte-array_[4] is status.
  */
  get-status-bitmask_ --clear/bool=false --wait/bool=false -> int?:
    if clear:
      // Refresh pulls fresh data and could likely clear
      if (cached-measure-mode_ < MODE-1) and (cached-measure-mode_ > MODE-3) : return null
      read-alg-register_ --wait=wait
      if alg-byte-array_ != null:
        return alg-byte-array_[4]
      else:
        return null
    else:
      // reading via REG-STATUS_ will not clear error assert
      raw := read-register_ REG-STATUS_ --width=8
      return raw

  /**
  Gives raw current read from cache.

  Checks for new sensor data before decoding cached bytes.
  - alg-byte-array_[6] << alg-byte-array_[7] is raw read register.
  - RAW-DATA-CURRENT-SELECTED-MASK_ masks the raw current from that 16 bit
  value. Sensor current is an integer from 0uA..63uA.
  */
  read-raw-current --wait/bool=false -> float?:
    read-alg-register_ --wait=wait
    if alg-byte-array_ != null:
      raw16  := ((alg-byte-array_[6] & 0xFF) << 8) | (alg-byte-array_[7] & 0xFF)
      return ((raw16 >> (RAW-ADC-READING-MASK_.count-trailing-zeros)) & RAW-DATA-CURRENT-SELECTED-MASK_).to-float / 1e6
    else:
      return null

  /**
  Gives raw sensor voltage read from cache.

  Checks for new sensor data before decoding cached bytes.
  - alg-byte-array_[6] << alg-byte-array_[7] is raw read register.
  - RAW-ADC-READING-MASK_ masks the raw current from that 16 bit value.
  */
  read-raw-voltage --wait/bool=false -> float?:
    read-alg-register_ --wait=wait
    if alg-byte-array_ != null:
      raw16  := ((alg-byte-array_[6] & 0xFF) << 8) | (alg-byte-array_[7] & 0xFF)
      return (raw16 & RAW-ADC-READING-MASK_) * RAW-ADC-VOLTAGE-LSB_
    else:
      return null

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
    assert: (width == 8) or (width == 16) or (width == 32)
    if mask == null:
      if      width == 8:  mask = 0xFF
      else if width == 16: mask = 0xFFFF
      else:                mask = 0xFFFFFFFF
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
    if width == 32:
      if signed:
        register-value = reg_.read-i32-be register
      else:
        register-value = reg_.read-u32-be register

    if register-value == null:
      logger_.error "read-register_: Read failed."
      throw "read-register_: Read failed."

    if ((mask == 0xFFFF) or (mask == 0xFF) or (mask == 0xFFFFFFFF)) and (offset == 0):
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
    assert: (width == 8) or (width == 16) or (width == 32)
    if mask == null:
      if      width == 8:  mask = 0xFF
      else if width == 16: mask = 0xFFFF
      else:                mask = 0xFFFFFFFF
    if offset == null:
      offset = mask.count-trailing-zeros

    field-mask/int := (mask >> offset)
    assert: ((value & ~field-mask) == 0)  // fit check
    bit-32-ba := ?

    // Full-width direct write
    if ((width == 8)  and (mask == 0xFF)  and (offset == 0)) or
      ((width == 16) and (mask == 0xFFFF) and (offset == 0)) or
      ((width == 32) and (mask == 0xFFFFFFFF) and (offset == 0)):
      if width == 8:
        signed ? reg_.write-i8 register (value & 0xFF) : reg_.write-u8 register (value & 0xFF)
      else if width == 16:
        signed ? reg_.write-i16-be register (value & 0xFFFF) : reg_.write-u16-be register (value & 0xFFFF)
      else:
        bit-32-ba = to-bytes32 (value & 0xFFFFFFFF)
        signed ? reg_.write-i32-be register (value & 0xFFFFFFFF) : reg_.write-bytes register bit-32-ba
      return

    // Read Reg for modification
    old-value/int? := null
    if width == 8:
      if signed :
        old-value = reg_.read-i8 register
      else:
        old-value = reg_.read-u8 register
    else if width == 16:
      if signed :
        old-value = reg_.read-i16-be register
      else:
        old-value = reg_.read-u16-be register
    else:
      if signed :
        old-value = reg_.read-i32-be register
      else:
        old-value = reg_.read-u32-be register


    if old-value == null:
      logger_.error "write-register_: Read existing value (for modification) failed."
      throw "write-register_: Read failed."

    new-value/int := (old-value & ~mask) | ((value & field-mask) << offset)

    if width == 8:
      signed ? reg_.write-i8 register new-value : reg_.write-u8 register new-value
      return
    else if width == 16:
      signed ? reg_.write-i16-be register new-value : reg_.write-u16-be register new-value
      return
    else if width == 32:
      bit-32-ba = to-bytes32 new-value
      signed ? reg_.write-i32-be register new-value : reg_.write-bytes register bit-32-ba
      return
    throw "write-register_: Unhandled Circumstance."

  /**
  Provides strings to display bitmasks nicely when testing.
  */
  bits-16_ x/int --min-display-bits/int=0 -> string:
    assert: (x >= 0) and (x <= 0xFFFFFFFF)
    out-string := "$(%b x)"
    if (x > 0xFFFF) or (min-display-bits > 24):
      out-string = out-string.pad --left 32 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16]).$(out-string[16..20]).$(out-string[20..24]).$(out-string[24..28]).$(out-string[28..32])"
      return out-string
    if (x > 0xFFF) or (min-display-bits > 16):
      out-string = out-string.pad --left 24 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16]).$(out-string[16..20]).$(out-string[20..24])"
      return out-string
    if (x > 0xFF) or (min-display-bits > 8):
      out-string = out-string.pad --left 16 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16])"
      return out-string
    else if (x > 0xF) or (min-display-bits > 4):
      out-string = out-string.pad --left 8 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8])"
      return out-string
    else:
      out-string = out-string.pad --left 4 '0'
      out-string = "$(out-string[0..4])"
      return out-string

  /**
  Turns a 32 bit value into a 4xbyte byte array
  */
  to-bytes32 value/int -> ByteArray:
    return #[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8)  & 0xFF,
      value & 0xFF
    ]

  /**
  Formats a Duration as HH:MM:SS.mmm, or MM:SS.mmm, or SS.mmm
  */
  duration-to-string dur/Duration -> string:
    total-ms := dur.in-ms
    sign := ""
    if total-ms < 0:
      sign = "-"
      total-ms = -total-ms

    ms/int := total-ms % 1000
    total-s := total-ms / 1000
    s/int := total-s % 60
    total-m/int := total-s / 60
    m := total-m % 60
    total-h := total-m % 60
    h:= total-h

    if h > 0:
      return "$sign$(%02d h):$(%02d m):$(%02d s).$(%03d ms)"
    else if m > 0:
      return "$sign$(%02d m):$(%02d s).$(%03d ms)"
    else:
      return "$sign$(%01d s).$(%03d ms)"

  /**
  Prints/logs current status of interesting registers/bits, for troubleshooting.
  */
  dump-status -> none:
    s := get-status-bitmask_ --clear=false
    baseline := get-baseline
    hw-id := get-hardware-id
    error-bitmask := get-error-bitmask_ --clear=false
    error-text := get-error-text error-bitmask
    logger_.info "DUMP STATUS" --tags={
      "status-register": "$(bits-16_ s --min-display-bits=8)",
      "FW-MODE_": "$(%0b (s >> STATUS-FW-MODE-MASK_.count-trailing-zeros) & 1)",
      "APP-VALID_": "$(%0b (s >> STATUS-APP-VALID-MASK_.count-trailing-zeros) & 1)",
      "DATA-READY_": "$(%0b (s >> STATUS-DATA-READY-MASK_.count-trailing-zeros) & 1)",
      "ERROR_": "$(%0b (s & STATUS-ERROR-MASK_.count-trailing-zeros) & 1)",
      "BASELINE_": "0x$(%04x baseline)",
      "HW-ID_": "0x$(%02x hw-id)",
      "error-register": "$(bits-16_ error-bitmask --min-display-bits=8)",
      "error-text": error-text
    }
