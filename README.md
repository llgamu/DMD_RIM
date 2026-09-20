# DMD-RIM — Camera / NI / DMD synchronization for line-confocal imaging

This repository contains the control and synchronization code used to combine:

- a **Hamamatsu ORCA-Flash** camera operated in **Light Sheet / Progressive rolling-shutter mode**,
- a **NI USB-6343** data-acquisition board,
- and a **ViALUX DMD** operated in external-trigger slave mode.

The goal is to perform **line-confocal imaging** by synchronizing the DMD illumination pattern with the moving active region of the camera rolling shutter.

## System architecture

```text
ORCA camera
Light Sheet / Progressive mode
        |
        | H-sync
        v
   NI USB-6343
   counters
        |
        | TTL trigger
        v
   ViALUX DMD
   slave mode
        |
        v
moving illumination pattern
```

The camera acts as the **master clock**. Its H-sync signal follows the progression of the rolling shutter line by line.

The NI board is used to reshape, delay and eventually divide the H-sync stream before sending trigger pulses to the DMD.

## Timing parameters

### DMD

Typical operating frequency:

```text
~15 kHz
```

corresponding to a pattern period of approximately:

```text
T_DMD ≈ 66 µs
```

### Camera

The rolling-shutter line interval `T_H` can be adjusted over a wide range, from roughly a few microseconds to much slower values used for debugging.

For a line exposure time `T_exp`, the approximate width of the active rolling-shutter band is:

```text
N_band ≈ T_exp / T_H
```

For example:

```text
T_exp = 10 ms
T_H   = 1 ms

=> active band ≈ 10 camera lines
```

This relation is central to matching the DMD illumination band to the camera detection band.

## Main scripts

### `pulse.m`

Basic NI output test used during initial hardware validation.

### `Bandes.m`

Uses the camera H-sync as an external NI `ScanClock`.

A periodic ON/OFF signal is sent to an LED and observed by the camera. This provides a direct test of the correspondence between H-sync timing and rolling-shutter line position.

For example, with:

```text
T_H      = 1 ms
Exposure = 10 ms
LED      = 10 ms ON / 10 ms OFF
```

the measured spatial profile is triangular, as expected from the temporal integration of the square-wave illumination over a 10-line rolling-shutter window.

### `test_hsync_to_ctr1_delay.m`

Routes the camera H-sync through a hardware counter on the NI board.

This provides:

- deterministic hardware delay,
- controlled trigger pulse width,
- a first step toward H-sync division.

The next goal is to use two counters so that the DMD can be updated every `N` camera lines rather than necessarily every line.

### `DMD_slave_Marche_Lorry/`

Contains the DMD slave-mode code that has been experimentally validated.

Main files include:

```text
DMD.m
edf_nidaq.m
test_dmd_slave.m
```

The DMD is initialized in slave mode and waits for external trigger pulses before advancing through the loaded sequence.

### `Boucle_complete_Orca_NI_DMD.m`

Integrates the full synchronization chain:

```text
Camera H-sync
      |
      v
   NI ctr0
      |
      v
   NI ctr1
      |
      v
 DMD trigger
```

The first implementation is intentionally run with a relatively slow line interval, typically:

```text
T_H = 1 ms
```

to simplify debugging and oscilloscope measurements.

The architecture is intended to support:

```text
/1  -> one DMD update per camera line
/2  -> one DMD update every 2 camera lines
/3  -> one DMD update every 3 camera lines
/4  -> one DMD update every 4 camera lines
...
```

## Current status

```text
[x] Camera H-sync generated in Light Sheet / Progressive mode
[x] H-sync used by NI to control LED illumination
[x] Camera line timing validated experimentally
[x] H-sync relayed through NI hardware counter
[x] DMD slave mode validated with external triggers
[ ] Full Camera -> NI -> DMD loop validated experimentally
[ ] Trigger-to-optical DMD latency measured with photodiode
[ ] NI delay adjusted to compensate DMD latency
[ ] H-sync division by N validated with two counters
[ ] Moving DMD illumination band synchronized with rolling shutter
[ ] Speckle-band illumination implemented for confocal RIM
```

## Next experimental step

The next important calibration is to measure the actual delay between the electrical trigger sent to the DMD and the optically stable displayed pattern.

```text
Camera H-sync
      |
      +----------> oscilloscope
      |
      v
 NI counters
      |
      +----------> DMD trigger
                       |
                       v
                optical transition
                measured with
                photodiode
```

The measured DMD latency can then be compensated by the NI timing so that each DMD pattern is stable when the corresponding rolling-shutter band is active.

## Experimental data

Large experimental images are intentionally kept outside the Git repository.

The corresponding lab data are currently stored in:

```text
2026 09 DMD RIM EXP
```

Additional camera configuration notes are documented in:

```text
lightsheet mode.ppt
```

The Git history records the successive development and validation steps of the synchronization system.
