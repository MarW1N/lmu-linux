# Description
I made this launch_lmu.sh to make it easier for myself to launch LMU so that I can use TinyPedal (https://github.com/TinyPedal/TinyPedal) using the native LMU API with the help of *lmushm* and *lmubridge.exe* from https://github.com/Spacefreak18/simshmbridge and thought someone else might find it useful.

Then I found the excellent LMUFFB (https://github.com/coasting-nc/LMUFFB) to make use of LMU telemetry to enhance the force feedback and incorporated that as well.

I have other plans for other software I use as well, such as CrewChief (https://gitlab.com/mr_belowski/CrewChiefV4) which I currently launch manually.

## Configuration

### simshm and lmubridge.exe
Uncomment SIMSHMBRIDGE_DIR and make sure the path points to a directory containing *simshm* and *lmubridge.exe* binaries.

### LMUFFB
Uncomment LMUFFB_DIR and make sure it points to a path containing *LMUFFB.exe* binary.

### Debug logging
Debug logging can be activated by uncommenting "DEBUG=true" in launch_lmu.env. This will create launch_lmu.log in the same folder as the script. 

## Invocation of script
- In Steam launch options for Le Mans Ultimate `/some/path/launch_lmu.sh %command%`
- Launch Le Mans Ultimate and have some fun

