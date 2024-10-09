# Beamng Pacenotes

## General deployment
mods are located in `C:\Users\<you>\AppData\Local\BeamNG.drive\<version>\mods`. To make this mod, make a zip file with all these folders:
* lua
* scripts
* ui **
* settings **

`settings` is not yet needed, I think I set it up as an example of how I would provide a default keybind for the record action

`ui` may be omitted from the zip file as described below

## Required assets
The `art` folder is where recordings / pacenote data ends up. When BeamNG updates, this folder should be copied from the previous install to the new one if you wish to preserve previous pacenote recordings - `C:\Users\<you>\AppData\Local\BeamNG.drive\<version>` as it has subfolders `<level>/pacenotes` which the mod will use to playback pacenotes

## development notes
notes.lua (local uncommitted file) contains many lua ramblings and findings.
I regular reference the Beamng codebase for lua and js stuff, the `lua` and `ui` folder of the install dir is the place to search.

From the BeamNG development console, you can access the mod's object (`M` in `extension.lua`) as `extensions.scripts_sopo__pacenotes_extension`.

Ctrl+R theoretically reloads mods? - Since updating unloading and the onload function, I may be able to disable and reenable the mod with success. So far, I have just fresh start BeamNG each time I update the zip.

### UI app debugging
for debugging the ui, I don't add the ui to the zip file. Instead, I made a symlink from cmd as an admin:
```mklink /D "C:\Users\raffc\AppData\Local\BeamNG.drive\<version>\ui\modules\apps\pacenotesEditor" "L:\Github\BeamNG pacenotes mod\ui\modules\apps\pacenotesEditor"```. This will make editing and debugging easier. Note I mismatched the folder names, clearly a wise choice.
Alternatively, you can copy paste the `ui` folder into `C:\Users\<you>\AppData\Local\BeamNG.drive\<version>`.

Note the ui folder won't exist after an update, if you just want one command to copy you can just symlink the ui folder:
```mklink /D "C:\Users\raffc\AppData\Local\BeamNG.drive\<version>\ui" "L:\Github\BeamNG pacenotes mod\ui"```

Pressing Ctrl + U gives you cef debugging tools for the UI

## Pending work


When I left off in Oct 2023, I was in the middle of getting the UI to have basic functionality. Connect to mic server works though it is a blocking task, but it doesn't update the UI or anything.
A more pressing matter would be, how can I discern that an event (mission, scenario, whatever) was COMPLETED so I can save the json during recce?
TODO
* complete UI
* delete prev pace note
* rich editing experience
* make it so that if the user goes too far off the path, the pacenotes eventually pick back up
* give the beamng home path (local/BeamNG.drive/<version>) to the server, or at least the version, so it doesn't have a hard coded path

* rerecord previous note? uses the same distance, just sets the new filename
* recce-edit mode
* include length of recording with pacenote data for calculation
* include direction of car with checkpoint data for calculation

## non-functioning deployment script
To get the powershell deploy script to work, do `Set-ExecutionPolicy RemoteSigned` in a admin powershell. Then you can simply call `./deploy.ps1`. If you wish to set the permissions back, do `Set-ExecutionPolicy Default`
For some reason the mod didn't seem to work at all when running deploy, so I switched back to copying manually

You'd think the bat one would work too. I had ai write it and validate it, but it has never done anything but produce errors.
