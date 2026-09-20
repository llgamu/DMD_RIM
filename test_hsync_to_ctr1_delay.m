function test_hsync_to_ctr1_delay()
% TEST_HSYNC_TO_CTR1_DELAY
%
% Test matériel simple :
%
%   ORCA H-sync -> PFI0
%        front montant
%            |
%            |---- 80 us ----|
%                             |
%                             +--> ctr1 OUT / PFI13 HIGH pendant 5 us
%
% Objectif :
% vérifier à l'oscilloscope que chaque front montant H-sync reçu sur PFI0
% produit une impulsion sur PFI13 exactement 80 us plus tard.
%
% IMPORTANT :
% - Le timing est entièrement matériel dans la NI USB-6343.
% - MATLAB configure et arme la tâche, mais ne chronomètre pas les pulses.
% - Pour CE TEST, le Pre-Hsync ORCA n'est pas nécessaire : on mesure
%   simplement le délai H-sync -> sortie NI.
% - Dans l'expérience finale, on activera 1 Pre-Hsync côté ORCA afin que
%   le premier trigger DMD soit émis avant la première ligne utile.
%
% Connexions oscilloscope conseillées :
%   CH1 = H-sync caméra / PFI0
%   CH2 = ctr1 OUT / PFI13
%   masse = DGND
%
% Paramètres actuels :
%   H        = 100 us
%   tau_DMD  = 20 us
%   delay_NI = H - tau_DMD = 80 us
%   pulse    = 5 us
%
% Si H ou tau_DMD changent, modifier uniquement les paramètres ci-dessous.

%% Paramètres

device      = 'Dev1';
counter     = 'ctr1';

hsyncSource = '/Dev1/PFI0';
H           = 100e-6;
tau_DMD     = 20e-6;
pulseWidth  = 5e-6;

delayNI = H - tau_DMD;

if delayNI < 0
    error(['delayNI < 0 : avec un seul Pre-Hsync, H doit être > tau_DMD. ' ...
           'Pour H plus court, il faudra utiliser plusieurs Pre-Hsync.']);
end

if delayNI + pulseWidth >= H
    error(['Le counter n''aura pas fini son pulse avant le H-sync suivant. ' ...
           'Réduire pulseWidth ou revoir le timing.']);
end

fprintf('\nTest H-sync -> ctr1/PFI13\n');
fprintf('-------------------------\n');
fprintf('H-sync input : %s\n', hsyncSource);
fprintf('Counter      : %s/%s\n', device, counter);
fprintf('Delay NI     : %.3f us\n', delayNI*1e6);
fprintf('Pulse width  : %.3f us\n\n', pulseWidth*1e6);

%% Charger NI-DAQmx .NET

NET.addAssembly('NationalInstruments.DAQmx');
import NationalInstruments.DAQmx.*

task = NationalInstruments.DAQmx.Task();

try
    ctrPhysical = sprintf('%s/%s', device, counter);

    task.COChannels.CreatePulseChannelTime( ...
        ctrPhysical, ...
        'HsyncDelayedPulse', ...
        COPulseTimeUnits.Seconds, ...
        COPulseIdleState.Low, ...
        delayNI, ...
        delayNI, ...
        pulseWidth);

    task.Triggers.StartTrigger.ConfigureDigitalEdgeTrigger( ...
        hsyncSource, ...
        DigitalEdgeStartTriggerEdge.Rising);

    task.Triggers.StartTrigger.Retriggerable = true;

    task.Control(TaskAction.Verify);
    task.Control(TaskAction.Commit);

    task.Start();

    fprintf('Tâche armée.\n');
    fprintf('Chaque front H-sync sur PFI0 doit produire un pulse sur PFI13\n');
    fprintf('80 us plus tard, de largeur 5 us.\n\n');
    fprintf('Appuyer sur ENTREE pour arrêter le test.\n');

    input('', 's');

    task.Stop();
    task.Dispose();

    fprintf('Test arrêté proprement.\n');

catch ME
    try
        task.Stop();
    catch
    end
    try
        task.Dispose();
    catch
    end
    rethrow(ME);
end

end
