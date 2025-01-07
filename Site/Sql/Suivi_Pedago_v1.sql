
	-- pwi 2024-12-17 v0 creation
	-- pwi 2024-12-21 v1 extend modules to also have modules which will start in less than one month
	--                   add notes pedago
	--                   fix signatures stagiaires manquantes to not count seances where stagiaires was absent
	--                   use a person label instead of module stagiaire label

	use TOM59331;
	select
		-- MODULE LEVEL
		-- Nom du Module (id, label)
		MODULES.ID
		, MODULES.Label as ModuleLabel
		, MODULES.FormuleID
		, FORMULES.Label as FormuleLabel
		, MODULES.DateFrom as ModuleDateFrom
		, MODULES.DateTo as ModuleDateTo
		, MODULES.NStagiaires as ModuleNbStagiaires
		, MODULES.DureeModule as ModuleDureeMinutes
		, MODULES.DureeHeures as ModuleDureeHeures
		, MODULES.SoldeToPlann as ModuleSoldeToPlann
		, MODULES.CentreID
		, CENTRES.Label as CentreLabel
		, MODULES.RefPedagoID as RefPedagoID
		, PEDAGO.Label as RefPedagoLabel
		, MODULES.LangueID
		, LANGUES.Label as LangueLabel
		-- convention(s)
		, CONVENTIONS.ConventionLabel
		, CONVENTIONS.CompanyID
		, CONVENTIONS.CompanyName
		, CONVENTIONS.ConventionDateFromMin
		, CONVENTIONS.ConventionDateToMax
		-- Date du premier cours + si possible si cette date a été changée depuis la dernière extraction
		, SEANCES.PremierCours as SeancesPremierCours
		-- ?? Date du dernier cours + si possible si cette date a été changée depuis la dernière extraction
		-- Date du dernier cours planifié + si possible si cette date a été changée depuis la dernière extraction
		, SEANCES.DernierCours as SeanceDernierCours
		-- Note pédagogique manquante : non  / oui (avec date si oui ) -> SeancesIntraVars.NoShow ?
		, NOTES_PEDAGO_DUE.NotesPedagoDue
		, NOTES_PEDAGO_FOUND.NotesPedagoFound
		, ( NOTES_PEDAGO_DUE.NotesPedagoDue - NOTES_PEDAGO_FOUND.NotesPedagoFound ) as NotesPedagoManquantes
		-- les séances
		, ISNULL( SEANCES_PASSEES.SeancesCount, 0 ) as SeancesPassees
		-- Signature formateur manquante : non/ oui (avec date si oui)
		, ISNULL( SIGN_FORMATEUR_MANQUANTES.SignFormateurManquantes, 0 ) as SeanceSignFormateurManquantes
		-- stagiaires
		, MODULES_STAGIAIRES.ID as ModuleStagiaireID
		, MODULES_STAGIAIRES.label as ModuleStagiaireLabel
		, PERSONS.ID as PersonID
		, PERSONS.Label as PersonLabel
		, PERSONS.Civility as PersonCivility
		, PERSONS.Email as PersonEmail
		-- TODO
		-- Signature stagiaire manquante : non / oui (avec date si oui )
		, ISNULL( SIGN_STAG_MANQUANTES.SignStagManquantes, 0 ) as SeanceSignStagiaireManquantes
		-- Absence stagiaire : pourcentage et nombre d'heures d'absence
		, ISNULL( ABSENCES.AbsencesMinutes, 0 ) as StagiaireAbsencesTotalMinutes
		, ISNULL( ABSENCES.AbsencesCount, 0 ) as StagiaireAbsencesCount
		, ( ISNULL( ABSENCES.AbsencesMinutes, 0 ) * 100 / MODULES.DureeModule ) as StagiaireAbsencesPercentMinutes
		, CASE
			WHEN SEANCES_PASSEES.SeancesCount IS NULL OR SEANCES_PASSEES.SeancesCount = 0 THEN 'N/A'
			ELSE CAST( ISNULL( ABSENCES.AbsencesCount, 0 ) * 100 / SEANCES_PASSEES.SeancesCount AS VARCHAR )
		  END as StagiaireAbsencesPercentCount
		-- Date de planification de l'évaluation (date de la séance sur laquelle le ( E ) a été placé )
		-- (E ) non planifié
		, CASE
			WHEN EVALUATION.Evaluation is null THEN ''
			ELSE CONVERT( VARCHAR, EVALUATION.Evaluation, 120 )
		  END as EvaluationPlanifiee
		-- Date à laquelle l'évaluation a été remplie par le formateur
		-- Evaluation due et non remplie
		, CASE
			WHEN EVALS_INTRAS.DayDate is null THEN
				CASE
					WHEN EVALUATION.Evaluation is not null and EVALUATION.Evaluation < GETDATE() THEN 'DUE'
					ELSE ''
				END
			ELSE CONVERT( VARCHAR, EVALS_INTRAS.DayDate, 120 )
		  END as EvaluationRenseignee
		-- ?? Date rapport de progrès validé
		-- ?? Rapport de progrès à valider
		-- Questionnaire Début (QD) : date planifié
		-- Questionnaire Début (QD) : date renseigné
		-- Quest.ionnaire Début (QD) : non renseigné
		, QDEBUT.DayDate as QuestionnaireDebut
		-- Questionnaire FIN (QF) : date planifié
		-- Questionnaire Fin (QF) : date renseigné (+ si possible note globale et si veut continuer Oui/Non)
		-- Questionnaire Fin (QF) : non renseigné
		, QFIN.DayDate as QuestionnaireFin
		, case QFIN.ReprendreFormation
			when -1 then 'Ne sais pas'
			when 0 then 'Oui'
			when 1 then 'Non'
		  end as ReprendreFormation

		from ( select ID as ModuleStagiaireID, ModuleID from dbo.c_ModulesStagiaires where ModuleID in (
				-- les modules en cours, ou qui commencent dans moins de 1 mois, ou terminés depuis moins de 1 mois
				select ID from dbo.c_Modules where DateFrom < DATEADD(MONTH, +1, GETDATE()) and DateTo > DATEADD(MONTH, -1, GETDATE())
				-- 11128 -- 5 stagiaires x 30 séances
				-- 10987 -- notes pedago manquantes
		)) RES

		left join dbo.c_Modules MODULES on MODULES.ID = RES.ModuleID
		left join dbo.c_ModulesStagiaires MODULES_STAGIAIRES on MODULES_STAGIAIRES.ID = RES.ModuleStagiaireID
		left join dbo.c_Centres CENTRES on CENTRES.ID = MODULES.CentreID 
		left join dbo.c_Employees PEDAGO on PEDAGO.ID = MODULES.RefPedagoID 
		left join dbo.c_Formules FORMULES on FORMULES.ID = MODULES.FormuleID 
		left join dbo.c_Langues LANGUES on LANGUES.ID = MODULES.LangueID 

		-- the stagiaire name
		left join dbo.c_Persons PERSONS on PERSONS.ID = MODULES_STAGIAIRES.PersonID

		-- as of 2024-12-12, 42 modules do not have any convention
		left join ( select C.ModuleID, max(C.CompanyID) as CompanyID, max(C.CompanyName) as CompanyName,
			string_agg( C.Label, '/ ') as ConventionLabel, min( C.DateConv) as ConventionDateFromMin, max( C.DateTo) as ConventionDateToMax
			from dbo.c_Conventions C group by C.ModuleID ) CONVENTIONS on CONVENTIONS.ModuleID = MODULES.ID

		-- les seances planifiées
		left join ( select A.ModuleID, min( A.DayDate ) as PremierCours, max( A.DayDate ) as DernierCours from dbo.c_SeancesIntraVars A group by A.ModuleID ) SEANCES on SEANCES.ModuleID = MODULES.ID

		left join ( select A.ModuleID, min( A.DateHourFrom ) as Evaluation from dbo.c_SeancesIntraVars A where A.Label like '% (E)' group by A.ModuleID ) EVALUATION on EVALUATION.ModuleID = MODULES.ID

		-- les séances exécutées
		left join ( select A.ModuleStagiaireID, count( A.DateHourFrom ) as SignStagManquantes
			from dbo.c_StagiairesSeancesIntraVars A where A.DateHourFrom < GETDATE() and A.SignImage is null and A.TypePresence = 'PRS' group by A.ModuleStagiaireID ) SIGN_STAG_MANQUANTES on SIGN_STAG_MANQUANTES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, count( A.DateHourFrom ) as SeancesCount
			from dbo.c_StagiairesSeancesIntraVars A where A.DateHourFrom < GETDATE() group by A.ModuleStagiaireID ) SEANCES_PASSEES on SEANCES_PASSEES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, sum( A.NMinutes ) as AbsencesMinutes, count( A.DateHourFrom ) as AbsencesCount
			from dbo.c_StagiairesSeancesIntraVars A where A.DateHourFrom < GETDATE() and A.DateAbs is not null group by A.ModuleStagiaireID ) ABSENCES on ABSENCES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleID, count( A.DayDate ) as SignFormateurManquantes
			from dbo.c_SeancesIntraVars A where A.DayDate < GETDATE() and A.SignImage is null group by A.ModuleID ) SIGN_FORMATEUR_MANQUANTES on SIGN_FORMATEUR_MANQUANTES.ModuleID = MODULES.ID

		-- les notes pédagogiques à renseigner par le formateur pour chaque séance
		-- la note est dûe si la logistique de la session dit qu'il y a un formateur
		-- la note est attachée à la séance, commune à tous les stagiaires participants
		left join ( select A.ModuleID, count(*) as NotesPedagoDue from dbo.c_SeancesIntraVars A
			inner join dbo.e_LogisticVarType B on B.Code = A.LogisticVarType and B.IsFormateur = 1 and A.DayDate < GETDATE()
			group by A.ModuleID
				 ) NOTES_PEDAGO_DUE on NOTES_PEDAGO_DUE.ModuleID = RES.ModuleID

		left join ( select B.ModuleID, COUNT(*) as NotesPedagoFound from dbo.c_SeancesIntraVarPedagos A
			inner join dbo.c_SeancesIntraVars B on B.ID = A.ID 
			where ISNULL( A.Label, '' ) <> '' or ISNULL( A.Remarques, '' ) <> '' or ISNULL( A.Conseils, '' ) <> '' or ISNULL( A.TravailPerso, '' ) <> ''
			group by B.ModuleID ) NOTES_PEDAGO_FOUND on NOTES_PEDAGO_FOUND.ModuleID = RES.ModuleID

		-- les résultats, évaluations et questionnaires de début et de fin
		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_EvaluationsIntras A group by A.ModuleStagiaireID ) EVALS_INTRAS on EVALS_INTRAS.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_StagiaireSatisfactionStartsEcs A group by A.ModuleStagiaireID ) QDEBUT on QDEBUT.ModuleStagiaireID = MODULES_STAGIAIRES.ID -- RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate, min( A.ReprendreFormation ) as ReprendreFormation
			from dbo.c_StagiaireSatisfactionsEcs A group by A.ModuleStagiaireID ) QFIN on QFIN.ModuleStagiaireID = MODULES_STAGIAIRES.ID -- RES.ModuleStagiaireID

	--order by ModuleNbStagiaires desc
	-- where MODULES.Label like '%sethness%'
	--order by FormuleID asc, MODULES.ID asc, ModuleStagiaireID