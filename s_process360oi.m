%% Process 360 optical images generated by s_360CameraRig.m
% optical image --> sensor --> image processing --> RGB images -->
% stitching code

% TODO: NEEDS TO BE CLEANED UP

%% Initialize
ieInit;

workingDir = fullfile('/share/wandell/users/tlian/360Scenes/renderings','livingRoom-GoPro_2704_2028_2048_8');
dataDirectory = workingDir; %fullfile(workingDir,'OI');

outputDirectory = fullfile(workingDir,'rgb'); 
if(~exist(outputDirectory,'dir'))
    mkdir(outputDirectory);
end 

%% Get scale factor to remove vignetting

removeVignetting = 1;

% Wide-angle
if(removeVignetting)
    wideAngleWhiteFile = fullfile(workingDir,'wideAngleWhiteScene.mat');
    if(exist(wideAngleWhiteFile,'file'))
        whiteSceneOI = load(wideAngleWhiteFile);
        whiteSceneOI = whiteSceneOI.oi;
        whiteScenePhotons = oiGet(whiteSceneOI,'photons');
        % whiteLevel = oiGet(whiteSceneOI,'illuminance');
        
        % Note we're getting some weird color artifacts near the edge of the
        % white scene. I still need to debug this. But in the meantime, let's
        % just use a middle wavelength.
        nWaves = oiGet(whiteSceneOI,'nWaves');
        whiteLevel = whiteScenePhotons(:,:,round(nWaves/2));
        vignetteScale = 1./(whiteLevel./max(whiteLevel(:)));
        
        % Note: Rings are a consequence of the pupil sampling method used in PBRTv3.
        % figure; imagesc(vignetteScale); colorbar;
    else
        vignetteScale = 1;
    end
end
      
%% Loop through all images

dirInfo = dir(fullfile(dataDirectory,'cam*.mat'));
nFiles = length(dirInfo);

originAll = [];
targetAll = [];
upAll = [];
indicesAll = [];

% Read first file to determine photon scale factor


for ii = 1:nFiles
    
    clear oi;
    
    % Load current optical image
    load(fullfile(dataDirectory,dirInfo(ii).name));
    
    % --- Setup OI ---
    
    % Instead of adjusting illuminance for each image, we scale the number
    % of photons by the same factor for all images on the rig. This keeps
    % the scale across images on the rig relative. You may have to play
    % with the scale depending on the scene. 
    scale = 5e12; % This creates an mean illuminance of roughly 50 lux for cam1 for the whiteRoom
    %scale = 1e11; % for livingroom
    photons = scale.*oiGet(oi,'photons');
    oi = oiSet(oi,'photons',photons);
    
    % It's helpful at this point to check the dimensions of the OI given in the
    % window. Are they reasonable? If not, it's possible the focal length,
    % aperture diameter, and FOV were not set correctly when saving the OI.
   
    % --- Setup sensor ---
    
    sensor = sensorCreate();
    
    % Set the pixel size
    % Sensor size will be the same as the size of the optical image. 
    %sensorPixelSize = 5.5 *10^-6; % From Grasshopper
    sensorPixelSize = oiGet(oi,'sample spacing','m');
    oiHeight = oiGet(oi,'height');
    oiWidth = oiGet(oi,'width');
    sensorSize = round([oiHeight oiWidth]./sensorPixelSize);
    sensor = sensorSet(sensor,'size',sensorSize);
    sensor = sensorSet(sensor,'pixel size same fill factor',sensorPixelSize);
    
    % Set exposure time
    sensor = sensorSet(sensor,'exp time',1/600); % in seconds (for whiteRoom)
    %sensor = sensorSet(sensor,'exp time',1/1000); % in seconds (for livingRoom)
    %sensor = sensorSet(sensor,'auto Exposure',true);

    % Compute!
    sensor = sensorCompute(sensor,oi);
    
    % Check exposure
    exposureTime = sensorGet(sensor,'exp time');
    fprintf('Exposure Time is 1/%0.2f s \n',1/exposureTime);
    
%     vcAddObject(sensor); 
%     sensorWindow;

    % --- Setup Image Processing ---
    ip = ipCreate;
    ip = ipSet(ip,'demosaic method','bilinear');
    ip = ipSet(ip,'correction method illuminant','gray world');
    
    % Compute!
    ip = ipCompute(ip,sensor);
    
    if(removeVignetting)
        % Scale according to the white image (remove vignetting)
        % Is there anything built in to ISET to do this?
        if(strcmp(dirInfo(ii).name,'cam0.dat') || ...
                strcmp(dirInfo(ii).name,'cam15.dat') || ...
                strcmp(dirInfo(ii).name,'cam16.dat'))
            % Fish eye lens
        else
            % Wide-angle
            ip.data.result = ip.data.result.*vignetteScale;
        end
    end
    
    vcAddObject(ip);
    ipWindow;
    
    % --- Save Images ---
    
    % Flip the indexing. The cameras should run clockwise, but from PBRT
    % they run counter clockwise. I think this is due to some coordinate
    % axes flips.
    
%     allIndices = [0 circshift(14:-1:1,1) 15 16];
%     expression = '(\d+)';
%     matchStr = regexp(dirInfo(ii).name,expression,'match');
%     currIndex = str2double(cell2mat(matchStr));
%     newIndex = allIndices(currIndex+1);
    
    expression = '(\d+)';
    matchStr = regexp(dirInfo(ii).name,expression,'match');
    currIndex = str2double(cell2mat(matchStr));
    newIndex = currIndex;
    
    % Save the images according to the Surround360 format
    ip = ipSet(pi,'gamma',3.0);
    srgb = ipGet(ip,'data srgb');
    
    % Crop the image
%     [M,N,C] = size(srgb);
%     center = round([M/2,N/2]);
%     removeX = 30;
%     removeY = round(removeX*(M/N));
%     srgb = srgb(removeY:(2*center(1)-removeY),removeX:(2*center(2)-removeX),:);
    
    imageDir = fullfile(outputDirectory,sprintf('cam%d',newIndex));
    if(~exist(imageDir,'dir'))
        mkdir(imageDir);
    end
    imwrite(srgb,fullfile(piRootPath,'local','000000.png'))
    
    
    % We will save the origins/targets etc. according to the new index.
    % This is helpful when we try to match up with the camera_rig.json
    % file.
    %{
    originAll = [originAll; origin];
    targetAll = [targetAll; target];
    upAll = [upAll; up];  
    indicesAll = [indicesAll; newIndex];
    %}
end

