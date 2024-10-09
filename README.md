# Record Your Own Pacenotes

This mod allows you to easily record your own pacenotes completely within *BeamNG.drive* (after a one-time setup), and seamlessly playback pacenotes without any additional steps.

## Key Features
- No robotic-sounding pacenotes
- No need for the map editor
- No editing text files
- Easy adjustments to existing pacenotes

## How to Play Pacenotes
1. **Install this mod** - To install it from this repo, make a zip folder with the following folders and add it to your `mods/repo` folder:
- lua
- scripts
- ui
2. Obtain or record your own pacenotes - the GitHub repo does not include any prerecorded pacenotes, but I may share zip files of prerecorded pacenotes soon here or through BeamNG forums.
3. **Start the scenario or time trial** – Pacenotes will load and play automatically.

## Tuning Playback
- **Lookahead Distance**: Determines how many meters ahead pacenotes are triggered.  
  Example: If set to 40, you’ll hear about a turn 40 meters before you reach it.
- **Speed Multiplier**: Adjusts the lookahead distance dynamically based on your speed.  
  Experiment with this to find the best balance for your driving.
- **Volume**: Controls the playback volume of pacenotes.

## How to Record Pacenotes
1. **Set up the mic server** as detailed below (required since *BeamNG.drive* can't access microphones natively).
2. **Bind the "Record Pacenote" action** to a button or key.
3. **Start a scenario** or create a new rally course using the Pacenote Editor UI.
4. **Drive the course slowly**.
5. **Press and hold to record** when you encounter a turn or hazard.
   - *Note*: The track is not editable after the first drive. Avoid backing up or crashing while recording. You can edit and record new pacenotes after finishing the course.

## How to Set Up the Mic Server
### One-time setup steps:
1. **Install Python** (if you don’t have it). You can get it from many places, but the [Microsoft App Store](https://apps.microsoft.com/detail/9nrwmjp3717k?hl=en-US&gl=US) might be the easiest option.
2. **Install the necessary modules:**
   - `pyAudio`
   - `pathlib` (this may already be included in some installations)
3. **Launch the mic server**:
   - Open **CMD** or **PowerShell**, and navigate to this repo's `server` folder.
   - Run the server with the command:
     ```bash
     python server.py
     ```
   - *Note*: If your mic isn’t connected, the server will prompt you to connect it, and you’ll need to run the command again.
4. Launch (or switch back to) *BeamNG.drive* and click **"Connect"** in the Pacenote Editor UI.

### Security Note:
Python was chosen for the server to ensure transparency. Be cautious when running programs from sources you do not trust or understand.

## Editing Pacenotes
- While in a rally, you can record a new pacenote at any point by pressing and holding the "Record Pacenote" keybind (you must be connected to the mic server).
- The **Pacenotes Editor UI** lets you:
  - View all recorded notes and see your current position on the track.
  - Click on a pacenote to edit:
    - **Name**: For convenience; does not affect playback.
    - **Distance**: Adjusts when the pacenote is triggered.
    - **Continue Distance**: Blocks playback of other notes until you are X meters away from the turn or hazard (useful for hairpins or square turns).
    - **Delete**: Marks the pacenote for deletion (playback will stop, but the deletion is not finalized until you "Save" the rally project).

---

## This Project is Still Being Improved!

Please provide feedback on how editing works for you and any features you would like to see.
