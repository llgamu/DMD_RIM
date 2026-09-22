%% ================================================================
%  TEST COMPLET :
%
%  ORCA light-sheet / propagative
%       H-sync
%          |
%          v
%       NI PFI0
%          |
%          v
%   ctr0 : selection / division des H-sync
%          |
%          | Ctr0InternalOutput
%          v
%   ctr1 : pulse final DMD
%          |
%          +------------------> PFI13 --> DMD Trigger In
%          |
%          +-- falling edge --> AI SampleClock
%                                  |
%                                  v
%                         AI0 <- DMD SyncOut1
%
%
% Chaque pulse effectivement envoye au DMD produit donc
% exactement UN sample analogique de SyncOut1.
%
% IMPORTANT :
% - AI declenche par Ctr1InternalOutput, PAS directement par H-sync
% - les H-sync volontairement sautes ne produisent aucun sample AI
% - acquisition AI continue : pas besoin de connaitre le nombre
%   exact de H-lines
%% ================================================================

clearvars;
clc;

load_all_folders

%% ------------------------------------------------
% PARAMETERS
%% ------------------------------------------------

% ================================================================
% CAMERA
% ================================================================

H = 1e-3;               % 1H camera
% H = 0.1e-3;           % alternative testee : 100 us


% ================================================================
% NI COUNTERS
% ================================================================

% ctr0 :
% 50 us pour H=1 ms.
% Pour H=100 us, on reduit automatiquement pour garder de la marge.
pulse_ctr0 = min(50e-6, 0.20*H);


% ctr1 :
% son front montant declenche le DMD.
% son front descendant declenchera UN sample AI.
%
% Donc pulse_DMD fixe aussi le delai entre :
%    Trigger DMD --> mesure SyncOut1
%
% Ici : mesure a 40 % de H.
sample_delay = 0.40 * H;

pulse_DMD = sample_delay;


% ================================================================
% DMD TIMINGS
%
% Valeurs validees experimentalement :
%
% H = 1 ms :
%     period  = 0.99 ms
%     display = 0.94 ms
%
% H = 0.1 ms :
%     period  = 0.099 ms
%     display = 0.094 ms
% ================================================================

dmd_period_ms  = 0.99 * H * 1e3;
dmd_display_ms = 0.94 * H * 1e3;

% SyncOut1 :
% pulse suffisamment large pour pouvoir mesurer au milieu.
%
% H=1 ms   -> 0.5 ms
% H=0.1 ms -> 0.05 ms
dmd_sync_width_ms = 0.50 * H * 1e3;


% ================================================================
% ANALOG INPUT
% ================================================================

AI_channel = 'Dev1/ai0';

% SyncOut1 apres ton diviseur donne environ 3.3 V
% On classera comme "missed" tout ce qui est sous ce seuil.
sync_threshold_V = 1.5;

% Comme ctr1 ne peut pas aller plus vite que les H-sync,
% 1/H est la frequence MAXIMALE attendue du SampleClock.
AI_max_expected_rate = 1/H;

% Taille du buffer.
% Ici suffisamment pour 300 s au debit maximal.
AI_buffer_duration_s = 300;

AI_buffer_samples = ceil( ...
    AI_max_expected_rate * AI_buffer_duration_s);


fprintf('\n===============================================\n');
fprintf('H                    = %.3f us\n',H*1e6);
fprintf('DMD period           = %.3f us\n',dmd_period_ms*1e3);
fprintf('DMD illumination     = %.3f us\n',dmd_display_ms*1e3);
fprintf('DMD SyncOut width    = %.3f us\n',dmd_sync_width_ms*1e3);
fprintf('NI DMD trigger width = %.3f us\n',pulse_DMD*1e6);
fprintf('AI sampling delay    = %.3f us\n',sample_delay*1e6);
fprintf('===============================================\n');


%% ------------------------------------------------
% DMD : sequence de test
%% ------------------------------------------------

height_DMD = DMD.height_DMD;
width_DMD  = DMD.width_DMD;

N_ON  = 500;
N_OFF = 500;

mask_to_get = false( ...
    height_DMD, ...
    width_DMD, ...
    N_ON + N_OFF);

mask_to_get(:,:,1:N_ON) = true;

Npatterns = size(mask_to_get,3);

fprintf('DMD sequence : %d patterns\n',Npatterns);

fprintf('Modulation optique attendue : %g ms ON / %g ms OFF\n',...
    N_ON*H*1e3, ...
    N_OFF*H*1e3);


%% ------------------------------------------------
% INITIALISATION DMD
%% ------------------------------------------------

fprintf('\nInitialisation du DMD en SLAVE...\n');

dmd = DMD('slave');

dmd.stop();
dmd.remove('all');

dmd.default_bin_mode = 'normal';

dmd.period       = dmd_period_ms;
dmd.display_time = dmd_display_ms;

dmd.synch_delay = 0;

% Pulse SyncOut1.
dmd.synch_pulse_width = dmd_sync_width_ms;

% Tous les evenements de synchro sur SyncOut1
dmd.set_gate(1,[1],1);

% Charge la sequence et arme le DMD en mode loop
dmd.test(mask_to_get);

fprintf('DMD arme en SLAVE.\n');


%% ------------------------------------------------
% NI-DAQmx .NET
%% ------------------------------------------------

fprintf('\nInitialisation NI-DAQmx...\n');

NET.addAssembly('NationalInstruments.DAQmx');

import NationalInstruments.DAQmx.*


%% ================================================================
% COUNTER 0
%
% PFI0 (H-sync camera)
%       |
%       v
% ctr0 retriggerable
%
% Dans cette version : division /1.
%
% La logique pourra ensuite etre modifiee pour /N.
%% ================================================================

ctr0Task = NationalInstruments.DAQmx.Task('Hsync_div1');

ctr0Task.COChannels.CreatePulseChannelTime( ...
    'Dev1/ctr0', ...
    'Hsync_div1_pulse', ...
    COPulseTimeUnits.Seconds, ...
    COPulseIdleState.Low, ...
    0, ...
    pulse_ctr0, ...
    pulse_ctr0);


ctr0Task.Triggers.StartTrigger.ConfigureDigitalEdgeTrigger( ...
    '/Dev1/PFI0', ...
    DigitalEdgeStartTriggerEdge.Rising);

ctr0Task.Triggers.StartTrigger.Retriggerable = true;


%% ================================================================
% COUNTER 1
%
% Ctr0InternalOutput
%       |
%       v
% ctr1
%       |
%       +----------> PFI13 --> DMD Trigger In
%       |
%       +----------> Ctr1InternalOutput
%                         |
%                         v
%                   AI SampleClock
%
% Rising edge  = trigger DMD
% Falling edge = acquisition SyncOut1
%% ================================================================

ctr1Task = NationalInstruments.DAQmx.Task('DMD_trigger');

ctr1Task.COChannels.CreatePulseChannelTime( ...
    'Dev1/ctr1', ...
    'DMD_trigger_pulse', ...
    COPulseTimeUnits.Seconds, ...
    COPulseIdleState.Low, ...
    0, ...
    pulse_DMD, ...
    pulse_DMD);


ctr1Task.Triggers.StartTrigger.ConfigureDigitalEdgeTrigger( ...
    '/Dev1/Ctr0InternalOutput', ...
    DigitalEdgeStartTriggerEdge.Rising);

ctr1Task.Triggers.StartTrigger.Retriggerable = true;


%% ================================================================
% ANALOG INPUT : DMD SyncOut1
%
% DMD SyncOut1 --> diviseur 5 V -> ~3.3 V --> AI0
%
% Le SampleClock est :
%
%        /Dev1/Ctr1InternalOutput
%
% et on echantillonne sur son FRONT DESCENDANT.
%
% Donc :
%
% chaque pulse ctr1
%       |
%       +--> rising  : DMD Trigger
%       |
%       +--> falling : lecture SyncOut1
%
%% ================================================================

aiTask = NationalInstruments.DAQmx.Task('DMD_SyncOut_monitor');


% AI0 reference a AIGND.
%
% Si tu cables autrement (differentiel par exemple),
% changer AITerminalConfiguration.Rse.
aiTask.AIChannels.CreateVoltageChannel( ...
    AI_channel, ...
    'DMD_SyncOut1', ...
    AITerminalConfiguration.Rse, ...
    -5.0, ...
     5.0, ...
    AIVoltageUnits.Volts);


% IMPORTANT :
%
% Ctr1InternalOutput est utilise comme HORLOGE D'ECHANTILLONNAGE,
% pas comme simple StartTrigger.
%
% Une conversion analogique a chaque falling edge de ctr1.
aiTask.Timing.ConfigureSampleClock( ...
    '/Dev1/Ctr1InternalOutput', ...
    AI_max_expected_rate, ...
    SampleClockActiveEdge.Falling, ...
    SampleQuantityMode.ContinuousSamples, ...
    int32(AI_buffer_samples));


% Reader .NET
aiReader = AnalogSingleChannelReader(aiTask.Stream);


%% ------------------------------------------------
% ARMEMENT
%% ------------------------------------------------

fprintf('\nArmement...\n');

% Ordre important :
%
% 1. DMD deja arme
% 2. AI doit attendre AVANT que ctr1 puisse produire des pulses
% 3. ctr1
% 4. ctr0
% 5. lancement camera

aiTask.Start();

ctr1Task.Start();

ctr0Task.Start();


fprintf('\n===============================================\n');
fprintf('SYSTEME ARME\n');
fprintf('===============================================\n');

fprintf('Camera H-sync : PFI0\n');
fprintf('ctr0 OUT      : PFI12\n');
fprintf('ctr1 OUT      : PFI13 --> DMD Trigger In\n');
fprintf('SyncOut1 DMD  : AI0\n');

fprintf('\n');

fprintf('AI SampleClock : falling edge Ctr1InternalOutput\n');

fprintf('1H             : %.3f us\n',H*1e6);
fprintf('AI sample delay: %.3f us apres DMD trigger\n',...
    sample_delay*1e6);

fprintf('\nLancer maintenant acquisition camera en mode propagative.\n');

fprintf('===============================================\n');


%% ------------------------------------------------
% ATTENTE
%% ------------------------------------------------

input( ...
    'Appuyer sur ENTER apres le test pour analyser SyncOut1...', ...
    's');


%% ------------------------------------------------
% ARRET DE LA GENERATION DES TRIGGERS
%% ------------------------------------------------

fprintf('\nArret des triggers...\n');

% D'abord couper la source H-sync -> ctr0.
try
    ctr0Task.Stop();
catch
end


% Laisser au dernier pulse ctr1 le temps de se terminer
% et donc au dernier falling edge de produire son sample AI.
pause(max(5*pulse_DMD,1e-3));


try
    ctr1Task.Stop();
catch
end


%% ------------------------------------------------
% LECTURE DES DONNEES AI
%% ------------------------------------------------

fprintf('\nLecture SyncOut1...\n');

try

    nAvailable = double( ...
        aiTask.Stream.AvailableSamplesPerChannel);

catch

    nAvailable = 0;

end


fprintf('Nombre de samples disponibles : %d\n',nAvailable);


if nAvailable > 0

    Vsync = aiReader.ReadMultiSample( ...
        int32(nAvailable));

    Vsync = double(Vsync);
    Vsync = Vsync(:);

else

    Vsync = [];

end


try
    aiTask.Stop();
catch
end


%% ------------------------------------------------
% ANALYSE SyncOut1
%% ------------------------------------------------

if ~isempty(Vsync)

    missed = Vsync < sync_threshold_V;

    Nsamples = numel(Vsync);

    Nmissed = sum(missed);

    missed_fraction = Nmissed / Nsamples;


    fprintf('\n===============================================\n');
    fprintf('RESULTAT TEST DMD\n');
    fprintf('===============================================\n');

    fprintf('Triggers DMD testes : %d\n',Nsamples);

    fprintf('SyncOut detectes     : %d\n',...
        Nsamples-Nmissed);

    fprintf('SyncOut manques      : %d\n',...
        Nmissed);

    fprintf('Fraction manquee     : %.6g\n',...
        missed_fraction);

    fprintf('Taux de succes       : %.9f %%\n',...
        100*(1-missed_fraction));

    fprintf('===============================================\n');


    if Nmissed > 0

        missed_indices = find(missed);

        fprintf('\nIndices des premiers evenements manques :\n');

        disp( ...
            missed_indices( ...
            1:min(20,end)));

    else

        missed_indices = [];

        fprintf('\nAucun SyncOut manque detecte.\n');

    end


    %% ------------------------------------------------------------
    % PLOT
    %% ------------------------------------------------------------

    figure;

    plot(Vsync,'.');

    hold on;

    yline(sync_threshold_V,'--');

    xlabel('Numero du trigger DMD');

    ylabel('SyncOut1 [V]');

    title(sprintf( ...
        'DMD SyncOut1 : %d missed / %d triggers', ...
        Nmissed, ...
        Nsamples));

    grid on;


else

    warning('Aucun sample analogique acquis.');

end


%% ------------------------------------------------
% NETTOYAGE
%% ------------------------------------------------

fprintf('\nNettoyage...\n');


try
    aiTask.Dispose();
catch
end

try
    ctr0Task.Dispose();
catch
end

try
    ctr1Task.Dispose();
catch
end

try
    dmd.stop();
catch
end


fprintf('Test termine.\n');