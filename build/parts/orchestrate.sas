C_IMPORT: CCF_pre.sas

%macro EasyRun(Scenario,IncubationPeriod,InitRecovered,RecoveryDays,doublingtime,Population,KnownAdmits,KnownCOVID,
                SocialDistancing,ISOChangeDate,SocialDistancingChange,ISOChangeDateTwo,SocialDistancingChangeTwo,
                MarketSharePercent,Admission_Rate,ICUPercent,VentPErcent,FatalityRate,
                plots=no,N_DAYS=365,DiagnosedRate=1.0,E=0,SIGMA=0.90,DAY_ZERO='13MAR2020'd,BETA_DECAY=0.0,
                ECMO_RATE=0.03,DIAL_RATE=0.05,HOSP_LOS=7,ICU_LOS=9,VENT_LOS=10,ECMO_LOS=6,DIAL_LOS=11);

    DATA INPUTS;
        FORMAT
            Scenario                    $200.     
            IncubationPeriod            BEST12.    
            InitRecovered               BEST12.  
            RecoveryDays                BEST12.    
            doublingtime                BEST12.    
            Population                  BEST12.    
            KnownAdmits                 BEST12.    
            KnownCOVID                  BEST12.    
            SocialDistancing            BEST12.    
            ISOChangeDate               DATE9.    
            SocialDistancingChange      BEST12.    
            ISOChangeDateTwo            DATE9.    
            SocialDistancingChangeTwo   BEST12.    
            MarketSharePercent          BEST12.    
            Admission_Rate              BEST12.    
            ICUPercent                  BEST12.    
            VentPErcent                 BEST12.    
            FatalityRate                BEST12.   
            plots                       $3.
            N_DAYS                      BEST12.
            DiagnosedRate               BEST12.
            E                           BEST12.
            SIGMA                       BEST12.
            DAY_ZERO                    DATE9.
            BETA_DECAY                  BEST12.
            ECMO_RATE                   BEST12.
            DIAL_RATE                   BEST12.
            HOSP_LOS                    BEST12.
            ICU_LOS                     BEST12.
            VENT_LOS                    BEST12.
            ECMO_LOS                    BEST12.
            DIAL_LOS                    BEST12.
        ;
        LABEL
            Scenario                    =   "Scenario Name to be stored as a character variable, combined with automatically-generated ScenarioIndex to create a unique ID"
            IncubationPeriod            =   "Number of days by which to offset hospitalization from infection, effectively shifting utilization curves to the right"
            InitRecovered               =   "Initial number of Recovered patients, assumed to have immunity to future infection"
            RecoveryDays                =   "Number of days a patient is considered infectious (the amount of time it takes to recover or die)"
            doublingtime                =   "Baseline Infection Doubling Time without social distancing"
            Population                  =   "Number of people in region of interest, assumed to be well mixed and independent of other populations"
            KnownAdmits                 =   "Number of COVID-19 patients at hospital of interest at Day 0, used to calculate the assumed number of Day 0 Infections"
            KnownCOVID                  =   "Number of known COVID-19 patients in the region at Day 0, not used in S(E)IR calculations"
            SocialDistancing            =   "Baseline Social distancing (% reduction in social contact compared to normal activity)"
            ISOChangeDate               =   "Date of first change from baseline in social distancing parameter"
            SocialDistancingChange      =   "Second value of social distancing (% reduction in social contact compared to normal activity)"
            ISOChangeDateTwo            =   "Date of second change in social distancing parameter"
            SocialDistancingChangeTwo   =   "Third value of social distancing (% reduction in social contact compared to normal activity)"
            MarketSharePercent          =   "Anticipated share (%) of hospitalized COVID-19 patients in region that will be admitted to hospital of interest"
            Admission_Rate              =   "Percentage of Infected patients in the region who will be hospitalized"
            ICUPercent                  =   "Percentage of hospitalized patients who will require ICU"
            VentPErcent                 =   "Percentage of hospitalized patients who will require Ventilators"
            FatalityRate                =   "Percentage of hospitalized patients who will die"
            plots                       =   "YES/NO display plots in output"
            N_DAYS                      =   "Number of days to project"
            DiagnosedRate               =   "Factor to adjust admission_rate contributing to via MarketSharePercent I (see calculation for I)"
            E                           =   "Initial Number of Exposed (infected but not yet infectious)"
            SIGMA                       =   "Rate of latent individuals Exposed and transported to the infectious stage during each time period"
            DAY_ZERO                    =   "Date of the first COVID-19 case"
            BETA_DECAY                  =   "Factor (%) used for daily reduction of Beta"
            ECMO_RATE                   =   "Default percent of total admissions that need ECMO"
            DIAL_RATE                   =   "Default percent of admissions that need Dialysis"
            HOSP_LOS                    =   "Average Hospital Length of Stay"
            ICU_LOS                     =   "Average ICU Length of Stay"
            VENT_LOS                    =   "Average Vent Length of Stay"
            ECMO_LOS                    =   "Average ECMO Length of Stay"
            DIAL_LOS                    =   "Average DIAL Length of Stay"
        ;
        Scenario                    =   "&Scenario.";
        IncubationPeriod            =   &IncubationPeriod.;
        InitRecovered               =   &InitRecovered.;
        RecoveryDays                =   &RecoveryDays.;
        doublingtime                =   &doublingtime.;
        Population                  =   &Population.;
        KnownAdmits                 =   &KnownAdmits.;
        KnownCOVID                  =   &KnownCOVID.;
        SocialDistancing            =   &SocialDistancing.;
        ISOChangeDate               =   &ISOChangeDate.;
        SocialDistancingChange      =   &SocialDistancingChange.;
        ISOChangeDateTwo            =   &ISOChangeDateTwo.;
        SocialDistancingChangeTwo   =   &SocialDistancingChangeTwo.;
        MarketSharePercent          =   &MarketSharePercent.;
        Admission_Rate              =   &Admission_Rate.;
        ICUPercent                  =   &ICUPercent.;
        VentPErcent                 =   &VentPErcent.;
        FatalityRate                =   &FatalityRate.;
        plots                       =   "&plots.";
        N_DAYS                      =   &N_DAYS.;
        DiagnosedRate               =   &DiagnosedRate.;
        E                           =   &E.;
        SIGMA                       =   &SIGMA.;
        DAY_ZERO                    =   &DAY_ZERO.;
        BETA_DECAY                  =   &BETA_DECAY.;
        ECMO_RATE                   =   &ECMO_RATE.;
        DIAL_RATE                   =   &DIAL_RATE.;
        HOSP_LOS                    =   &HOSP_LOS.;
        ICU_LOS                     =   &ICU_LOS.;
        VENT_LOS                    =   &VENT_LOS.;
        ECMO_LOS                    =   &ECMO_LOS.;
        DIAL_LOS                    =   &DIAL_LOS.;
    RUN;

X_IMPORT: scenario_setup.sas

P_IMPORT: model_proctmodel_seir.sas

P_IMPORT: model_proctmodel_sir.sas

X_IMPORT: model_datastep_sir.sas

P_IMPORT: model_datastep_seir.sas

X_IMPORT: model_proctmodel_seir_Ohio_I_Feed.sas

    %IF &PLOTS. = YES %THEN %DO;
        /* if multiple models for a single scenarioIndex then plot them */
        PROC SQL noprint;
            select count(*) into :scenplot from (select distinct ModelType from store.MODEL_FINAL where ScenarioIndex=&ScenarioIndex.);
        QUIT;
        %IF &scenplot > 1 %THEN %DO;
            PROC SGPLOT DATA=STORE.MODEL_FINAL;
                where ScenarioIndex=&ScenarioIndex.;
                TITLE "Daily Hospital Occupancy - All Approaches";
                TITLE2 "Scenario: &Scenario., Initial R0: %SYSFUNC(round(&R_T.,.01)) with Initial Social Distancing of %SYSEVALF(&SocialDistancing.*100)%";
                TITLE3 "Adjusted R0 after %sysfunc(INPUTN(&ISOChangeDate., date10.), date9.): %SYSFUNC(round(&R_T_Change.,.01)) with Adjusted Social Distancing of %SYSEVALF(&SocialDistancingChange.*100)%";
                TITLE4 "Adjusted R0 after %sysfunc(INPUTN(&ISOChangeDateTwo., date10.), date9.): %SYSFUNC(round(&R_T_Change_Two.,.01)) with Adjusted Social Distancing of %SYSEVALF(&SocialDistancingChangeTwo.*100)%";
                SERIES X=DATE Y=HOSPITAL_OCCUPANCY / GROUP=MODELTYPE LINEATTRS=(THICKNESS=2);
                XAXIS LABEL="Date";
                YAXIS LABEL="Daily Occupancy";
            RUN;
            TITLE; TITLE2; TITLE3; TITLE4;
        %END;	
    %END;

X_IMPORT: data_dictionary.sas

%mend;
