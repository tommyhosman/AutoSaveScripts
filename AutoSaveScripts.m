function tOut = AutoSaveScripts()
% AutoSaveScripts()
% Backup unsaved scripts (including unsaved Untitled scripts) to a backup
% directory every <autoSaveRefresh_sec>. 
% 
% Typical use case is to call this function from startup.m to periodically
% save scripts in the background.
% 
% Instance backup folders are created and auto-incremented to handle multiple
% matlab instances.
% 
% If <backupOnlyUntitled> is true, only unsaved Untitled scripts are backed up
% 
% Example backup dir:
% OS path: userpath/backup/2020-12-26/MatlabInstance3/
% <backupDir>/<backupSubDirFormat>/<backupInstanceDir><number>/
% 
% 
%--------------------------------------------------------------------------
% History:
%   2020.12   Copyright Tommy Hosman, All Rights Reserved
%--------------------------------------------------------------------------


% Backup constants
autoSaveRefresh_sec   = 300;
backupDir             = fullfile(userpath,'backup'); % default MATLAB\backup
backupSubDirFormat    = 'yyyy-mm-dd';
backupInstanceDir     = 'MatlabInstance';
backupOnlyUntitled    = false;
appDataName           = 'AutoBackupDirectory';
timerName             = 'AutoBackupTimer';

debug.stopOnError     = false; % Stop (rethrow) if we encounter timer errors
debug.keyboardOnError = false; % Keyboard (pause) if we encounter timer errors
debug.verbosePrints   = false; % See local DebugPrintf()


% Delete any running timers
delete(timerfind('Name',timerName));

% Set up backup timer
t = timer('Name', timerName, ...
          'TimerFcn', @BackupUnsavedFiles, ...
          'Period', autoSaveRefresh_sec, ...
          'StartDelay', 0.01, ... % Prevents blocking on start
          'StopFcn', @CleanUp, ...
          'ErrorFcn', @CleanUp, ...
          'ExecutionMode', 'fixedRate' ...
          );

% Save backup constants to UserData
t.UserData.appDataName          = appDataName;
t.UserData.backupDir            = backupDir;
t.UserData.backupSubDirFormat   = backupSubDirFormat;
t.UserData.backupInstanceDir    = backupInstanceDir;
t.UserData.backupOnlyUntitled   = backupOnlyUntitled;
t.UserData.debug                = debug;

% Start!
start(t);

if nargout
    tOut = t;
end
end



function BackupUnsavedFiles(obj,event)
% Main timer function
% 
% Checks for unsaved editor documents
% Saves unsaved documents in backup directory

try
    % Find unsaved documents in the editor
    if matlab.desktop.editor.isEditorAvailable
        openDocuments   = matlab.desktop.editor.getAll;
        toBackupDocInds = [openDocuments.Modified];
        
        % Find modified Untitled scripts
        if obj.UserData.backupOnlyUntitled
            editorSummary   = {openDocuments.Filename}';
            untitledDocInds = ~cellfun('isempty', regexp(editorSummary, 'Untitled*'));
            toBackupDocInds = toBackupDocInds(:) & untitledDocInds(:);
        end

        % If any unsaved documents found, save them.
        if any(toBackupDocInds)
            backupLoc = GetBackupLocation(obj.UserData);
            SaveUnsaved(obj, backupLoc, openDocuments(toBackupDocInds))
        end
    end

    
catch err
    fprintf(2, 'Error during main timer loop!\nError Message: %s\n', err.message)
    if obj.UserData.debug.keyboardOnError
        fprintf('\nPost-error pausing in timer workspace... type ''dbcont'' or click the continue GUI button to keep running.\n')
        keyboard
    end
    if t.UserData.debug.stopOnError
        rethrow(err);
    end
end

end

function CleanUp(~,~)
% Any clean up activities.
% 
% Currently, just handle unclosed fid
try
    fid = GetSetTempFID();
    if ~isempty(fid)
        fclose(fid);
    end
catch err
    fprintf(2, 'Error cleaning up!\nError Message: %s\n', err.message)
end
end

function SaveUnsaved(obj, backupLoc, unsavedDocs)
% Loop through unsaved documents and save to backup location

    for ii = 1:length(unsavedDocs)
        doc = unsavedDocs(ii);
        
        % Grab the file name and ignore any subdirectories
        [unsavedSubDir, saveFilename] = fileparts( doc.Filename );
        
        % (unsaved) Untitled will have empty unsavedSubDir
        % Skip non empty unsavedSubDir
        if obj.UserData.backupOnlyUntitled
            if ~isempty(unsavedSubDir)
                continue;
            end
        end
        
        filename = fullfile(backupLoc, [saveFilename '.m']);

        %% Write the file
        DebugPrintf(obj.UserData,'Saving %s...', filename);
        
        try
            fid = fopen(filename, 'wt'); % Open file
            GetSetTempFID(fid); % Save off fid in case of error
            fwrite(fid, doc.Text); % Write
            DebugPrintf(obj.UserData,' Done!\n') % Debug print
            
        catch err
            fprintf(2,'\nError\nProblem writing file %s\n\nError: %s\n', filename, err.message);
            if obj.UserData.debug.stopOnError
                rethrow(err)
            end
        end
        
        % Close the file, but do not fail if we did not open filename
        try 
            fclose(fid);
            GetSetTempFID(); % Delete tmp fid
        catch err
            if ~strcmp(err.identifier, 'MATLAB:badfid_mx')
                rethrow(err)
            end
        end
    end

end

function backupLoc = GetBackupLocation(userData)
% Get backup location 

    % Look if it is saved in appdata
    backupLoc = getappdata(groot, userData.appDataName);
    if isempty(backupLoc)
        % Create a new backup directory if first time
        backupLoc = CreateBackupDir(userData);
        setappdata(groot, userData.appDataName, backupLoc);
    elseif ~isfolder(backupLoc)
        % Double check that it exists in case backup loc was deleted
        mkdir(backupLoc);
    end
end

function backupLoc = CreateBackupDir(userData)
% First make backup directory for today's date
% Then create backup directory for the matlab instance

% Create a backup directory for today
backupRoot = fullfile(userData.backupDir   ,datestr(now,userData.backupSubDirFormat));
if ~isfolder(backupRoot)
    mkdir(backupRoot);
end

% Create backup instance folder (for each matlab)
% Keep trying if there is a folder name conflict
backupLoc = '';
cnt = 1;
while isempty(backupLoc) && cnt < 10
    backupLoc = CreateNewInstanceDir(backupRoot, userData);
    cnt = cnt + 1;
end

if isempty(backupLoc)
    fprintf('\n\nContents of %s\n', backupRoot)
    disp(dir(backupRoot))
    error('Could not find a new instance at %s\n', backupRoot)
end

end

function backupLoc = CreateNewInstanceDir(backupLoc, userData)

instanceName = userData.backupInstanceDir;
% Now wait a random amount of time at least minWait seconds
% To prevent simultaneous matlabs from using the same instance number
minWait   = 0.01;
maxWait   = 0.15;
myStream  = RandStream('mlfg6331_64'); % This may not be right...
pauseTime = rand(myStream,1,1)*(maxWait-minWait)+minWait;
pause(pauseTime);

% Get dirs that start with instanceName
dirs = dir(fullfile(backupLoc, [instanceName '*']));
dirs = dirs([dirs.isdir]);

% Find the max instance number (so we can create max+1)
instanceDirs = regexp({dirs.name}, '\d+', 'match');
instanceDirs(cellfun(@isempty,instanceDirs)) = [];
nextInd = max(cellfun(@str2double, instanceDirs)) + 1;
if isempty(nextInd)
    nextInd = 1;
end

% Create the full path to the instance directory
backupLoc = fullfile(backupLoc,sprintf('%s%d',instanceName,nextInd));
if ~isfolder(backupLoc)
    DebugPrintf(userData,'   Creating backup directory at\n   %s\n', backupLoc)
    mkdir(backupLoc);
else
    % Folder should not already exist. Return empty to try again.
    backupLoc = '';
end

end

function DebugPrintf(userData,varargin)
% Print if verbosePrints is true
if userData.debug.verbosePrints
    fprintf(varargin{:});
end
end

function fid = GetSetTempFID(fid)
% Save the fid so we can retrieve/close it if a problem arises.
appdataName = 'tmpAutoSaveFID';

if nargin == 1
    setappdata(groot, appdataName, fid);
elseif isappdata(groot,appdataName)
    fid = getappdata(groot, appdataName);
    rmappdata(groot,appdataName);
elseif nargout == 1
    fid = [];
end

end