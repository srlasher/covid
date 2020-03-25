%LET S_DEFAULT = 4390484;
%LET KNOWN_INFECTIONS = 46;
%LET KNOWN_CASES = 10;
/*Currently Hospitalized COVID-19 Patients*/
%LET CURRENT_HOSP = &KNOWN_CASES;
/*Doubling time before social distancing (days)*/
%LET DOUBLING_TIME = 5;
/*Social distancing (% reduction in social contact)*/
%LET RELATIVE_CONTACT_RATE = 0.00;
/**/
%LET ADMISSION_RATE=0.075;
/*factor to adjust %admission to make sense multiplied by Total I*/
%LET DIAGNOSED_RATE=1.0; 
/*Hospitalization %(total infections)*/
%LET HOSP_RATE = %SYSEVALF(&ADMISSION_RATE*&DIAGNOSED_RATE);
/*ICU %(total infections)*/
%LET ICU_RATE = %SYSEVALF(0.25*&DIAGNOSED_RATE);
/*Ventilated %(total infections)*/
%LET VENT_RATE = %SYSEVALF(0.125*&DIAGNOSED_RATE);
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
/*Hospital Market Share (%)*/
%LET MARKET_SHARE = 0.29;
%LET DEATH_RATE=0.00;
/*Regional Population*/
%LET S = &S_DEFAULT;
/*Currently Known Regional Infections (only used to compute detection rate - does not change projections*/
%LET INITIAL_INFECTIONS = &KNOWN_INFECTIONS;
%LET TOTAL_INFECTIONS = %SYSEVALF(&CURRENT_HOSP / &MARKET_SHARE / &HOSP_RATE);
%LET DETECTION_PROB = %SYSEVALF(&INITIAL_INFECTIONS / &TOTAL_INFECTIONS);
%LET I = %SYSEVALF(&INITIAL_INFECTIONS / &DETECTION_PROB);
/*Initial Number of Exposed (infected but not yet infectious)*/
%LET E = 0;
/*Initial Number of Recovered*/
%LET R = 0;
%LET INTRINSIC_GROWTH_RATE = %SYSEVALF(2 ** (1 / &DOUBLING_TIME) - 1);
%LET RECOVERY_DAYS = 14;
%LET GAMMA = %SYSEVALF(1/&RECOVERY_DAYS);
%LET BETA = %SYSEVALF((&INTRINSIC_GROWTH_RATE + &GAMMA) / &S * (1-&RELATIVE_CONTACT_RATE));
/*R_T is R_0 after distancing*/
%LET R_T = %SYSEVALF(&BETA / &GAMMA * &S);
%LET R_NAUGHT = %SYSEVALF(&R_T / (1-&RELATIVE_CONTACT_RATE));
/*doubling time after distancing*/
%LET DOUBLING_TIME_T = %SYSEVALF(1/%SYSFUNC(LOG2(&BETA*&S - &GAMMA + 1)));
/*rate of latent individuals Exposed transported to the infectious stage each time period*/
%LET SIGMA = 0.90;
%LET N_DAYS = 365;
%LET BETA_DECAY = 0.0;
/*Average number of days from infection to hospitalization*/
%LET DAYS_TO_HOSP = 0;
/*Date of first COVID-19 Case*/
%LET DAY_ZERO = 13MAR2020;

%PUT _ALL_;

/* DATA STEP APPROACH */
DATA DS_FINAL;
	FORMAT DATE ADMIT_DATE DATE9.;
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

PROC SGPLOT DATA=DS_FINAL;
	TITLE "Daily Occupancy - Data Step SIR Approach";
	SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
	SERIES X=DATE Y=ICU_OCCUPANCY;
	SERIES X=DATE Y=VENT_OCCUPANCY;
	SERIES X=DATE Y=ECMO_OCCUPANCY;
	SERIES X=DATE Y=DIAL_OCCUPANCY;
	XAXIS LABEL="Date";
	YAXIS LABEL="Daily Occupancy";
RUN;

TITLE;

PROC DATASETS LIB=WORK NOPRINT NOWARN;
	DELETE ALL_APPROACHES;
RUN;
QUIT;

PROC APPEND BASE=ALL_APPROACHES DATA=DS_FINAL;
RUN;

/*PROC TMODEL APPROACHES*/
DATA DINIT(Label="Initial Conditions of Simulation"); 
	S_N = &S - (&I/&DIAGNOSED_RATE) - &R;
	E_N = &E;
	I_N = &I/&DIAGNOSED_RATE;
	R_N = &R;
	R0=&R_NAUGHT;
	DO TIME = 0 TO &N_DAYS; 
		OUTPUT; 
	END; 
RUN;

/*PROC TMODEL SIR APPROACH*/
PROC TMODEL DATA = DINIT NORPINT;
	/* PARAMETER SETTINGS */ 
	PARMS N &S. R0 &R_NAUGHT. ; 
	GAMMA = &GAMMA.;    	         
	BETA = R0*GAMMA/N;
	/* DIFFERENTIAL EQUATIONS */ 
	DERT.S_N = -BETA*S_N*I_N; 				
	DERT.I_N = BETA*S_N*I_N-GAMMA*I_N;   
	DERT.R_N = GAMMA*I_N;           
	/* SOLVE THE EQUATIONS */ 
	SOLVE S_N I_N R_N / OUT = TMODEL_SIR_FINAL; 
RUN;
QUIT;

DATA TMODEL_SIR_FINAL;
	FORMAT DATE ADMIT_DATE DATE9.;
	LABEL HOSPITAL_OCCUPANCY="Hospital Occupancy" ICU_OCCUPANCY="ICU Occupancy" VENT_OCCUPANCY="Ventilator Utilization"
		 ECMO_OCCUPANCY="ECMO Utilization" DIAL_OCCUPANCY="Dialysis Utilization";
	LENGTH METHOD $15.;
	RETAIN LAG_S LAG_I LAG_R LAG_N CUMULATIVE_SUM_HOSP CUMULATIVE_SUM_ICU CUMULATIVE_SUM_VENT CUMULATIVE_SUM_ECMO CUMULATIVE_SUM_DIAL
		CUMULATIVE_SUM_MARKET_HOSP CUMULATIVE_SUM_MARKET_ICU CUMULATIVE_SUM_MARKET_VENT CUMULATIVE_SUM_MARKET_ECMO CUMULATIVE_SUM_MARKET_DIAL;
 	LAG_S = S_N; 
 	LAG_I = I_N; 
 	LAG_R = R_N; 
 	LAG_N = N; 
	SET TMODEL_SIR_FINAL(RENAME=(TIME=DAY) DROP=_ERRORS_ _MODE_ _TYPE_);
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

PROC SGPLOT DATA=TMODEL_SIR_FINAL;
	TITLE "Daily Occupancy - PROC TMODEL SIR Approach";
	SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
	SERIES X=DATE Y=ICU_OCCUPANCY;
	SERIES X=DATE Y=VENT_OCCUPANCY;
	SERIES X=DATE Y=ECMO_OCCUPANCY;
	SERIES X=DATE Y=DIAL_OCCUPANCY;
	XAXIS LABEL="Date";
	YAXIS LABEL="Daily Occupancy";
RUN;

TITLE;

PROC APPEND BASE=ALL_APPROACHES DATA=TMODEL_SIR_FINAL;
RUN;

/*PROC TMODEL SEIR APPROACH*/
PROC TMODEL DATA = DINIT NOPRINT;
	/* PARAMETER SETTINGS */ 
	PARMS N &S. R0 &R_NAUGHT. ; 
	GAMMA = &GAMMA.;
	SIGMA = &SIGMA;
	BETA = R0*GAMMA/N;
	/* DIFFERENTIAL EQUATIONS */ 
	DERT.S_N = -BETA*S_N*I_N;
	DERT.E_N = BETA*S_N*I_N-SIGMA*E_N;
	DERT.I_N = SIGMA*E_N-GAMMA*I_N;   
	DERT.R_N = GAMMA*I_N;           
	/* SOLVE THE EQUATIONS */ 
	SOLVE S_N E_N I_N R_N / OUT = TMODEL_SEIR_FINAL; 
RUN;
QUIT;

DATA TMODEL_SEIR_FINAL;
	FORMAT DATE ADMIT_DATE DATE9.;
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
	SET TMODEL_SEIR_FINAL(RENAME=(TIME=DAY) DROP=_ERRORS_ _MODE_ _TYPE_);
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

PROC SGPLOT DATA=TMODEL_SEIR_FINAL;
	TITLE "Daily Occupancy - PROC TMODEL SEIR Approach";
	SERIES X=DATE Y=HOSPITAL_OCCUPANCY;
	SERIES X=DATE Y=ICU_OCCUPANCY;
	SERIES X=DATE Y=VENT_OCCUPANCY;
	SERIES X=DATE Y=ECMO_OCCUPANCY;
	SERIES X=DATE Y=DIAL_OCCUPANCY;
	XAXIS LABEL="Date";
	YAXIS LABEL="Daily Occupancy";
RUN;

TITLE;

PROC APPEND BASE=ALL_APPROACHES DATA=TMODEL_SEIR_FINAL FORCE;
RUN;

PROC SGPLOT DATA=ALL_APPROACHES;
	TITLE "Daily Hospital Occupancy - All Approaches";
	SERIES X=DATE Y=HOSPITAL_OCCUPANCY / GROUP=METHOD;
/*	SERIES X=DATE Y=ICU_OCCUPANCY / GROUP=METHOD;*/
/*	SERIES X=DATE Y=VENT_OCCUPANCY / GROUP=METHOD;*/
/*	SERIES X=DATE Y=ECMO_OCCUPANCY / GROUP=METHOD;*/
/*	SERIES X=DATE Y=DIAL_OCCUPANCY / GROUP=METHOD;*/
	XAXIS LABEL="Date";
	YAXIS LABEL="Daily Occupancy";
RUN;

TITLE;

CAS;

CASLIB _ALL_ ASSIGN;

PROC CASUTIL;
	DROPTABLE INCASLIB="CASUSER" CASDATA="PROJECT_DS" QUIET;
	LOAD DATA=WORK.DS_FINAL CASOUT="PROJECT_DS" OUTCASLIB="CASUSER" PROMOTE;
QUIT;


PROC CASUTIL;
	DROPTABLE INCASLIB="CASUSER" CASDATA="PROJECT_MODEL" QUIET;
	LOAD DATA=WORK.TMODEL_FINAL CASOUT="PROJECT_MODEL" OUTCASLIB="CASUSER" PROMOTE;
QUIT;

CAS CASAUTO TERMINATE;
