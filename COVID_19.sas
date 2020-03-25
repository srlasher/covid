/*SAS program COVID_19*/

%macro EasyRun(Scenario,IncubationPeriod,InitRecovered,RecoveryDays,doublingtime,Population,KnownAdmits,KnownCOVID,SocialDistancing,MarketSharePercent,Admission_Rate,ICUPercent,VentPErcent,plots=no);

/* Translate CCF code macro (%EASYRUN) inputs to variables used in this code 
	these variables come in from the macro call above
	this section show the name mapping to how they are used in this code
*/
/*%LET scenario=BASE_Scenario_one;*/
/*%LET IncubationPeriod=0;*/ /* not yet used */
/*%LET InitRecovered=0;*/ /* R */
/*%LET RecoveryDays=14;*/ /* RECOVERY_DAYS */
/*%LET doublingtime=5;*/ /* DOUBLING_TIME */
/*%LET KnownAdmits=10;*/ /* KNOWN_CASES */
/*%LET KnownCOVID=46;*/ /* KNOWN_INFECTIONS */
/*%LET Population=4390484;*/ /* S_DEFAULT */
/*%LET SocialDistancing=0.0;*/ /* RELATIVE_CONTACT_RATE */
/*%LET MarketSharePercent=0.29;*/ /* MARKET_SHARE */
/*%LET Admission_Rate=0.075;*/ /* same name below */
/*%LET ICUPercent=0.25;*/ /* used in ICU_RATE */
/*%LET VentPErcent=0.125;*/ /* used in VENT_RATE */


/* Dynamic Variables across Scenario Runs */
%LET S_DEFAULT = &Population.;
%LET KNOWN_INFECTIONS = &KnownCOVID.;
%LET KNOWN_CASES = &KnownAdmits.;
/*Doubling time before social distancing (days)*/
%LET DOUBLING_TIME = &doublingtime.;
/*Initial Number of Exposed (infected but not yet infectious)*/
%LET E = 0;
/*Initial Number of Recovered*/
%LET R = &InitRecovered.;
%LET RECOVERY_DAYS = &RecoveryDays.;
/*Social distancing (% reduction in social contact)*/
%LET RELATIVE_CONTACT_RATE = &SocialDistancing.;
/*Hospital Market Share (%)*/
%LET MARKET_SHARE = &MarketSharePercent.;
%LET ADMISSION_RATE= &Admission_Rate.;
/*factor to adjust %admission to make sense multiplied by Total I*/
%LET DIAGNOSED_RATE=1.0; 
/*ICU %(total infections)*/
%LET ICU_RATE = %SYSEVALF(&ICUPercent.*&DIAGNOSED_RATE);
/*Ventilated %(total infections)*/
%LET VENT_RATE = %SYSEVALF(&VentPErcent.*&DIAGNOSED_RATE);
/*Average number of days from infection to hospitalization*/
%LET DAYS_TO_HOSP = 0;


/*Parameters assumed to be constant across scenarios*/
/*Currently Hospitalized COVID-19 Patients*/
%LET CURRENT_HOSP = &KNOWN_CASES;
/*Hospitalization %(total infections)*/
%LET HOSP_RATE = %SYSEVALF(&ADMISSION_RATE*&DIAGNOSED_RATE);
/*Hospital Length of Stay*/
%LET HOSP_LOS = 7;
/*ICU Length of Stay*/
%LET ICU_LOS = 9;
/*Vent Length of Stay*/
%LET VENT_LOS = 10;
/*default percent of total admissions that need ECMO*/
%LET ECMO_RATE=0.03; 
%LET ECMO_LOS=6;
/*default percent of admissions that need Dialysis*/
%LET DIAL_RATE=0.05;
%LET DIAL_LOS=11;
%LET DEATH_RATE=0.00;
/*rate of latent individuals Exposed transported to the infectious stage each time period*/
%LET SIGMA = 0.90;
/*Days to project*/
%LET N_DAYS = 365;
%LET BETA_DECAY = 0.0;
/*Date of first COVID-19 Case*/
%LET DAY_ZERO = 13MAR2020;


/*Parameters derived from other inputs*/
/*Regional Population*/
%LET S = &S_DEFAULT;
/*Currently Known Regional Infections (only used to compute detection rate - does not change projections*/
%LET INITIAL_INFECTIONS = &KNOWN_INFECTIONS;
%LET TOTAL_INFECTIONS = %SYSEVALF(&CURRENT_HOSP / &MARKET_SHARE / &HOSP_RATE);
%LET DETECTION_PROB = %SYSEVALF(&INITIAL_INFECTIONS / &TOTAL_INFECTIONS);
%LET I = %SYSEVALF(&INITIAL_INFECTIONS / &DETECTION_PROB);
%LET INTRINSIC_GROWTH_RATE = %SYSEVALF(2 ** (1 / &DOUBLING_TIME) - 1);
%LET GAMMA = %SYSEVALF(1/&RECOVERY_DAYS);
%LET BETA = %SYSEVALF((&INTRINSIC_GROWTH_RATE + &GAMMA) / &S * (1-&RELATIVE_CONTACT_RATE));
/*R_T is R_0 after distancing*/
%LET R_T = %SYSEVALF(&BETA / &GAMMA * &S);
%LET R_NAUGHT = %SYSEVALF(&R_T / (1-&RELATIVE_CONTACT_RATE));
/*doubling time after distancing*/
%LET DOUBLING_TIME_T = %SYSEVALF(1/%SYSFUNC(LOG2(&BETA*&S - &GAMMA + 1)));


/*DATA FOR PROC TMODEL APPROACHES*/
DATA DINIT(Label="Initial Conditions of Simulation"); 
	S_N = &S. - (&I/&DIAGNOSED_RATE) - &R;
	E_N = &E;
	I_N = &I/&DIAGNOSED_RATE;
	R_N = &R;
	R0=&R_NAUGHT;
	DO TIME = 0 TO &N_DAYS; 
		OUTPUT; 
	END; 
RUN;

/* create an index, ScenarioIndex for this run by incrementing the max value of ScenarioIndex in SCENARIOS dataset */
%IF %SYSFUNC(exist(work.scenarios)) %THEN %DO;
	PROC SQL noprint; select max(ScenarioIndex) into :ScenarioIndex_Base from work.scenarios; quit;
%END;
%ELSE %DO; %LET ScenarioIndex_Base = 0; %END;
/* store all the macro variables that set up this scenario in PARMS dataset */
DATA PARMS;
	set sashelp.vmacro(where=(scope='EASYRUN'));
	if name in ('SQLEXITCODE','SQLOBS','SQLOOPS','SQLRC','SQLXOBS','SQLXOPENERRS') then delete;
	ScenarioIndex = &ScenarioIndex_Base. + 1;
RUN;

/* Check to see if PARMS (this scenario) has already been run before in SCENARIOS dataset */
%IF %SYSFUNC(exist(work.scenarios)) %THEN %DO;
	PROC SQL noprint;
		/* has this scenario been run before - all the same parameters and value - no more and no less */
		select count(*) into :ScenarioExist from
			(select t1.ScenarioIndex, t2.ScenarioIndex
				from 
					(select *, count(*) as cnt 
						from PARMS
						where name not in ('SCENARIO','SCENARIOINDEX_BASE','SCENARIOINDEX')
						group by ScenarioIndex) t1
					join
					(select * from SCENARIOS
						where name not in ('SCENARIO','SCENARIOINDEX_BASE','SCENARIOINDEX')) t2
					on t1.name=t2.name and t1.value=t2.value
				group by t1.ScenarioIndex, t2.ScenarioIndex, t1.cnt
				having count(*) = t1.cnt)
		; 
	QUIT;
%END; 
%ELSE %DO; 
	%LET ScenarioExist = 0;
%END;

/* If this is a new scenario then run it and append results to MODEL_FINAL dataset and scenario (PARMS) to the SCENARIO dataset */
%IF &ScenarioExist = 0 %THEN %DO;
	PROC SQL noprint; select max(ScenarioIndex) into :ScenarioIndex from work.parms; QUIT;

	/*PROC TMODEL SEIR APPROACH*/
		PROC TMODEL DATA = DINIT NOPRINT;
			/* PARAMETER SETTINGS */ 
			PARMS N &S. R0 &R_NAUGHT. ; 
			GAMMA = &GAMMA.;
			SIGMA = &SIGMA;
			BETA = R0*GAMMA/N;
			/* DIFFERENTIAL EQUATIONS */ 
			/* a. Decrease in healthy susceptible persons through infections: number of encounters of (S,I)*TransmissionProb*/
			DERT.S_N = -BETA*S_N*I_N;
			/* b. inflow from a. -Decrease in Exposed: alpha*e "promotion" inflow from E->I;*/
			DERT.E_N = BETA*S_N*I_N-SIGMA*E_N;
			/* c. inflow from b. - outflow through recovery or death during illness*/
			DERT.I_N = SIGMA*E_N-GAMMA*I_N;
			/* d. Recovered and death humans through "promotion" inflow from c.*/
			DERT.R_N = GAMMA*I_N;           
			/* SOLVE THE EQUATIONS */ 
			SOLVE S_N E_N I_N R_N / OUT = TMODEL_SEIR; 
		RUN;
		QUIT;

		DATA TMODEL_SEIR;
			FORMAT ModelType $30. Scenarioname $30. DATE ADMIT_DATE DATE9.;
			ModelType="TMODEL - SEIR";
			ScenarioName="&Scenario";
			ScenarioIndex=&ScenarioIndex.;
			LABEL HOSPITAL_OCCUPANCY="Hospital Occupancy" ICU_OCCUPANCY="ICU Occupancy" VENT_OCCUPANCY="Ventilator Utilization"
				ECMO_OCCUPANCY="ECMO Utilization" DIAL_OCCUPANCY="Dialysis Utilization";
			LENGTH METHOD $15.;
			RETAIN LAG_S LAG_I LAG_R LAG_N CUMULATIVE_SUM_HOSP CUMULATIVE_SUM_ICU CUMULATIVE_SUM_VENT CUMULATIVE_SUM_ECMO CUMULATIVE_SUM_DIAL
				CUMULATIVE_SUM_MARKET_HOSP CUMULATIVE_SUM_MARKET_ICU CUMULATIVE_SUM_MARKET_VENT CUMULATIVE_SUM_MARKET_ECMO CUMULATIVE_SUM_MARKET_DIAL;
			LAG_S = S_N; 
			LAG_E = E_N; 
			LAG_I = I_N; 
			LAG_R = R_N; 
			LAG_N = N; 
			SET TMODEL_SEIR(RENAME=(TIME=DAY) DROP=_ERRORS_ _MODE_ _TYPE_);
			N = SUM(S_N, E_N, I_N, R_N);
			SCALE = LAG_N / N;
		/*	NOTINFECTED = SUM(S_N,E_N);*/
		/*	NEWINFECTED=ROUND(SUM(LAG(NOTINFECTED),-1*NOTINFECTED),1);*/
			NEWINFECTED=ROUND(SUM(LAG(SUM(S_N,E_N)),-1*SUM(S_N,E_N)),1);
			IF NEWINFECTED < 0 THEN NEWINFECTED=0;
			HOSP = ROUND(NEWINFECTED * &HOSP_RATE * &MARKET_SHARE);
			ICU = ROUND(NEWINFECTED * &ICU_RATE * &MARKET_SHARE * &HOSP_RATE);
			VENT = ROUND(NEWINFECTED * &VENT_RATE * &MARKET_SHARE * &HOSP_RATE);
			ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &MARKET_SHARE * &HOSP_RATE);
			DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &MARKET_SHARE * &HOSP_RATE);
			MARKET_HOSP = ROUND(NEWINFECTED * &HOSP_RATE);
			MARKET_ICU = ROUND(NEWINFECTED * &ICU_RATE * &HOSP_RATE);
			MARKET_VENT = ROUND(NEWINFECTED * &VENT_RATE * &HOSP_RATE);
			MARKET_ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &HOSP_RATE);
			MARKET_DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &HOSP_RATE);
			CUMULATIVE_SUM_HOSP + HOSP;
			CUMULATIVE_SUM_ICU + ICU;
			CUMULATIVE_SUM_VENT + VENT;
			CUMULATIVE_SUM_ECMO + ECMO;
			CUMULATIVE_SUM_DIAL + DIAL;
			CUMULATIVE_SUM_MARKET_HOSP + MARKET_HOSP;
			CUMULATIVE_SUM_MARKET_ICU + MARKET_ICU;
			CUMULATIVE_SUM_MARKET_VENT + MARKET_VENT;
			CUMULATIVE_SUM_MARKET_ECMO + MARKET_ECMO;
			CUMULATIVE_SUM_MARKET_DIAL + MARKET_DIAL;
			CUMADMITLAGGED=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_HOSP),1) ;
			CUMICULAGGED=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_ICU),1) ;
			CUMVENTLAGGED=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_VENT),1) ;
			CUMECMOLAGGED=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_ECMO),1) ;
			CUMDIALLAGGED=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_DIAL),1) ;
			CUMMARKETADMITLAG=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_MARKET_HOSP));
			CUMMARKETICULAG=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_MARKET_ICU));
			CUMMARKETVENTLAG=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_MARKET_VENT));
			CUMMARKETECMOLAG=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_MARKET_ECMO));
			CUMMARKETDIALLAG=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_MARKET_DIAL));
			ARRAY FIXINGDOT _NUMERIC_;
			DO OVER FIXINGDOT;
				IF FIXINGDOT=. THEN FIXINGDOT=0;
			END;
			HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_HOSP-CUMADMITLAGGED,1);
			ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_ICU-CUMICULAGGED,1);
			VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_VENT-CUMVENTLAGGED,1);
			ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_ECMO-CUMECMOLAGGED,1);
			DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_DIAL-CUMDIALLAGGED,1);
			MARKET_HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_HOSP-CUMMARKETADMITLAG,1);
			MARKET_ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ICU-CUMMARKETICULAG,1);
			MARKET_VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_VENT-CUMMARKETVENTLAG,1);
			MARKET_ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ECMO-CUMMARKETECMOLAG,1);
			MARKET_DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_DIAL-CUMMARKETDIALLAG,1);	
			DATE = "&DAY_ZERO"D + DAY;
			ADMIT_DATE = SUM(DATE, &DAYS_TO_HOSP.);
			METHOD = "SEIR - TMODEL";
			DROP LAG: CUM: ;
		RUN;

	/*PROC TMODEL SIR APPROACH*/
		PROC TMODEL DATA = DINIT NOPRINT;
			/* PARAMETER SETTINGS */ 
			PARMS N &S. R0 &R_NAUGHT. ; 
			GAMMA = &GAMMA.;    	         
			BETA = R0*GAMMA/N;
			/* DIFFERENTIAL EQUATIONS */ 
			DERT.S_N = -BETA*S_N*I_N; 				
			DERT.I_N = BETA*S_N*I_N-GAMMA*I_N;   
			DERT.R_N = GAMMA*I_N;           
			/* SOLVE THE EQUATIONS */ 
			SOLVE S_N I_N R_N / OUT = TMODEL_SIR; 
		RUN;
		QUIT;

		DATA TMODEL_SIR;
			FORMAT ModelType $30. Scenarioname $30. DATE ADMIT_DATE DATE9.;	
			ModelType="TMODEL - SIR";
			ScenarioName="&Scenario";
			ScenarioIndex=&ScenarioIndex.;
			LABEL HOSPITAL_OCCUPANCY="Hospital Occupancy" ICU_OCCUPANCY="ICU Occupancy" VENT_OCCUPANCY="Ventilator Utilization"
				ECMO_OCCUPANCY="ECMO Utilization" DIAL_OCCUPANCY="Dialysis Utilization";
			LENGTH METHOD $15.;
			RETAIN LAG_S LAG_I LAG_R LAG_N CUMULATIVE_SUM_HOSP CUMULATIVE_SUM_ICU CUMULATIVE_SUM_VENT CUMULATIVE_SUM_ECMO CUMULATIVE_SUM_DIAL
				CUMULATIVE_SUM_MARKET_HOSP CUMULATIVE_SUM_MARKET_ICU CUMULATIVE_SUM_MARKET_VENT CUMULATIVE_SUM_MARKET_ECMO CUMULATIVE_SUM_MARKET_DIAL;
			LAG_S = S_N; 
			LAG_I = I_N; 
			LAG_R = R_N; 
			LAG_N = N; 
			SET TMODEL_SIR(RENAME=(TIME=DAY) DROP=_ERRORS_ _MODE_ _TYPE_);
			N = SUM(S_N, I_N, R_N);
			SCALE = LAG_N / N;
			NEWINFECTED=ROUND(SUM(LAG(S_N),-1*S_N),1);
			IF NEWINFECTED < 0 THEN NEWINFECTED=0;
			HOSP = ROUND(NEWINFECTED * &HOSP_RATE * &MARKET_SHARE);
			ICU = ROUND(NEWINFECTED * &ICU_RATE * &MARKET_SHARE * &HOSP_RATE);
			VENT = ROUND(NEWINFECTED * &VENT_RATE * &MARKET_SHARE * &HOSP_RATE);
			ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &MARKET_SHARE * &HOSP_RATE);
			DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &MARKET_SHARE * &HOSP_RATE);
			MARKET_HOSP = ROUND(NEWINFECTED * &HOSP_RATE);
			MARKET_ICU = ROUND(NEWINFECTED * &ICU_RATE * &HOSP_RATE);
			MARKET_VENT = ROUND(NEWINFECTED * &VENT_RATE * &HOSP_RATE);
			MARKET_ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &HOSP_RATE);
			MARKET_DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &HOSP_RATE);
			CUMULATIVE_SUM_HOSP + HOSP;
			CUMULATIVE_SUM_ICU + ICU;
			CUMULATIVE_SUM_VENT + VENT;
			CUMULATIVE_SUM_ECMO + ECMO;
			CUMULATIVE_SUM_DIAL + DIAL;
			CUMULATIVE_SUM_MARKET_HOSP + MARKET_HOSP;
			CUMULATIVE_SUM_MARKET_ICU + MARKET_ICU;
			CUMULATIVE_SUM_MARKET_VENT + MARKET_VENT;
			CUMULATIVE_SUM_MARKET_ECMO + MARKET_ECMO;
			CUMULATIVE_SUM_MARKET_DIAL + MARKET_DIAL;
			CUMADMITLAGGED=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_HOSP),1) ;
			CUMICULAGGED=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_ICU),1) ;
			CUMVENTLAGGED=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_VENT),1) ;
			CUMECMOLAGGED=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_ECMO),1) ;
			CUMDIALLAGGED=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_DIAL),1) ;
			CUMMARKETADMITLAG=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_MARKET_HOSP));
			CUMMARKETICULAG=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_MARKET_ICU));
			CUMMARKETVENTLAG=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_MARKET_VENT));
			CUMMARKETECMOLAG=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_MARKET_ECMO));
			CUMMARKETDIALLAG=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_MARKET_DIAL));
			ARRAY FIXINGDOT _NUMERIC_;
			DO OVER FIXINGDOT;
				IF FIXINGDOT=. THEN FIXINGDOT=0;
			END;
			HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_HOSP-CUMADMITLAGGED,1);
			ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_ICU-CUMICULAGGED,1);
			VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_VENT-CUMVENTLAGGED,1);
			ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_ECMO-CUMECMOLAGGED,1);
			DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_DIAL-CUMDIALLAGGED,1);
			MARKET_HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_HOSP-CUMMARKETADMITLAG,1);
			MARKET_ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ICU-CUMMARKETICULAG,1);
			MARKET_VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_VENT-CUMMARKETVENTLAG,1);
			MARKET_ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ECMO-CUMMARKETECMOLAG,1);
			MARKET_DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_DIAL-CUMMARKETDIALLAG,1);	
			DATE = "&DAY_ZERO"D + DAY;
			ADMIT_DATE = SUM(DATE, &DAYS_TO_HOSP.);
			METHOD = "SIR - TMODEL";
			DROP LAG: CUM:;
		RUN;

	/* DATA STEP APPROACH */
		DATA DS_SIR;
			FORMAT ModelType $30. Scenarioname $30. DATE ADMIT_DATE DATE9.;		
			ModelType="DS - SIR";
			ScenarioName="&Scenario";
			ScenarioIndex=&ScenarioIndex.;
			LABEL HOSPITAL_OCCUPANCY="Hospital Occupancy" ICU_OCCUPANCY="ICU Occupancy" VENT_OCCUPANCY="Ventilator Utilization"
				ECMO_OCCUPANCY="ECMO Utilization" DIAL_OCCUPANCY="Dialysis Utilization";
			LENGTH METHOD $15.;
			DO DAY = 0 TO &N_DAYS;
				IF DAY = 0 THEN DO;
					S_N = &S - (&I/&DIAGNOSED_RATE) - &R;
					I_N = &I/&DIAGNOSED_RATE;
					R_N = &R;
					BETA=&BETA;
					N = SUM(S_N, I_N, R_N);
				END;
				ELSE DO;
					BETA = LAG_BETA * (1- &BETA_DECAY);
					S_N = (-BETA * LAG_S * LAG_I) + LAG_S;
					I_N = (BETA * LAG_S * LAG_I - &GAMMA * LAG_I) + LAG_I;
					R_N = &GAMMA * LAG_I + LAG_R;
					N = SUM(S_N, I_N, R_N);
					SCALE = LAG_N / N;
					IF S_N < 0 THEN S_N = 0;
					IF I_N < 0 THEN I_N = 0;
					IF R_N < 0 THEN R_N = 0;
					S_N = SCALE*S_N;
					I_N = SCALE*I_N;
					R_N = SCALE*R_N;
				END;
				LAG_S = S_N;
				LAG_I = I_N;
				LAG_R = R_N;
				LAG_N = N;
				LAG_BETA = BETA;
				NEWINFECTED=ROUND(SUM(LAG(S_N),-1*S_N),1);
				IF NEWINFECTED < 0 THEN NEWINFECTED=0;
				HOSP = ROUND(NEWINFECTED * &HOSP_RATE * &MARKET_SHARE);
				ICU = ROUND(NEWINFECTED * &ICU_RATE * &MARKET_SHARE * &HOSP_RATE);
				VENT = ROUND(NEWINFECTED * &VENT_RATE * &MARKET_SHARE * &HOSP_RATE);
				ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &MARKET_SHARE * &HOSP_RATE);
				DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &MARKET_SHARE * &HOSP_RATE);
				MARKET_HOSP = ROUND(NEWINFECTED * &HOSP_RATE);
				MARKET_ICU = ROUND(NEWINFECTED * &ICU_RATE * &HOSP_RATE);
				MARKET_VENT = ROUND(NEWINFECTED * &VENT_RATE * &HOSP_RATE);
				MARKET_ECMO = ROUND(NEWINFECTED * &ECMO_RATE * &HOSP_RATE);
				MARKET_DIAL = ROUND(NEWINFECTED * &DIAL_RATE * &HOSP_RATE);
				CUMULATIVE_SUM_HOSP + HOSP;
				CUMULATIVE_SUM_ICU + ICU;
				CUMULATIVE_SUM_VENT + VENT;
				CUMULATIVE_SUM_ECMO + ECMO;
				CUMULATIVE_SUM_DIAL + DIAL;
				CUMULATIVE_SUM_MARKET_HOSP + MARKET_HOSP;
				CUMULATIVE_SUM_MARKET_ICU + MARKET_ICU;
				CUMULATIVE_SUM_MARKET_VENT + MARKET_VENT;
				CUMULATIVE_SUM_MARKET_ECMO + MARKET_ECMO;
				CUMULATIVE_SUM_MARKET_DIAL + MARKET_DIAL;
				CUMADMITLAGGED=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_HOSP),1) ;
				CUMICULAGGED=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_ICU),1) ;
				CUMVENTLAGGED=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_VENT),1) ;
				CUMECMOLAGGED=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_ECMO),1) ;
				CUMDIALLAGGED=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_DIAL),1) ;
				CUMMARKETADMITLAG=ROUND(LAG&HOSP_LOS(CUMULATIVE_SUM_MARKET_HOSP));
				CUMMARKETICULAG=ROUND(LAG&ICU_LOS(CUMULATIVE_SUM_MARKET_ICU));
				CUMMARKETVENTLAG=ROUND(LAG&VENT_LOS(CUMULATIVE_SUM_MARKET_VENT));
				CUMMARKETECMOLAG=ROUND(LAG&ECMO_LOS(CUMULATIVE_SUM_MARKET_ECMO));
				CUMMARKETDIALLAG=ROUND(LAG&DIAL_LOS(CUMULATIVE_SUM_MARKET_DIAL));
				ARRAY FIXINGDOT _NUMERIC_;
				DO OVER FIXINGDOT;
					IF FIXINGDOT=. THEN FIXINGDOT=0;
				END;
				HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_HOSP-CUMADMITLAGGED,1);
				ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_ICU-CUMICULAGGED,1);
				VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_VENT-CUMVENTLAGGED,1);
				ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_ECMO-CUMECMOLAGGED,1);
				DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_DIAL-CUMDIALLAGGED,1);
				MARKET_HOSPITAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_HOSP-CUMMARKETADMITLAG,1);
				MARKET_ICU_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ICU-CUMMARKETICULAG,1);
				MARKET_VENT_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_VENT-CUMMARKETVENTLAG,1);
				MARKET_ECMO_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_ECMO-CUMMARKETECMOLAG,1);
				MARKET_DIAL_OCCUPANCY= ROUND(CUMULATIVE_SUM_MARKET_DIAL-CUMMARKETDIALLAG,1);	
				DATE = "&DAY_ZERO"D + DAY;
				ADMIT_DATE = SUM(DATE, &DAYS_TO_HOSP.);
				METHOD = "SIR - DATA Step";
				OUTPUT;
			END;
			DROP LAG: BETA CUM: ;
		RUN;
	
	PROC APPEND base=MODEL_FINAL data=TMODEL_SEIR; run;
	PROC APPEND base=MODEL_FINAL data=TMODEL_SIR NOWARN FORCE; run;
	PROC APPEND base=MODEL_FINAL data=DS_SIR NOWARN FORCE; run;
	PROC APPEND base=SCENARIOS data=PARMS; run;

	%IF &PLOTS. = YES %THEN %DO;
		PROC SGPLOT DATA=MODEL_FINAL;
			where ModelType='TMODEL - SIER' and ScenarioIndex=&ScenarioIndex.;
			TITLE "Daily Occupancy - PROC TMODEL SEIR Approach";
			SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
			SERIES X=DATE Y=ICU_OCCUPANCY;
			SERIES X=DATE Y=VENT_OCCUPANCY;
			SERIES X=DATE Y=ECMO_OCCUPANCY;
			SERIES X=DATE Y=DIAL_OCCUPANCY;
			XAXIS LABEL="Date";
			YAXIS LABEL="Daily Occupancy";
		RUN;
		PROC SGPLOT DATA=MODEL_FINAL;
			where ModelType='TMODEL - SIR' and ScenarioIndex=&ScenarioIndex.;
			TITLE "Daily Occupancy - PROC TMODEL SIR Approach";
			SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
			SERIES X=DATE Y=ICU_OCCUPANCY;
			SERIES X=DATE Y=VENT_OCCUPANCY;
			SERIES X=DATE Y=ECMO_OCCUPANCY;
			SERIES X=DATE Y=DIAL_OCCUPANCY;
			XAXIS LABEL="Date";
			YAXIS LABEL="Daily Occupancy";
		RUN;
		PROC SGPLOT DATA=MODEL_FINAL;
			where ModelType='DS - SIR' and ScenarioIndex=&ScenarioIndex.;
			SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
			SERIES X=DATE Y=ICU_OCCUPANCY;
			SERIES X=DATE Y=VENT_OCCUPANCY;
			SERIES X=DATE Y=ECMO_OCCUPANCY;
			SERIES X=DATE Y=DIAL_OCCUPANCY;
			XAXIS LABEL="Date";
			YAXIS LABEL="Daily Occupancy";
		RUN;
		PROC SGPLOT DATA=MODEL_FINAL;
			TITLE "Daily Hospital Occupancy - All Approaches";
			SERIES X=DATE Y=HOSPITAL_OCCUPANCY / GROUP=MODELTYPE;
		/*	SERIES X=DATE Y=ICU_OCCUPANCY / GROUP=METHOD;*/
		/*	SERIES X=DATE Y=VENT_OCCUPANCY / GROUP=METHOD;*/
		/*	SERIES X=DATE Y=ECMO_OCCUPANCY / GROUP=METHOD;*/
		/*	SERIES X=DATE Y=DIAL_OCCUPANCY / GROUP=METHOD;*/
			XAXIS LABEL="Date";
			YAXIS LABEL="Daily Occupancy";
		RUN;
		TITLE;	
	%END;

%END;

%mend;

%EasyRun(scenario=BASE_Scenario_one,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.0,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125,plots=YES);

%EasyRun(scenario=BASE_Scenario_two,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.2,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=BASE_Scenario_three,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.4,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=BASE_Scenario_one_Inc,IncubationPeriod=10,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.0,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=BASE_Scenario_two_Inc,IncubationPeriod=10,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.2,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=BASE_Scenario_three_Inc,IncubationPeriod=10,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.4,MarketSharePercent=.29,Admission_Rate=.075,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_one_5Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.0,MarketSharePercent=.29,Admission_Rate=.05,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_two_5Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.2,MarketSharePercent=.29,Admission_Rate=.05,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_three_5Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.4,MarketSharePercent=.29,Admission_Rate=.05,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_one_3Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.0,MarketSharePercent=.29,Admission_Rate=.03,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_two_3Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.2,MarketSharePercent=.29,Admission_Rate=.03,ICUPercent=0.25,VentPErcent=0.125);

%EasyRun(scenario=Scenario_three_3Prcnt,IncubationPeriod=0,InitRecovered=0,RecoveryDays=14,
doublingtime=5,KnownAdmits=10,KnownCOVID=46,Population=4390484,
SocialDistancing=0.4,MarketSharePercent=.29,Admission_Rate=.03,ICUPercent=0.25,VentPErcent=0.125);




CAS;

CASLIB _ALL_ ASSIGN;

PROC CASUTIL;
	DROPTABLE INCASLIB="CASUSER" CASDATA="PROJECT_DS" QUIET;
	LOAD DATA=WORK.MODEL_FINAL CASOUT="PROJECT_DS" OUTCASLIB="CASUSER" PROMOTE;
	DROPTABLE INCASLIB="CASUSER" CASDATA="PROJECT_SCENARIOS" QUIET;
	LOAD DATA=WORK.SCENARIOS CASOUT="PROJECT_SCENARIOS" OUTCASLIB="CASUSER" PROMOTE;
QUIT;

CAS CASAUTO TERMINATE;
