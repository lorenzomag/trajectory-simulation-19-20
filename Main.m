%% Pod Trajectory Simulation, HypED 2018/19
% This script calculates the trajectory of the pod inside the tube by
% calculating the force from the Halbach wheel propulsion module. A linear 
% increase/decrease in RPM is assumed (capped by a given maximum angular
% acceleration), and the rpm cannot exceed the max RPM given by the motor 
% specifications. Inertia in power input has been ignored when in efficiency
% calculation.
%
% NOTE ABOUT TIME STEP (dt):
% For quick estimates a time step of ~0.1s is sufficient. 
% For more accurate results use a time step of 0.05s or smaller.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Lines containing "LP" are to be removed or changed
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


clear; clc;

%% Parameters
% Script mode
useMaxAccDistance = false;          
maxAccDistance = 1000;

% Import parameters from './Parameters/HalbachWheel_parameters.xlsx'
Lim_parameters = importLimParameters();

% Import lookup tables and optimal slip coefficients
fx_lookup_table = load('Parameters/forceLookupTable.mat');              % Thrust force lookup table (net values for a wheel pair)
pl_lookup_table = load('Parameters/powerLossLookupTable.mat');          % Power loss lookup table (net values for a wheel pair)
ct_lookup_table = load('Parameters/coggingTorqueLookupTable.mat');      % Interaction torque lookup table (values for a single wheel) LP
os_coefficients = load('Parameters/optimalSlipCoefficients.mat');       % Optimal slip coefficients

% Setup parameters
dt = 1/100;                                                 % Time step (see note above)
tmax = 120;                                                 % Maximum allowed duration of run
n_Lim = 2;                                                  % Number of Lims
n_brake = 2;                                                % Number of brakes
cof = 0.38;                                                 % Coefficient of kinetic friction of the brake pads
spring_compression = 30;                                    % Spring compression in [mm] when wedge is pressing against rail
spring_coefficient = 20.6;                                  % Spring coefficient in [N/mm]
actuation_force = spring_compression * spring_coefficient;  % Spring actuation force
braking_force = actuation_force * cof / (tan(0.52) - cof);  % Force from a single brake pad
deceleration_total = n_brake * braking_force / Lim_parameters.M; % Braking deceleration from all brakes
stripe_dist = 100 / 3.281;                                  % Distance between stripes
number_of_stripes = floor(Lim_parameters.l / stripe_dist); % Total number of stripes we will detect

%% Initialize arrays
%  Create all necessary arrays and initialize with 0s for each time step. 
%  This is computationally faster than extending the arrays after each calculation.
time = 0:dt:tmax;                       % Create time array with time step dt and maximum time tmax
v = zeros(1,length(time));              % Velocity of pod
a = zeros(1,length(time));              % Acceleration of pod
distance = zeros(1,length(time));       % Distance travelled
theta = zeros(1,length(time));          % Current phase of Lim fields
omega = zeros(1,length(time));          % Lim frequency
torque = zeros(1,length(time));         % Net torque on Halbach wheels LP (What is this for?)
torque_lat = zeros(1,length(time));     % Torque on Halbach wheels from lateral forces LP (What is this for?)
torque_motor = zeros(1,length(time));   % Supplied torque from motor LP (What is this for?)
power = zeros(1,length(time));          % Power
power_loss = zeros(1,length(time));     % Power loss
power_input = zeros(1,length(time));    % Power input
efficiency = zeros(1,length(time));     % Power output / Power input
slips = zeros(1,length(time));          % Absolute slip between Halbach wheels and track
f_thrust_wheel = zeros(1,length(time)); % Thrust force from a single Halbach wheel
f_lat_wheel = zeros(1,length(time));    % Lateral force from a single Halbach wheel   
f_x_pod = zeros(1,length(time));        % Net force in direction of track (x) for whole pod
f_y_pod = zeros(1,length(time));        % Net force in lateral direction (y) for whole pod
stripes = zeros(1,number_of_stripes);   % Indices at which we detect each stripe

%% Calculation loop
%  This is the main loop of the script, caluclating the relevant values for
%  each point in time. The function calc_main gets called at each iteration 
%  and handles the phases of the trajectory internally by passing a "phase"
%  variable as the first input argument.
%  phase = 1 -- Acceleration
%  phase = 2 -- Deceleration
%  phase = 3 -- Max RPM

phase = 1;          % We start in the acceleration phase
stripe_count = 0;   % Initially we have counted 0 stripes

% For each point in time ...
for i = 2:length(time) % Start at i = 2 because values are all init at 1
    %% Phase transitions
    % If we have exceeded the max. RPM we cap the RPM and recalculate
    if (omega(i-1) * 60 / (2 * pi)) > Lim_parameters.m_rpm
        phase = 3; % Max RPM
        
        % Recalculate previous time = i - 1 to avoid briefly surpassing max RPM
        [v,a,distance,theta,omega,torque,torque_lat,torque_motor,power,power_loss,power_input,efficiency,slips,f_thrust_wheel,f_lat_wheel,f_x_pod,f_y_pod] = ...
        calc_main(phase, i - 1, dt, n_Lim, n_brake, v, a, distance, theta, omega, torque, torque_lat, torque_motor, power, power_loss, power_input, efficiency, slips, ...
                  f_thrust_wheel, f_lat_wheel, f_x_pod, f_y_pod, Lim_parameters, braking_force, fx_lookup_table, pl_lookup_table, ct_lookup_table, os_coefficients);
    end
    
    % If we have reached the maximum allowed acceleration distance we 
    % transition to deceleration
    if (useMaxAccDistance)
        if distance(i-1) >= (maxAccDistance)
            phase = 2; % Deceleration
        end
    else
        % Calculate our 'worst case' braking distance assuming a 100% energy transfer from wheels into translational kinetic energy
        % LP Determine stored energy in Lims that would be translated intro
        %  translational kinetic energy
        kinetic_energy = 0.5 * Lim_parameters.M * v(i-1)^2;
        rotational_kinetic_energy = n_Lim * 0.5 * Lim_parameters.i * omega(i-1)^2;
        total_kinetic_energy = kinetic_energy + rotational_kinetic_energy;
        e_tot = kinetic_energy + rotational_kinetic_energy;
        braking_dist = (e_tot / Lim_parameters.M) / (deceleration_total);
        if distance(i-1) >= (Lim_parameters.l - braking_dist)
            phase = 2; % Deceleration
        end
    end
    
    %% Main calculation
    % Calculate for current time = i
    [v,a,distance,theta,omega,torque,torque_lat,torque_motor,power,power_loss,power_input,efficiency,slips,f_thrust_wheel,f_lat_wheel,f_x_pod,f_y_pod] = ...
    calc_main(phase, i, dt, n_Lim, n_brake, v, a, distance, theta, omega, torque, torque_lat, torque_motor, power, power_loss, power_input, efficiency, slips, ...
              f_thrust_wheel, f_lat_wheel, f_x_pod, f_y_pod, Lim_parameters, braking_force, fx_lookup_table, pl_lookup_table, ct_lookup_table, os_coefficients);
    
    fprintf("Step: %i, %.2f s, %.2f m, %.2f m/s, %4.0f RPM, %.2f Nm, %.2f m/s, Phase: %i\n", i, time(i), distance(i), v(i), omega(i) * 60 / (2 * pi), torque_motor(i), slips(i), phase)
    
    %% Stripes
    if (distance(i) >= (1 + stripe_count) * stripe_dist)
        stripes(1 + stripe_count) = i;
        stripe_count = stripe_count + 1;
    end
    
    %% Exit conditions
    % Stop when speed is 0m/s or time is up
    if v(i) <= 0 || i == length(time)
        % Truncate arrays and create final result structure 
        result = finalizeResults(i, time, distance, v, a, theta, omega * 60 / (2 * pi), torque, torque_lat, torque_motor, f_thrust_wheel, f_lat_wheel,...
                                 f_x_pod, f_y_pod, power, power_loss, power_input, efficiency, slips);
        % Break from loop
        break;
    end
end

%% Print some results LP Change at the end
% Find max. speed and x force
v_max = max(result.velocity);
v_max_time = find(result.velocity == v_max) * dt - dt;
max_frequency = max(result.rpm);
f_x_max = max(result.pod_x);
f_x_min = min(result.pod_x);
torque_max = max(result.torque);
torque_motor_max = max(result.torque_motor);
torque_lat_max = max(result.torque_lat);
% Let's display some stuff for quick viewing
fprintf('\n--------------------RESULTS--------------------\n');
fprintf('\nDuration of run: %.2f s\n', time(i));
fprintf('\nDistance: %.2f m\n', distance(i));
fprintf('\nMaximum speed: %.2f m/s at %.2f s\n', v_max(1), v_max_time(1));
fprintf('\nMaximum RPM: %5.0f\n', max_frequency);
fprintf('\nMaximum net thrust force per wheel: %.2f N\n', f_x_max/n_Lim);
fprintf('\nMaximum net lateral force per wheel: %.2f N\n', max(f_y_pod)/n_Lim);
fprintf('\nMaximum thrust torque: %.2f Nm\n', torque_max);
fprintf('\nMaximum motor torque: %.2f Nm\n', torque_motor_max);
fprintf('\nMaximum lateral torque: %.2f Nm\n', torque_lat_max);
fprintf('\nPower per motor: %.2f W\n', max(power_input)/n_Lim);

%% Plot the trajectory graphs
% plotTrajectory(result);