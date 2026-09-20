load_all_folders

%% load calibration

load("D:\data_lorry\27022026\calibration27022026\data.mat")

%% INITIALIZING ALL DEVICES 
%%%%%%%%%%%%%%%%%%%%%%%%%%%

dmd = DMD('slave');
nidaq=edf_nidaq();


%% dimensions du dmd

% Constants
height_DMD = DMD.height_DMD;
width_DMD = DMD.width_DMD;

%% temporal parameters

general_params.exposure_time=5; % in ms 
readoutime=1;%ms;

% en edf "general_params.exposure_time" était le temps d'expo de la caméra,
% pendant ce temps la lentille/piezo faisait la rampe de Z
%readoutime : en edf, c'était le delais entre 2 images consécutives (au
%minimum 7.5 ms en 1024x1024

%%

%mask_to_get=sr_generate_speckle_kron(height_DMD, width_DMD,0.5,60,50);


%numbers

targeted_mask=gpt_binary_numbers(1024,50); %masks voulus au plan caméra
mask_to_get=zeros(height_DMD,width_DMD,length(targeted_mask(1,1,:))); %masks au plan dmd

for k=1:length(targeted_mask(1,1,:))
    mask_to_get(:,:,k)=(imwarp(targeted_mask(:,:,k),tform,'OutputView',imref2d(size(mask_to_get))))>0;
    %application de al transformation
end


Nillu=length(mask_to_get(1,1,:));
%nb d'illus 

%% SPECKLE ACQUISITION 


% Init the devices
dmd.stop();
dmd.remove('all');

% For the sync ; choose carefully !

dmd.default_bin_mode = 'normal';
%dmd.default_bin_mode='uninterrupted'

% le mode 'uninterrupted' peut être intéressant en slave notamment pour
% aller très vite, mais je dois me replonger dans la doc


dmd.period = general_params.exposure_time+readoutime; % (temps entre 2 paternes)
dmd.display_time = general_params.exposure_time; %  illumination_time = temps pattern affiché


dmd.set_gate(1,[1],1); % 1,[1],1 permet de copier le trigger out sur sortie 1 (inutile en slave)

%% pour tester la syncrho, une seule séquence ici, voir plus bas pour gérer plusieurs séquences

dmd.test(mask_to_get)
%rien ne passera tant que le DMD ne recoit pas de triggers

%%


nidaq.SetTRamp(dmd.display_time); 
nidaq.SetTSave(readoutime);
nidaq.SetNumberSpeckles(Nillu) 

%ça envoie au DMD un TTL 5V pendant le display time puis 0V pendant readoutime et ça boucle sur Nillu itérations.


%% start acquisition

nidaq.GenerateOutput
%genère les triggs, normalement on voit les masques sur le DMD


%% alternative pour gérer plusieurs séquences.

%seq_id = dmd.loadSequence(mask_to_get);
%mise en mémoire d'une séquence de masques, seq_ind est la référence de cette séquence dans la mémoire du dmd.

%dmd.run(seq_id);% demande d'afficher la séquence seq_id, normalement rien
%ne passe avant les triggs du nidaq

%envoie les triggs
%nidaq.GenerateOutput();



%% read me
% si message d'erreur : Error using DMD/run (line 412) Infinite
% loop active." faire :
%dmd.stop 