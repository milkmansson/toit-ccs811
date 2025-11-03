# Toit Driver for the AMS OSRAM CCS811 Ultra-Low Power Digital Gas and Indoor Air Quality Sensor
The CCS811 is a compact digital gas sensor from ams/ScioSense that measures
indoor air quality.  It uses a metal-oxide (MOX) sensing element to detects
levels of volatile organic compounds (TVOCs) and estimates equivalent CO₂ (eCO₂)
concentration.  The sensor analyzes how reactive gases affect the resistance of
the MOX layer using built-in algorithms to convert this data into air-quality
metrics.

![Front and back of a ccs811](images/ccs811.jpg)

> [!WARNING]
> This device is quite old, although they are about.  There are operational
> caveats for this device, including minimum run-in times, and firmware.
> Please read below.

## Features

### Reading eCO2 and eTVOC:
From the Datasheet:
> CCS811 supports intelligent algorithms to process raw sensor measurements to
> output equivalent Total Volatile Organic Compounds (eTVOC) and equivalent CO2
> (eCO2) values, where the main cause of VOCs is from humans. (pp 1).

The driver exposes these using the following functions.  Note that the value
returned will be the same if the driver is queried faster than the refresh rate
set using 'measure mode':
```Toit
// I2C Setup omitted

// Ccs811.MODE-0 = Off = No samples
// Ccs811.MODE-1 = Measure mode 1 = 1 sec samples
// Ccs811.MODE-2 = Measure mode 2 = 10 sec samples
// Ccs811.MODE-3 = Measure mode 3 = 60 sec samples
// Ccs811.MODE-4 = Measure mode 4 = no samples - but raw values returned every 250ms.

// Establish driver, constructor with measure mode 1
driver := Ccs811 ccs811-device --measure-mode=Ccs811.MODE-1

// Start the driver without waiting for the first sample
// driver := Ccs811 ccs811-device --measure-mode=Ccs811.MODE-1 --wait-for-first-sample=false

print "eCO2 $(driver.read-eco2) ppm"
print "eTVOC $(driver.read-etvoc) ppb"
```

### Temperature and Humidity Compensation:
If an external sensor is available, temperature and humidity information can be
passed to the CCS811.  The IC will automatically compensate its readings
accordingly.  A worked example of this exists in the
[examples](https://github.com/milkmansson/toit-ccs811/tree/main/examples)
folder.

### Baseline Correction and 'Manual Baseline Correction':
From the datasheet:
> The resistance of the sensitive layer is the output of the sensor.  However,
> metal oxide sensors do not give absolute readings. The resistance varies from
> sensor to sensor (manufacturing variation), from use-case to use-case, and
> over time. To mitigate this problem, the output of the sensor is normalized:
> R(sensor) is divided by R(a) . The value of R(a) is known as the baseline.
> R(a) cannot be determined by a one-time calibration; it is maintained
> on-the-fly in software.  This process is known as baseline correction.  The
> air quality is expected to vary in a typical environment so the minimum time
> over which a baseline correction is applied is 24 hours. Automatic baseline
> correction is enabled after initial device operation.

There is a mechanism to manually save and restore baseline values in the
BASELINE register.  (For additional information, search for application
note 'ams AN000370: CCS811 Clean Air Baseline Save and Restore'.)  This driver
exposes the feature in the following way:
```Toit
// I2C and driver setup omitted

// Get Baseline Value
baseline-correction-value/int := driver.get-baseline

// Set Baseline Value
driver.set-baseline baseline-correction-value
```
Note that the conditioning period must also be observed before using the BASELINE
register (see below).

### WAK Pin:
The device has a pin marked "WAK" which means "WAKE".  It must be held low for
the device to answer at all.  In my testing, I tied this to GND and did all
tests.  In scenarios requiring super low battery usage, this might be a smart
method to reduce power considerably.  This could be used in combination with
deep-sleep, using an extra GPIO pin in order to control the device.

### INT Pin:
The device has an interrupt pin, which alerts low.  Can be used to set the
interrupt pin each time data is ready.  Super useful if in low power mode - can
wake the microcontroller from deep sleep, where the microcontroller will perform
a read/write/save to the internet, etc, and put itself back to sleep again.
```Toit
// I2C Setup omitted

// Sets 60sec measurements, and enables the data-ready interrupt.
set-measure-mode Ccs811.MODE-3 --intrpt-data-ready=True
```
Alerts can be used to wake the microcontroller from deep sleep if specific eCO2
values have been reached as well.  Both threshold, and data-ready alerts can be
set at once.
```Toit
// I2C Setup omitted

// eCO2 values in ppm (defaults shown).  If threshold exceeded by 50ppm then
// the alert is generated.
driver.set-eco2-thresholds --low=1500 --high=2500

// Sets 1sec measurements, and enables the threshold interrupt.
set-measure-mode Ccs811.MODE-1 --intrpt-threshold=True
```
### Reset Pin:
RESET is an active low input and is pulled up to VDD by default.  RESET is
optional, but 4.7kOhm pull-up and/or decoupling of the nRESET pin may be
necessary to avoid erroneous noise-induced resets.  This pin is pulled low
internally during a reset.

## Caveats
### 'Early-Life'
The datasheet states that the device requires a Burn-In time:
> "CCS811 performance in terms of resistance levels and sensitivities will change
> during early life. The change in resistance is greatest over the first 48 hours
> of operation.  CCS811 controls the burn-in period allowing eCO 2 and eTVOC
> readings to be used from first power-on after 60 minutes of operation in modes
> 1-3." (pp12).

**However**, a later firmware update to the device reduces this requirement. Please
see below.

### 'Conditioning Period'
> After early-life (Burn-In) the conditioning or run-in period is the time
> required to achieve good sensor stability before measuring VOCs after long idle
> period.  After writing to MEAS_MODE to configure the sensor in mode 1-4, run
> CCS811 for 20 minutes, before accurate readings are generated. (pp12)

**However**, a later firmware update to the device changes this requirement.  Please
see below.

### Firmware and 'running-in'
Please see [this
readme](https://github.com/maarten-pennings/CCS811/blob/master/examples/ccs811flash/README.md).
The device this library was created with was already at v2.0.0, and recently
purchased devices appear to come with the latest firmware.  Therefore, this
library was not extended to include firmware update capability.  See the
[examples](https://github.com/milkmansson/toit-ccs811/tree/main/examples) folder
for examples of determining what APP-VERSION your IC has.  See the [this
repo](https://github.com/maarten-pennings/CCS811/blob/master/examples/ccs811flash/README.md)
for help on updating, if it is indeed required.  Raise an issue if a need exists
for updating in this driver.

### What is 'e'-CO2 and what are VOC's?
Some internet research revealed the following:
- **eCO2** is not a true CO₂ concentration measured with infrared absorption. It’s
  an algorithmic estimate of how much CO₂ would be present if the detected
  volatile organic compound (VOC) levels came from human metabolism (breathing,
  cooking, etc).
- The CCS811’s metal-oxide sensor measures how reactive gases change its
  resistance.  The internal algorithm then correlates those changes with CO₂
  levels typical of indoor air pollution and human occupancy.
- **eTVOC** A summed estimate of all oxidizable gases the sensor detects,
  expressed in ppb (parts per billion).  This value is also algorithmic: the
  CCS811’s MOX layer can’t distinguish individual chemicals, so it's output is
  an aggregate "VOC burden."

### Typical Ranges for eCO2
Typical ranges appear to be:
| eCO2	| (Indoor) Air Quality Interpretation |
| - | - |
| 400–800	ppm  | Fresh, well-ventilated air |
| 800–1200	ppm | Slightly stale / occupied room |
| 1200–2000	ppm | Poor ventilation |
| >2000 ppm |	Unhealthy, stuffy |

### Ranges for eTVOC
This is significantly harder to determine, as the sensor will react to quite a
wide range of compounds, including Combustion products, air fresheners, solvents
like nail polish remover, etc.
| eTVOC | (Indoor) Air Quality Interpretation |
| - | - |
| < 150 ppb	| Excellent air |
| 150–500 ppb	| Moderate pollutants, normal indoor |
| > 1000 ppb | Poor air quality |


## Sources/Links
Links to sources:
- [Maarten Pennings'](https://github.com/maarten-pennings) Github
  [repo](https://github.com/maarten-pennings/CCS811) with device driver,
  firmware files, and an updater. Invaluable - the AMS website seems to have
  forgotten this device.
- [Datasheet](https://cdn.sparkfun.com/assets/2/c/c/6/5/CN04-2019_attachment_CCS811_Datasheet_v1-06.pdf)

## Issues
If there are any issues, changes, or any other kind of feedback, please
[raise an issue](https://github.com/milkmansson/toit-ccs811/issues). Feedback is
welcome and appreciated!

## Disclaimer
- This driver has been written and tested with an unbranded module as pictured.
- All trademarks belong to their respective owners.
- No warranties for this work, express or implied.

## Credits
- AI has been used for reviews, analysing & compiling data/results, and
  assisting with ensuring accuracy.
- [Florian](https://github.com/floitsch) for the tireless help and encouragement
- The wider Toit developer team (past and present) for a truly excellent product

## About Toit
One would assume you are here because you know what Toit is.  If you dont:
> Toit is a high-level, memory-safe language, with container/VM technology built
> specifically for microcontrollers (not a desktop language port). It gives fast
> iteration (live reloads over Wi-Fi in seconds), robust serviceability, and
> performance that’s far closer to C than typical scripting options on the
> ESP32. [[link](https://toitlang.org/)]
- [Review on Soracom](https://soracom.io/blog/internet-of-microcontrollers-made-easy-with-toit-x-soracom/)
- [Review on eeJournal](https://www.eejournal.com/article/its-time-to-get-toit)
