%%%%%
% Prior profile from sample data (average profile at ARM - Manus
% island site (tropical profile)

load sample_data.asc
setenv('LBL_HOME','/home/dj104/lblrtm/LBL_HOME');

% construct a profile data structure with everything in physical
% units, and a prior structure with the ln(concentration)
% individual fields - note concentrations are in ln-space
% the sample data has 40 levels, I am truncating to 30 levels to
% save time with the LBLRTM run.
firstlevel = 16;
lastlevel=40;
nlevels = lastlevel-firstlevel+1;

profile.alt = sample_data(firstlevel:lastlevel,1);  % km
profile.tdry = sample_data(firstlevel:lastlevel,2); % K
profile.pres = sample_data(firstlevel:lastlevel,3); % hPa
profile.h2o = sample_data(firstlevel:lastlevel,4);  % g/kg
profile.co2 = sample_data(firstlevel:lastlevel,5);  % rest are ppmv
profile.o3 = sample_data(firstlevel:lastlevel,6);
profile.n2o = sample_data(firstlevel:lastlevel,7);
profile.co = sample_data(firstlevel:lastlevel,8);
profile.ch4 = sample_data(firstlevel:lastlevel,9);

% construct state vector - this will be T & Q only
prior.alt = sample_data(firstlevel:lastlevel,1);
prior.tdry = sample_data(firstlevel:lastlevel,2);
prior.pressure = sample_data(firstlevel:lastlevel,3);
prior.h2o = log(sample_data(firstlevel:lastlevel,4));
prior.co2 = log(sample_data(firstlevel:lastlevel,5));
prior.o3 = log(sample_data(firstlevel:lastlevel,6));
prior.n2o = log(sample_data(firstlevel:lastlevel,7));
prior.co = log(sample_data(firstlevel:lastlevel,8));
prior.ch4 = log(sample_data(firstlevel:lastlevel,9));
prior.x0 = [prior.tdry; prior.h2o];

% other data -  the atm flag (for trace gas concentrations);
% esurf/tsurf for surface property (greybody only)
prior.stdatm_flag = 1;
prior.esurf = 1.0;
prior.Tsurf = 2.7;
prior.hbound = [prior.alt(1),prior.alt(end),0.0];

%%%%%
% Sensor noise covariance, Se
%
% Se is diagonal - this should be replaced with a better estimate
% Units must match LBLRTM (W/cm2) - this is just assuming 1 R.U. 
% NEdR (where R.U. = mW/(m2 sr cm^-1)) for all channels
% Note also that you need the correct length to match the radiance 
% vector produced by LBLRTM, which may not be known ahead of time



%%%%%
% Prior state covariance, Sa
%
% Sa is a synthetic correlated array, with some guesses as to the 
% correlation lengths and variance; units need to match prior, so
% corr length is km, temp is K, wvap is ln(q)
corr_length = 2.0;
temp_var = linspace(1,1,length(prior.alt));
temp_Sa = synthetic_Sa(prior.alt, corr_length, temp_var);

wvvar = 0.5;

wvap_var_val =(log(1.0+wvvar)).^2;

wvap_var = linspace(wvap_var_val,wvap_var_val,length(prior.alt));
wvap_Sa = synthetic_Sa(prior.alt, corr_length, wvap_var);
% Add this to prior structure
prior.S_a = blkdiag(temp_Sa, wvap_Sa);

%%%%%
% Ancillary sensor data
%
% This is the remaining metadata needed to control the LBLRTM runs;
% specifically, the FTS scanning parameters, and the wavenumber
% range

wn1=100.0;
wn2 = 300;
wnmargin = 25;
sensor_params.wavenum = [wn1-wnmargin, wn2+wnmargin];
sensor_params.FTSparams = [10.0, wn1, wn2, 0.1];

%%%%%
% First guess
%
% Forward model run at prior state, and the associated jacobian - 
% These would normally be pre-computed, but in this case I'll use
% the code itself to generate them (the if-block following is a
% clumsy MATLAB method to create it once and then reload it if it
% can find a previously written save file

cleanup_flag = true;

[wn, prior_radiance] = ...
    simple_matlab_lblrun(cleanup_flag, prior.stdatm_flag, profile, ...
                         sensor_params.wavenum, ...
                         'FTSparams', sensor_params.FTSparams, 'HBOUND',prior.hbound);
[wn, prior_K] = ...
    simple_matlab_AJ_lblrun(cleanup_flag, prior.stdatm_flag, profile, ...
                            sensor_params.wavenum, ...
                            'FTSparams', sensor_params.FTSparams, ...
                            'CalcJacobian', [0,1],'HBOUND',prior.hbound);

prior_F.Fxhat = prior_radiance;
prior_F.K = prior_K;

% assign masks - the channel_mask can be used to do limited 
% microwindowing. The state_mask is not tested for any cases other
% than full T/ln(Q) profile retrievals. (see comments in 
% simple_nonlinear_retrieval.m)
channel_mask = true(length(wn),1);

state_mask = true(nlevels*2,1);
%state_mask(nlevels+1:nlevels+2)=true(2,1);

% Now, generate an observation at a different profile; make 
% this a perturbation from the prior - a dry layer at low alt., 
% and a warm layer at high alt.
truth_profile = profile;

%truth_profile.tdry(15:21) = ...
    %truth_profile.tdry(15:21) + [1,2,3,3,3,2,1]';
    
h2oerr= 0.2;
    
truth_profile.h2o = ...
    truth_profile.h2o*(1/(1+h2oerr));
[wn, obs_radiance] = ...
    simple_matlab_lblrun(cleanup_flag, prior.stdatm_flag, truth_profile, ...
                         sensor_params.wavenum, ...
                         'FTSparams', sensor_params.FTSparams,'HBOUND',prior.hbound);

% Add simulated instrument noise - fix the rand seed so this is
% repeatable

Se = generateSE(obs_radiance,wn,1.0);
%Se = diag(ones(length(wn),1)*1e-14);

%Se for BT units
%Se = diag(ones(length(wn),1)*0.09);



wvvar = [1.0,0.9,0.8,0.7,0.6,0.5,0.4,0.3,0.2,0.1];

wvvarl =  (log(1.0+wvvar)).^2;


for w = 1:length(wvvar)
    
    wvdiag = wvvarl(w);
    wvap_var = linspace(wvdiag,wvdiag,length(prior.alt));
    wvap_Sa = synthetic_Sa(prior.alt, corr_length, wvap_var);
    % Add this to prior structure
    prior.S_a = blkdiag(temp_Sa, wvap_Sa);

    
    % run the retrieval
    [xhat_final, convergence_met, iter, xhat, G, A, K, Fxhat] = ...
        simple_nonlinear_retrieval(prior, prior_F, Se, ...
        channel_mask, state_mask, obs_radiance, ...
        sensor_params);
    
    % Recompute hatS (this is computed inside the nonlinear retrieval,
    % I'm not sure why I don't output that - easy to change that,
    % though)
    hatS = inv(K{end}'*(Se\K{end}) + inv(prior.S_a));

    save(['results_',num2str(wvvar(w)*100.0),'.mat']);
    
    
end


