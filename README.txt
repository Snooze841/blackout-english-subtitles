BLACKOUT - ENGLISH SUBTITLES
============================
Version 1.1, October 2026

Made in October 2026 by an enthusiast with the help of Claude (Anthropic).

Blackout (Deadline Multimedia / IQ Media, 1997) is a dark Danish interactive movie with real
actors, for Windows 3.1, on 3 CDs. You wake up without a memory and slowly find out that you may
be a murderer. This package is for the SWEDISH release, which has Swedish speech and no
subtitles. The script makes copies of your own three CDs in which 245 films have English
subtitles burned into the picture. Since version 1.1 there is also a strip with English text for
the 162 spoken moments without picture (phone calls, voices, narration).

This package contains NO game files: no films, no pictures, no game data. It contains only the
English subtitles (subtitles\*.ass, sound.json) and fingerprints (SHA-256) of the original films. You need
your own original CDs (or images of them). Your CDs and images are only read, never changed.


CONTENTS OF THIS PACKAGE
------------------------
  Patch Blackout.bat                     double-click this to make the subtitled images
  Blackout - English subtitles.ps1       the actual script (PowerShell, plain text)
  Start sound subtitles.bat              double-click this BEFORE you play, for the text strip
  Blackout - sound subtitles.ps1         the script of the text strip (PowerShell, plain text)
  subtitles\                             the subtitles: one .ass file per film, clips.json
                                         (fingerprints and sizes of the original films) and
                                         sound.json (the text for the spoken moments)
  README.txt                             this file
  LEESMIJ.txt                            this file in Dutch


WHAT YOU NEED
-------------
  - Windows 10 or 11 (the script uses PowerShell 5.1, which is part of Windows).
  - The three CDs of the Swedish release of Blackout, as:
      a) .iso images, or
      b) raw .bin/.cue images, or
      c) the CDs themselves in your CD or DVD drive (you then insert them one by one).
  - FFmpeg, a free program for films. The script offers to download the official build
    (FFmpeg 9.0.2 "essentials" from gyan.dev, linked from ffmpeg.org; 115 MB). The download is
    checked with a fingerprint (SHA-256) and only ffmpeg.exe and its licence are kept, in the
    folder ffmpeg next to the script. Already have it? Start the script with
    -FFmpeg "<path to ffmpeg.exe>".
  - About 3.6 GB of free disk space (the three new images take 1.9 GB, the CD folder 1.1 GB).


HOW TO USE
----------
  1. Extract the whole zip file (right-click > Extract All). Do not run anything from inside the
     zip file.
  2. Double-click "Patch Blackout.bat".
     If Windows shows a blue warning (SmartScreen), choose "More info" and "Run anyway". The
     script is plain text: you can read it with Notepad.
  3. Answer the questions:
       - download FFmpeg (Y), if it is not there yet;
       - "Where is CD 1": drag the .iso (or .cue/.bin) of CD 1 into the window and press Enter,
         or type the drive letter of your CD drive (e.g. E). For CD 2 and 3 the script often
         guesses the file itself (press Enter);
       - the folder for the new images and the CD folder (Enter = the folder of the CD 1 image).
  4. Wait. Copying the CDs takes a few minutes; drawing the subtitles into the films takes
     about 30 to 90 minutes, depending on your computer.
  5. Done: in the chosen folder are
       Blackout CD 1 (English subtitles).iso
       Blackout CD 2 (English subtitles).iso
       Blackout CD 3 (English subtitles).iso
       Blackout CDs (English subtitles)         (a folder: the three CDs together)
     Use the images instead of the original images, in the way you already play the game. In
     DOSBox, for example:
       imgmount D "Blackout CD 1 (English subtitles).iso" "Blackout CD 2 (English subtitles).iso" "Blackout CD 3 (English subtitles).iso" -t iso
     (Ctrl+F4 switches to the next CD when the game asks for another one.)
     Do you also want the text for the spoken moments? Then use the folder instead of the
     images: see the next chapter.

For advanced users (PowerShell):
  .\"Blackout - English subtitles.ps1" -Cd1 "x\CD 1.iso" -Cd2 "x\CD 2.iso" -Cd3 "x\CD 3.iso" -Output "x\English"
  More options: -FFmpeg "<path>", -Workers <n> (films encoded at the same time), -KeepWork
  (keep the subtitled films in the work folder), -NoWait.
  Made the images with version 1.0? This only makes the CD folder from them (about 1 minute):
  .\"Blackout - English subtitles.ps1" -FolderOnly -Output "<folder with the three new images>"

Was the script interrupted? Start it again with the same output folder: the films that were
already done (in the folder blackout-subtitles-work) are not made again.


TEXT FOR THE SPOKEN MOMENTS WITHOUT PICTURE
-------------------------------------------
Much of the story is only sound: phone calls, voices in your head, narration over a still
picture. There is no film to draw subtitles on, so a small program shows the text in a strip
over DOSBox while you play.
  1. In your DOSBox settings, replace the imgmount line by this line (with your own folder, and
     the same drive letter you used before):
       mount D "<your folder>\Blackout CDs (English subtitles)" -t cdrom -label BLACKOUT1
     The folder holds all three CDs, so you never need to swap CDs.
  2. Double-click "Start sound subtitles.bat". A black window appears. Leave it open.
  3. Start Blackout as usual. The text appears at the bottom of the DOSBox window or screen when
     someone speaks. When you close DOSBox, the black window closes by itself.
Good to know:
  - The strip needs the FOLDER, not the images: DOSBox then opens a real file on your PC for
    every sound, and the program looks a few times per second which .MOV file that is. It only
    reads the file names. It does not touch the game, DOSBox or Windows.
  - It looks for a program whose name starts with "dosbox". It does not work with real CDs, a
    virtual machine or another emulator.
  - The text follows the moment the game opens a sound, so it can run slightly ahead or behind.
  - Sounds without speech (music, effects) show nothing. That is normal.
  - Nothing appears? Look in blackout-sound-subtitles.log next to the script.


WHAT THE SCRIPT DOES
--------------------
The game plays its films with QuickTime 2.1 for Windows 3.1 (video Cinepak, sound IMA ADPCM).
The script:
  1. copies each CD to a new image and checks the volume name (BLACKOUT1, BLACKOUT2,
     BLACKOUT3);
  2. finds all QuickTime films (.MOV) on the copies and recognises the 245 films with speech by
     their fingerprint (SHA-256). Films it does not recognise stay as they are;
  3. lets FFmpeg draw the English subtitles onto the picture and encode the video again as
     Cinepak (the codec of the original);
  4. puts the new video into the original QuickTime file: the header and the sound of the
     original stay the same, only the video frames are new. (QuickTime 2.1 cannot open the
     files FFmpeg writes itself.) Each new film is at most as large as the original, so it fits
     in the same place on the CD; if needed the script encodes it again a little smaller;
  5. writes the films onto the copies, corrects the file sizes in the directory of the CD, checks
     the result and gives the copies their final names;
  6. copies all files of the three new images to one folder, for the text strip. Files that are
     on more than one CD are copied once. 23 of them differ per CD (20 pictures, 2 short sounds
     and the heart animation): the version of the lowest CD is used, so in a later act such a
     picture can look a little different than with CD swaps. None of these has text in the strip.
     The game only checks that the three marker files of the CDs exist.
With exactly the same CD images and FFmpeg 9.0.2 the result is byte for byte the same as the
tested version; the script tells you whether that is the case.
Nothing is installed and nothing in Windows is changed.


ABOUT THE SUBTITLES (HONESTLY)
------------------------------
  - The Swedish speech was written down automatically with Whisper (speech recognition by
    OpenAI) and then translated into English. Nobody checked the translation against the
    original script, so here and there a line may be wrong or odd. Names and some words may
    be misheard.
  - Films with picture have subtitles in the picture. Conversations that are only sound (162
    sound files) have their text in the strip, see above. The other sound files are music and
    effects.
  - The subtitles are at the bottom of the picture, white with a black edge.


TESTED
------
  - With .iso images of the three Swedish CDs, on Windows 10 22H2 (64-bit), with FFmpeg 9.0.2
    (downloaded by the script): the three new images were byte for byte the same as the tested
    version, on a computer with 8 processor cores in about 65 minutes. The game was played in
    Windows 3.1 in DOSBox Staging with QuickTime 2.1: the films play with subtitles.
  - Version 1.1 was run again from start to finish (with the films of the first run, so without
    the long step 4): the images were again byte for byte the same, and the CD folder is byte for
    byte the same as the folder the game was played from.
  - The text strip was tested with DOSBox Staging on Windows 10, full screen and in a window, with
    that CD folder: a spoken sound of the game, played in Windows 3.1, showed its text line by line
    and the strip disappeared at the end. In the game itself the strip recognised the sounds of
    the intro. Playing the game with the strip was only done with an earlier version that works
    the same way; nobody has played the whole game with it. Other versions of DOSBox have not been
    tested.
  - A .bin/.cue image (MODE1/2352) was only tested with an image made from the .iso. Reading
    from a real CD in a drive has not been tested. If reading from the drive fails, make an
    image with another program and use that.
  - Other releases of Blackout (other languages) are not recognised.


REMOVING
--------
Delete the new images, the CD folder and the folder ffmpeg next to the script. That is all.


CREDITS AND LICENCES
--------------------
  Blackout (c) 1997 Deadline Multimedia / IQ Media. This package contains no files of the game.
  The images and the folder the script makes are for your own use only: do not share them or
  put them online.

  FFmpeg is not part of this package; the script can download the official build by Gyan Doshi
  (gyan.dev). FFmpeg is free software under the GNU GPL version 3 (see ffmpeg\LICENSE.txt
  after downloading; source code: https://ffmpeg.org).
  The speech recognition was done with Whisper (OpenAI, MIT licence) via whisper.cpp.

  The rest of this package (the scripts, the .bat files and the English subtitles) was made in
  October 2026 by an enthusiast with the help of Claude (Anthropic). This package may be freely
  shared, used and modified.
