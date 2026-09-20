% NI USB-6343 - AO1
d = daq("ni");

% Ajoute la sortie analogique AO1
addoutput(d, "Dev1", "ao1", "Voltage");

% Fréquence d'échantillonnage
fs = 100;          % 100 échantillons/s
d.Rate = fs;

% Signal carré 1 Hz pendant 10 s
T = 10;
t = (0:1/fs:T-1/fs)';

f = 1;             % 1 Hz
b = mod(floor(2*f*t), 2);   % 0/1
V = 5*b;           % 0 V / 5 V

% Envoi du signal
write(d, V);