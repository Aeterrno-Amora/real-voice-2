# Real Voice 2

This is inspired by Hataori's [*Real Voice*](https://github.com/hataori-p/real-voice) scripts, and serves the same purpose: extract parameters (pitch curve, pheneme duration, etc.) from a real singer and apply to a SV project. In other words, it aims to be a SV alternative of [*VocaListener*](https://staff.aist.go.jp/t.nakano/VocaListener/), although it (currently) lacks the power of iterative estimation.

The resulted voice is often more natural than someone without much voice tuning experiences can do. Here are some scenarios when this toolset is useful:
+ You have a "reference" voice for the song you're making, e.g., doing a cover, or you have a singer or yourself sing a "demonstrative" take for the song.
+ The result can be a good starting point, and you can tune it further for even better performances than the original singer.
+ The extracted parameters are valuable learning metarials. From beginners to masters, everyone who wish to produce more natural or more expressive voices can learn a lot from how real humans sing, and this tool visualizes the parameters in the same way as how you create them. Even singers can learn better when their singing is visualized together with the music score.

## Current State and Future Plan

| Selected Duration | 1s      | 30s  | 5min        |
| ----------------- | ------- | ---- | ----------- |
| Real Voice        | 2.3s    | 15s  | intolerable |
| Real Voice 2      | instant | 3.5s | 24s         |

`Load Pitch` is done, and is 5 to 100 times faster than the original version in *Real Voice* (see table above). It is very annoying if an artist has to wait for 2 or 3 seconds whenever he modifies one or two notes. But now it only takes a single hotkey and no wait. The speed to load long segments is also tolerable. The speedup mainly comes from:
+ Optimize the calculation that adds the control points.
+ Preprocess the parsing and interpolation of the pitch curve using an external python script, which is way faster than the internal lua script.
+ Data read by the lua script is cut down by 10 times in amount, and is structured in fixed-length floating-point values, allowing the lua script to jump arbitrarily by moving its file cursor. Thus it only reads the needed part each time, rather than the whole file.

`Notes From TextGrid` and other scripts are still under developement. I want to change some design and make them more integrated with the [Diffsinger](https://github.com/openvpi/DiffSinger) dataset labeling toolchains.

After that, Dynamics can be estimated in an iterative way by comparing the loudness of the rendered voice with that of the reference voice. Some other parameters can also be estimated by taking inspiration from Diffsinger's variance feature extractor and VocaListener.

## Installation

Download and extract everything, move the `sv-scripts` folder to your SynthV's script folder, which you can access from SynthV's menu `Scripts -> Open Scripts Folder`, or go to `C:\Users\<user_name>\Documents\Dreamtonics\Synthesizer V Studio\scripts\`. You should result in a folder structure like:
```
+ Synthesizer V Studio
  + scripts
    + Utilities
      + official scripts shipped with SynthV
    + Real Voice 2
      + some *.lua internal scripts

+ Somewhere you like
  + process.py
  + and other external scripts
```

Files outside the `sv-scripts` folder is for use outside of SynthV.

You will also need [Praat](https://www.fon.hum.uva.nl/praat/) and [Python](https://www.python.org/) installed.

## Usage

1. Follow the original *Real Voice*'s tutorial until you export the Praat Pitch Object in short text format. Save it anywhere you like, but the extension name should be `*.Pitch`.
2. Run `process.py` to preprocess data. It would prompt you to input a path to an `svp` file in order to configure output filenames accordingly. You can input the path by drag-ang-drop. It also prompts you to set some settings, hit `<Enter>` if you like the defaults.
3. Then it scans the `svp` file's directory for all possible tasks that preprocess exported raw data like `*.Pitch` into compact forms like `*_Pitch.txt` ready for use by internal scripts. You probably want to run the tasks marked with a star. If you don't like any of those, you can always input a path to a input file manually, and it guesses the task according to the extension name.
4. Now you can run script `Load Pitch` in SynthV Studio, on arbitrary selection of notes. If your project is named `<name>.svp`, it reads data from `<name>_Pitch.txt`.
5. If you have your `*.Pitch` file modified (e.g. you found a glitched pitch and went back to Praat to fix it), just hit `<Enter>` on the `process.py` that you have been running since step 2. It scans again and a star appears in front of your modified `*.Pitch`. Go through step 3 and 4 again and you pitch gets updated smoothly.
