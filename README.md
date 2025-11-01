# Toit Driver for the AMS OSRAM CCS811 Ultra-Low Power Digital Gas and Indoor Air Quality Sensor
The CCS811 is a compact digital gas sensor from ams/ScioSense that measures
indoor air quality.  It uses a metal-oxide (MOX) sensing element to detects
levels of volatile organic compounds (TVOCs) and estimates equivalent CO₂ (eCO₂)
concentration.  The sensor analyzes how reactive gases affect the resistance of
the MOX layer using built-in algorithms to convert this data into air-quality
metrics.

![Front and back of a ccs811](images/ccs811.jpg)

> [!WARNING]
> This device is allegedly obsolete.  It is quoted as being noisy and outdated.
> However they are still cheap, widely available, and good enough for many
> projects such as mine, making a driver worth the time to write.


## Caveats
- **'Early-Life':** - the datasheet states that the device requires a Burn-In time:
> "CCS811 performance in terms of resistance levels and sensitivities will change
> during early life. The change in resistance is greatest over the first 48 hours
> of operation.  CCS811 controls the burn-in period allowing eCO 2 and eTVOC
> readings to be used from first power-on after 60 minutes of operation in modes
> 1-3." (pp12)
- **'Conditioning Period':**
> After early-life (Burn-In) the conditioning or run-in period is the time
> required to achieve good sensor stability before measuring VOCs after long idle
> period.  After writing to MEAS_MODE to configure the sensor in mode 1-4, run
> CCS811 for 20 minutes, before accurate readings are generated. (pp12)
- **Temperature and Humidity Compensation:** If an external sensor is available,
temperature and humidity information can be passed to the CCS811.  The IC will
automatically compensate its readings accordingly.




 eCO2 and eTVOC Air quality sensor

## Features






### Sources
Links to sources:
- [Maarten Pennings'](https://github.com/maarten-pennings) Github
  [repo](https://github.com/maarten-pennings/CCS811) with device driver,
  firmware files, and an updater. Invaluable - the AMS website seems to have
  forgotten this device.


## Links
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
