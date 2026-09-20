%% ================================================================
%  TEST COMPLET :
%
%  ORCA light-sheet / propagative
%       H-sync = 1 ms
%          |
%          v
%       NI PFI0
%          |
%          v
%   ctr0 : un pulse par H-sync  (/1)
%          |
%          | Ctr0InternalOutput
%          v
%   ctr1 : pulse final DMD
%          |
%          v
%       PFI13
%          |
%          v
%      DMD slave
%
%  IMPORTANT :
%  - pas de pre-Hsync
%  - pas de compensation tau_DMD
%  - pas de delay volontaire
%  - DMD en BIN_NORMAL, comme dans test_dmd_slave.m qui fonctionne
%% ================================================================

clearvars;
clc;

load_all_folders

%% ------------------------------------------------
% PARAMETERS
%% ------------------------------------------------

H = 1e-3;               % 1H camera = 1 ms

% Pulses NI.
% Ils sont volontairement assez longs pour ce premier test.
pulse_ctr0 = 50e-6;     % 50 us
pulse_DMD  = 100e-6;    % 100 us

% DMD timings, en ms dans la classe DMD
dmd_period_ms  = 1.000; % = 1H
dmd_display_ms = 0.950; % 950 us affichage + ~50 us marge

%% ------------------------------------------------
% DMD : sequence de test
%% ------------------------------------------------

height_DMD = DMD.height_DMD;
width_DMD  = DMD.width_DMD;

% 20 patterns :
% 10 ALL ON suivis de 10 ALL OFF
%
% Avec H = 1 ms :
%     10 ms ON
%     10 ms OFF
%
% Très facile à identifier sur photodiode / caméra.

N_ON  = 500;
N_OFF = 500;


%On crée une seule période : le DMD sera utilisé en mode loop.
mask_to_get = false(height_DMD, width_DMD, N_ON + N_OFF);

mask_to_get(:,:,1:N_ON) = true; 

% Les N_OFF suivants restent false.

Npatterns = size(mask_to_get,3);

fprintf('DMD sequence : %d patterns\n',Npatterns);
fprintf('Modulation optique attendue : %g ms ON / %g ms OFF\n',...
    N_ON*H*1e3, N_OFF*H*1e3);


%% ------------------------------------------------
% INITIALISATION DMD
%% ------------------------------------------------

fprintf('\nInitialisation du DMD en SLAVE...\n');

dmd = DMD('slave');

dmd.stop();
dmd.remove('all');

% IMPORTANT :
% on garde exactement le mode qui marche dans test_dmd_slave.m

dmd.default_bin_mode = 'normal';

dmd.period       = dmd_period_ms;
dmd.display_time = dmd_display_ms;

dmd.synch_delay = 0;

% SyncOut suffisamment court pour être compatible avec H = 1 ms.
% On pourra modifier cette valeur ensuite pour étudier la fenêtre
% d'illumination réelle.
dmd.synch_pulse_width = 0.5;   % ms

% Laisse passer tous les événements de synchro sur SyncOut1
dmd.set_gate(1,[1],1);

% Charge la sequence + run('loop')
%
% En SLAVE :
% rien ne doit avancer tant qu'il n'y a pas de trigger externe.

dmd.test(mask_to_get); % charge la séquence et arme le display en mode 'loop'

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
% Ici : division /1
%
% Chaque rising edge H-sync genere un pulse.
%
% Physiquement :
% ctr0 OUT = PFI12
%
% On peut donc regarder PFI12 a l'oscilloscope.
%% ================================================================

ctr0Task = NationalInstruments.DAQmx.Task('Hsync_div1');

ctr0Task.COChannels.CreatePulseChannelTime( ...
    'Dev1/ctr0', ...                    % counter physique utilise : compteur 0 de Dev1
    'Hsync_div1_pulse', ...             % nom logique donne au channel compteur
    COPulseTimeUnits.Seconds, ...        % unite utilisee pour les temps ci-dessous
    COPulseIdleState.Low, ...            % niveau de sortie quand le compteur est inactif : LOW
    0, ...                               % initialDelay : delai entre le trigger et le debut du pulse
    pulse_ctr0, ...                      % lowTime : duree de l'etat LOW entre deux pulses
    pulse_ctr0);                         % highTime : duree de l'etat HIGH du pulse


ctr0Task.Triggers.StartTrigger.ConfigureDigitalEdgeTrigger( ...
    '/Dev1/PFI0', ...                    % source du trigger : H-sync camera connecte sur PFI0
    DigitalEdgeStartTriggerEdge.Rising); % declenchement sur front montant du H-sync

% Un nouveau pulse a chaque H-sync
ctr0Task.Triggers.StartTrigger.Retriggerable = true;


%% ================================================================
% COUNTER 1
%
% Ctr0InternalOutput
%       |
%       v
% ctr1 retriggerable
%       |
%       v
% PFI13 --> DMD Trigger In
%
% Aucun delay volontaire.
%% ================================================================

ctr1Task = NationalInstruments.DAQmx.Task('DMD_trigger');

ctr1Task.COChannels.CreatePulseChannelTime( ...
    'Dev1/ctr1', ...                    % counter physique utilise : compteur 1
    'DMD_trigger_pulse', ...            % nom logique du channel
    COPulseTimeUnits.Seconds, ...        % temps exprimes en secondes
    COPulseIdleState.Low, ...            % sortie LOW quand inactive
    0, ...                               % initialDelay : ici aucun delai volontaire
    pulse_DMD, ...                       % lowTime
    pulse_DMD);                          % highTime : largeur du trigger envoye au DMD


ctr1Task.Triggers.StartTrigger.ConfigureDigitalEdgeTrigger( ...
    '/Dev1/Ctr0InternalOutput', ...       % ctr1 est declenche par la sortie interne de ctr0
    DigitalEdgeStartTriggerEdge.Rising); % sur le front montant de ctr0


ctr1Task.Triggers.StartTrigger.Retriggerable = true;


%% ------------------------------------------------
% ARMEMENT
%% ------------------------------------------------

fprintf('\nArmement des compteurs...\n');

% IMPORTANT :
% armer d'abord l'etage aval.
%
% DMD est deja arme.
% Puis ctr1.
% Puis ctr0.
% Puis seulement on lance la camera.

ctr1Task.Start();
ctr0Task.Start();

fprintf('\n===============================================\n');
fprintf('SYSTEME ARME\n');
fprintf('===============================================\n');
fprintf('Camera H-sync : PFI0\n');
fprintf('ctr0 OUT      : PFI12  (controle oscilloscope)\n');
fprintf('ctr1 OUT      : PFI13  --> DMD Trigger In\n');
fprintf('\n');
fprintf('Lancer maintenant acquisition camera en mode propagative.\n');
fprintf('1H = %.3f ms\n',H*1e3);
fprintf('===============================================\n');


%% ------------------------------------------------
% ATTENTE
%% ------------------------------------------------

input('Appuyer sur ENTER apres le test pour tout arreter...','s');


%% ------------------------------------------------
% STOP
%% ------------------------------------------------

fprintf('\nArret...\n');

try
    ctr0Task.Stop();
catch
end

try
    ctr1Task.Stop();
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