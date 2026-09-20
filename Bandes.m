%% ORCA Hsync -> NI USB-6343 -> AO1 -> LED
% 1H = 1 ms  --> Hsync = 1 kHz
% 2048 lignes caméra
% motif : 10 lignes OFF / 10 lignes ON

clear;
clc;

%% -----------------------------
% Parametres utilisateur
% ------------------------------

device = "Dev1";

% Hsync camera connecte ici
hsyncTerminal = device + "/PFI0";

% Sortie analogique vers controleur LED
aoChannel = "ao1";

% ORCA Flash full frame
Nlines = 2048;

% 1H = 0.5 ms
lineInterval = 0.5*1e-3;     % s
hsyncFreq = 1 / lineInterval;   % 1000 Hz

% Motif lumineux
blockSize = 10;          % 10 lignes par etat

Voff = 0;                % LED OFF
Von  = 5;                % LED ON

%% -----------------------------
% Construction du vecteur
% -----------------------------

k = (0:Nlines-1)';

% 0000000000 1111111111 0000000000 ...
binaryPattern = mod(floor(k/blockSize), 2);

% Conversion en tension analogique
V = Voff + (Von - Voff).*binaryPattern;

%% -----------------------------
% Affichage du signal envoye
% -----------------------------

t = k * lineInterval;

figure;
plot(t, V, 'LineWidth', 1.5);

xlabel('Temps (s)');
ylabel('AO1 (V)');
title('Signal LED synchronise sur Hsync');

ylim([-0.5 5.5]);

% Affiche seulement les 200 premieres lignes
xlim([0 0.2]);

grid on;

%% -----------------------------
% Configuration NI
% -----------------------------

d = daq("ni");

% Sortie analogique
addoutput(d, device, aoChannel, "Voltage");

% Frequence attendue du clock externe
d.Rate = hsyncFreq;

% Utilisation de Hsync comme ScanClock externe
addclock(d, ...
    "ScanClock", ...
    "External", ...
    hsyncTerminal);

%% -----------------------------
% Charge les 2048 points
% -----------------------------

preload(d, V);

disp("NI armee.");
disp("Demarrer maintenant l'acquisition camera.");
disp("Chaque rising edge Hsync fera avancer AO1 d'un point.");

%% -----------------------------
% Demarrage
% -----------------------------

start(d);