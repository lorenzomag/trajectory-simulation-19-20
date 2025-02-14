function [v,a,distance,theta,omega,torque,torque_lat,torque_motor,power,power_loss,power_input,efficiency,slips,f_thrust_wheel,f_lat_wheel,f_x_pod,f_y_pod] = calc_main(phase,i,dt,n_wheel,n_brake,v,a,distance,theta,omega,torque,torque_lat,torque_motor,power,power_loss,power_input,efficiency,slips,f_thrust_wheel,f_lat_wheel,f_x_pod,f_y_pod,Lim_parameters,braking_force,fx_lookup_table,pl_lookup_table,ct_lookup_table,os_coefficients)
% CALC_MAIN Calculates trajectory values at each point in time.
% calc_main gets called at each iteration and handles the phases of the 
% trajectory via a passed phase input argument.
% phase = 1 -- Acceleration
% phase = 2 -- Deceleration
% phase = 3 -- Max RPM
% @author      Andreas Malekos, Rafael Anderka
    
    % Calculate slip, LIM thrust force, torque (LP torque to be changed)
    % and frequency
    switch phase
        case 1 % Acceleration
            % Find optimal slip and corresponding driving force
            slips(i) = calc_optimalSlip(v(i-1), os_coefficients);
            f_thrust_wheel(i) = calc_fx(slips(i), v(i-1), fx_lookup_table);
            
            % Calculate angular velocity and angle of Halbach wheels 
            % LP: Frequency? Phase?
            omega(i) = (slips(i)+v(i-1))/Lim_parameters.ro;
            theta(i) = theta(i-1) + omega(i) * dt;
            
            % Calculate required angular acceleration and torque 
            % LP needed at all?
            alpha = (omega(i)-omega(i-1))/dt;
            torque(i) = alpha * Lim_parameters.i;
            
            % Calculate rail heating losses LP Maybe relate this to end
            % effects and rail heating losses from LIMs
            power_loss(i) = n_wheel*calc_pl(slips(i), v(i-1), pl_lookup_table, Lim_parameters);
            
            % Calculate motor torque LP definitely no more motor torque.
            % Need to understand limits of LIMs
            %torque_motor(i) = torque(i) + f_thrust_wheel(i) * Lim_parameters.ro + power_loss(i)/n_wheel * omega(i);
            torque_motor(i) = torque(i) + f_thrust_wheel(i) * Lim_parameters.ro;
            
        case 2 % Deceleration using EmBrakes
            % Find steady state slip based on constraints from equations of motion assuming no external motor torque
            slips(i) = fzero(@(s) (s + v(i-1) + (n_wheel*calc_fx(s,v(i-1),fx_lookup_table) - n_brake*braking_force)/Lim_parameters.M*dt)/Lim_parameters.ro - omega(i-1) + calc_fx(s,v(i-1),fx_lookup_table)*Lim_parameters.ro/Lim_parameters.i*dt,[slips(i-1)-1,slips(i-1)+1]);
            
            f_thrust_wheel(i) = calc_fx(slips(i), v(i-1), fx_lookup_table);
            omega(i) = omega(i-1) - f_thrust_wheel(i) * Lim_parameters.ro / Lim_parameters.i * dt;
            theta(i) = theta(i-1) + omega(i) * dt;
            power_loss(i) = n_wheel*calc_pl(slips(i), v(i-1), pl_lookup_table, Lim_parameters);
            alpha = (omega(i)-omega(i-1))/dt;
            torque(i) = alpha * Lim_parameters.i;
            torque_motor(i) = 0;
            
        case 3 % Max RPM
            % Set omega to max. omega
            omega(i) = Lim_parameters.m_omega;
            theta(i) = theta(i-1) + omega(i) * dt;
            slips(i) = omega(i)*Lim_parameters.ro - v(i-1);
            f_thrust_wheel(i) = calc_fx(slips(i), v(i-1), fx_lookup_table);
            alpha = (omega(i)-omega(i-1))/dt;
            torque(i) = alpha * Lim_parameters.i;
            %torque_motor(i) =  torque(i) + f_thrust_wheel(i) * Lim_parameters.ro + power_loss(i)/n_wheel * omega(i);
            torque_motor(i) =  torque(i) + f_thrust_wheel(i) * Lim_parameters.ro;
            power_loss(i) = n_wheel*calc_pl(slips(i), v(i-1), pl_lookup_table, Lim_parameters);
    end
    
    % Cap motor torque
    if torque_motor(i) > Lim_parameters.m_torque
        torque_motor(i) = Lim_parameters.m_torque;
        
        % Find max. achievable slip given the torque constraint
        %slips(i) = fzero(@(slip) (Lim_parameters.i * ((v(i-1)+slip)/Lim_parameters.ro - omega(i-1))/dt + calc_fx(slip,v(i-1),fx_lookup_table)*Lim_parameters.ro + calc_pl(slip,v(i-1),pl_lookup_table,Lim_parameters) * (v(i-1)+slip)/Lim_parameters.ro - torque_motor(i)), [slips(i-1) - 1, slips(i)]);
        slips(i) = fzero(@(slip) (Lim_parameters.i * ((v(i-1)+slip)/Lim_parameters.ro - omega(i-1))/dt + calc_fx(slip,v(i-1),fx_lookup_table)*Lim_parameters.ro - torque_motor(i)), [slips(i-1) - 1, slips(i)]);

        % Recalculate dependent values
        f_thrust_wheel(i) = calc_fx(slips(i), v(i-1), fx_lookup_table);
        torque(i) = torque_motor(i) - Lim_parameters.ro*f_thrust_wheel(i);
        power_loss(i) = n_wheel*calc_pl(slips(i), v(i-1), pl_lookup_table, Lim_parameters);
        omega(i) = (slips(i)+v(i-1))/Lim_parameters.ro;
    end
    
    % Calculate total x forces
    if phase == 2
        f_x_pod(i) = f_thrust_wheel(i)*n_wheel - braking_force*n_brake;
    else
        f_x_pod(i) = f_thrust_wheel(i)*n_wheel;
    end
    
    
    % Calculate acceleration, velocity and distance
    a(i) = f_x_pod(i)/Lim_parameters.M;
    
    % Calculate trajectory
    v(i) = v(i-1) + dt*a(i);
    distance(i) = distance(i-1)+dt*v(i);
    
    % Calculate lateral torque, power and efficiency
    torque_lat(i) = Lim_parameters.ro*Lim_parameters.w*f_lat_wheel(i);
    power(i) = f_x_pod(i)*v(i); % power output = force * velocity
    power_input(i) = power(i)+power_loss(i); % ignoring inertia
    
    efficiency(i) = power(i)/power_input(i);

end
