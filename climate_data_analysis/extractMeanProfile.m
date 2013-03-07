function [ prof,error_prof,min_prof,max_prof,uMap,cov_prof ] = extractMeanProfile( dataDir,dimx,lims,vMap )
%Constructs a profile structure for all the data specified in data dir

%Set default dimensions to use to levels
if ~exist('dimx','var')
    dimx = 3;
    
end

if ~exist('lims','var')
    
    lims = [-180,180;-90,90;0,1000;0,now];
end


if ~exist('varMap','var')
    %Mapping of variable names
    vMap = containers.Map();
    vMap('HNO3')='HNO3';
    vMap('H2O2')= 'H2O2';
    vMap('CO')='CO';
    vMap('CH4')='CH4';
    %vMap('HCL')='HCL';
    %vMap('HOCL')='HOCL';
    %vMap('CLONO2')= 'CLONO2';
    vMap('HBr')= 'HBR';
    vMap('HOBr')='HOBR';
    vMap('N2O')='N2O';
    %vMap('CFC')='CFC';
    vMap('Water') = 'H2O';
    vMap('SO2')='SO2';
    vMap('SO4')='SO4';
    vMap('NH3')='NH3';
    vMap('OH_vmr')='OH';
    vMap('HO2_con')='HO2';
    vMap('NO_vmr')='NO';
    vMap('NO2_vmr')='NO2';
    
end




%Mapping of unit strings to LBLRTM units
unitMap = containers.Map();
unitMap('V/V') = 'A';
unitMap('kg/kg')='C';
unitMap('molecules/cm3')='B';

%Mapping of unit conversions for consistency with LBLRTM

convMap = containers.Map();

%Convert to ppmv
convMap('V/V')=1e6;

%Convert to g/kg
convMap('kg/kg')=1e3;

convMap('molecules/cm3')=1;

%Extract stats for each of the mapped variables

allVars = keys(vMap);
prof = [];
error_prof=[];
cov_prof = [];
min_prof=[];
max_prof =[];
uMap = containers.Map();




for i=1:length(allVars)
    
    v = allVars{i};
    updateProfileWithVariable(v);
    
end

    function updateProfileWithVariable(v)
        [covar,meanval,mn,mx]=calculateCovariance(dataDir,v,dimx,lims);
        stdev = sqrt(diag(covar));
        %Use the mean for the profile, stdev for the error_profile and
        %mn and mx for the min and max profiles resp.
        
        
        unitString = extractUnitString(dataDir,v);
        
        fldName = vMap(v);
        [profVec,lblunit]= convertUnits(meanval,unitString);
        prof= setfield(prof,fldName,profVec);
        min_prof = setfield(min_prof,fldName,convertUnits(mn,unitString));
        max_prof = setfield(max_prof,fldName,convertUnits(mx,unitString));
        error_prof = setfield(error_prof,fldName,convertUnits(stdev,unitString));
        cov_prof = setfield(cov_prof,fldName,convertCov(covar,meanval,unitString));
        
        uMap(fldName)=lblunit;
        
    end

    function [conCov, lblunit] = convertCov(cov1,meanVec,unitString)
        
       [convFac, lblunit] = findConversionFactor(unitString);
       convFun = @(x,y)x*convFac;
       conCov = convertCovariance(cov1,meanVec,convFun);
        
    end

    function [convFac,lblunit] = findConversionFactor(unitString)
        
        %Search for the LBLRTM equiv. unit string
        foundUnit = '';
        replacePos = 0;
        allUnits = keys(unitMap);
        j=1;
        
        while strcmp(foundUnit,'')&&j<=length(allUnits)
            
            uStr = allUnits{j};
            res = findstr(uStr,unitString);
            if ~isempty(res)
                foundUnit = uStr;
                replacePos = res(1);
                
            end
            
            j=j+1;
            
        end
        
        convVal1Str = unitString(1:replacePos-1);
        convVal1Str = strrep(convVal1Str,'10^','1e');
        convVal1 = str2double(convVal1Str);
        convVal2 = convMap(foundUnit);
        convFac = convVal1*convVal2;
            
        lblunit = unitMap(foundUnit);
    end


    function [concVec,lblunit] = convertUnits(vec1,unitString)
        
            [convFac, lblunit] = findConversionFactor(unitString);

            concVec = vec1*convFac;

        
    end





end

