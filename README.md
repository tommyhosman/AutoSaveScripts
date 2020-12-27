# AutoSaveScripts

Matlab function to periodically save modified scripts (including unsaved `Untitled` scripts) to a backup directory (organized by date and Matlab instance).

## Need

Matlab may close before there is an opportunity to save modified functions/scripts (e.g. `Untitled` scripts).

This script's main purpose is to handle backing up unsaved `Untitled` scripts because Matlab does not currently have a method to do this.

## Code header

Backup unsaved scripts (including unsaved `Untitled` scripts) to a backup directory every `autoSaveRefresh_sec`.

Backup instance folders are created and auto-incremented to handle multiple opened matlabs.

### Backup directory location

Example backup directory (with defaults):

Example OS path: `userpath`/backup/2020-12-26/MatlabInstance3/

Example path using param names: `backupDir`/`backupSubDirFormat`/`backupInstanceDir` `number`/

### Debug / Params

Params:

- `autoSaveRefresh_sec` [default `500`] Refresh time in seconds.
- `backupOnlyUntitled` [default `false`] If true, _only_ unsaved `Untitled` scripts are backed up. Otherwise, all unsaved files are backed up.

Debug flags:

- `debug.stopOnError` [default `false`] Stop (rethrow) if timer errors are encountered.
- `debug.keyboardOnError` [default `false`] Pause if timer errors are encountered (if true, will pause before the rethrowing the error).
- `debug.verbosePrints` [default `false`] Prints when creating the backup dir and saving backup scripts, see local function `DebugPrintf`.

## Testing

Testing on MATLAB 2019b, Windows OS

- All paths should be OS agnostic.
- Uses `matlab.desktop.editor` commands to access the editor which may be MATLAB version dependent.
