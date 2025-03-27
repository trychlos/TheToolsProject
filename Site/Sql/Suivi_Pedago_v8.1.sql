
	-- pwi 2024-12-17 v0 creation
	-- pwi 2024-12-21 v1 extend modules to also have modules which will start in less than one month
	--                   add notes pedago
	--                   fix signatures stagiaires manquantes to not count seances where stagiaires was absent
	--                   use a person label instead of module stagiaire label
	-- pwi 2024-12-23 v2 extend to cours inters
	--                   add 'Inters'/'Intras' fixed string as column zero to distinguish between the two queries
	--                   add 'date de validation du rapport de progrès'
	--                   add median date and if it is past
	-- pwi 2025- 1- 7 v3 have a space instead of NULL on last columns
	--                   are considered absents stagiaires where TypePresence is not 'PRS'
	-- pwi 2025- 1- 9 v4 absences are all AB* (ABS and AB10 AB15 etc.)
	--                   'PRS' is set when the stagiaire signs, but not all seances/cours have to be signed (see [b_LstPlanningToSign_Stagiaire] stored procedure)
	-- pwi 2025- 1-15 v5 pas de signature formateur en e-learning (check that LogisticVarType.Isformateur = 1 and NoSHow = 0)
	-- pwi 2025- 1-16 v6 remove AbsencesMinutes
	-- pwi 2025- 3- 5 v8 pas de formateur lorsqu'il n'est pas identifié en SéanceIntraVar
	-- pwi 2025- 3-26 v8.1 backport from v9
	--                     fix last notes selection and display
	--                     add QuestionnaireDebutDue when the third planned seance is past

	use TOM59331;
	-- ==============================================================================================================================
	select
		'Intras' as Source
		-- MODULE LEVEL
		-- Nom du Module (id, label)
		, MODULES.ID as ModuleID
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
		, SEANCES.DernierCours as SeancesDernierCours
		-- date mediane
		-- soit la date mediane des cours si tout a été planifié, sinon la date médiane de la convention
		, CASE
			WHEN MODULES.SoldeToPlann = 0 THEN DATEADD( DAY, DATEDIFF( DAY, SEANCES.PremierCours, SEANCES.DernierCours ) / 2, SEANCES.PremierCours )
			ELSE DATEADD( DAY, DATEDIFF( DAY, CONVENTIONS.ConventionDateFromMin, CONVENTIONS.ConventionDateToMax ) / 2, CONVENTIONS.ConventionDateFromMin )
		  END as SeancesMiParcoursDate
		, CASE
			WHEN MODULES.SoldeToPlann = 0 THEN
				CASE
					WHEN DATEADD( DAY, DATEDIFF( DAY, SEANCES.PremierCours, SEANCES.DernierCours ) / 2, SEANCES.PremierCours ) < GETDATE() THEN 'Passee'
					ELSE ''
				END
			ELSE 
				CASE
					WHEN DATEADD( DAY, DATEDIFF( DAY, CONVENTIONS.ConventionDateFromMin, CONVENTIONS.ConventionDateToMax ) / 2, CONVENTIONS.ConventionDateFromMin ) < GETDATE() THEN 'Passee'
					ELSE ''
				END
		  END as SeancesMiParcoursPassée
		-- Date et contenu de la note la plus récente
		, NOTES.Label as LastNoteLabel
		, NOTES.Notes as LastNoteContent
		, NOTES.DayDate as LastNoteDate
		-- Note pédagogique manquante : non  / oui (avec date si oui ) -> SeancesIntraVars.NoShow ?
		, NOTES_PEDAGO_DUE.NotesPedagoDue
		, NOTES_PEDAGO_FOUND.NotesPedagoFound
		, ( NOTES_PEDAGO_DUE.NotesPedagoDue - NOTES_PEDAGO_FOUND.NotesPedagoFound ) as NotesPedagoManquantes
		-- les séances
		, ISNULL( SEANCES_PASSEES.SeancesCount, 0 ) as SeancesPassees
		-- Signature formateur manquante : non/ oui (avec date si oui)
		, ISNULL( SIGN_FORMATEUR_MANQUANTES.SignFormateurManquantes, 0 ) as SeancesSignFormateurManquantes
		-- stagiaires
		, MODULES_STAGIAIRES.ID as ModuleStagiaireID
		, MODULES_STAGIAIRES.label as ModuleStagiaireLabel
		, PERSONS.ID as PersonID
		, PERSONS.Label as PersonLabel
		, PERSONS.Civility as PersonCivility
		, PERSONS.Email as PersonEmail
		-- Signature stagiaire manquante : non / oui (avec date si oui )
		, ISNULL( SIGN_STAG_MANQUANTES.SignStagManquantes, 0 ) as StagiaireSignManquantes
		-- Absence stagiaire : pourcentage et nombre d'heures d'absence
		-- , ISNULL( ABSENCES.AbsencesMinutes, 0 ) as StagiaireAbsencesMinutes
		-- , ( ISNULL( ABSENCES.AbsencesMinutes, 0 ) * 100 / MODULES.DureeModule ) as StagiaireAbsencesPercentMinutes
		, ISNULL( ABSENCES.AbsencesCount, 0 ) as StagiaireAbsencesCount
		, CASE
			WHEN SEANCES_PASSEES.SeancesCount IS NULL OR SEANCES_PASSEES.SeancesCount = 0 THEN ''
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
		-- Date rapport de progrès validé / à valider
		, CASE
			WHEN RAPPORT_VALIDE.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, RAPPORT_VALIDE.DayDate, 120 )
		  END as RapportProgresValide
		-- Questionnaire Début (QD) : date planifiée
		-- Affichée lorsqu'elle est plannifiée (on a trouvé une séance n° 3) et passée
		, CASE
			--WHEN QDPLANNED.DayDate IS NULL or QDPLANNED.DayDate < GETDATE() THEN ''
			WHEN QDPLANNED.DayDate IS NULL THEN '' --'(null)'
			WHEN QDPLANNED.DayDate > GETDATE() THEN '' --'(future)'
			WHEN QDEBUT.DayDate is not null THEN '' --'(done)'
			ELSE CONVERT( VARCHAR, QDPLANNED.DayDate, 120 )
		  END as QuestionnaireDebutDue
		-- Questionnaire Début (QD) : date renseigné
		-- Quest.ionnaire Début (QD) : non renseigné
		, CASE
			WHEN QDEBUT.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, QDEBUT.DayDate, 120 )
		  END as QuestionnaireDebutDone
		-- Questionnaire FIN (QF) : date planifié
		-- Questionnaire Fin (QF) : date renseigné (+ si possible note globale et si veut continuer Oui/Non)
		-- Questionnaire Fin (QF) : non renseigné
		, CASE
			WHEN QFIN.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, QFIN.DayDate, 120 )
		  END as QuestionnaireFin
		, ISNULL( case QFIN.ReprendreFormation
			when -1 then 'Ne sais pas'
			when 0 then 'Oui'
			when 1 then 'Non'
		  end, '' ) as ReprendreFormation

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

		-- content and date of most recent attached note
		left join (
			select A.ModuleID, A.Label, A.Notes, A.DayDate, row_number() over ( partition by A.ModuleID order by A.DayDate desc ) as rn
				from dbo.c_Notes A ) NOTES on NOTES.ModuleID = RES.ModuleID and rn=1

		-- les séances exécutées
		-- la presence 'PRS' est positionnée lorsque le stagiaire signe electroniquement
		-- les signatures manquantes sont celles où le stagiaire n'est pas marqué absent ET la seance n'a pas NoShow=0 ET la logistique de la seance n'est pas ST (sous-traitance)
		left join ( select A.ModuleStagiaireID, count( A.DateHourFrom ) as SignStagManquantes
			from dbo.c_StagiairesSeancesIntraVars A 
				inner join dbo.c_SeancesIntraVars B on B.ID = A.SeanceIntraVarID
				where A.DateHourFrom < GETDATE() and A.SignImage is null and A.TypePresence <> 'PRS' and A.TypePresence not like 'AB%' and B.NoShow = 0 and B.LogisticVarType <> 'ST'
				group by A.ModuleStagiaireID ) SIGN_STAG_MANQUANTES on SIGN_STAG_MANQUANTES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, count( A.DateHourFrom ) as SeancesCount
			from dbo.c_StagiairesSeancesIntraVars A where A.DateHourFrom < GETDATE() group by A.ModuleStagiaireID ) SEANCES_PASSEES on SEANCES_PASSEES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleStagiaireID, sum( A.NMinutes ) as AbsencesMinutes, count( A.DateHourFrom ) as AbsencesCount
			from dbo.c_StagiairesSeancesIntraVars A where A.DateHourFrom < GETDATE() and A.TypePresence like 'AB%' group by A.ModuleStagiaireID ) ABSENCES on ABSENCES.ModuleStagiaireID = RES.ModuleStagiaireID

		left join ( select A.ModuleID, count( A.DayDate ) as SignFormateurManquantes
			from dbo.c_SeancesIntraVars A
				inner join dbo.e_LogisticVarType B on B.Code = A.LogisticVarType
				where A.NoShow = 0 and A.DayDate < GETDATE() and A.FormateurID is not null and A.SignImage is null and B.IsFormateur = 1 group by A.ModuleID ) SIGN_FORMATEUR_MANQUANTES on SIGN_FORMATEUR_MANQUANTES.ModuleID = MODULES.ID

		-- les notes pédagogiques à renseigner par le formateur pour chaque séance
		-- la note est dûe si la logistique de la session dit qu'il y a un formateur
		-- la note est attachée à la séance, commune à tous les stagiaires participants
		left join ( select A.ModuleID, count(*) as NotesPedagoDue from dbo.c_SeancesIntraVars A
			inner join dbo.e_LogisticVarType B on B.Code = A.LogisticVarType and B.IsFormateur = 1 and A.DayDate < GETDATE()
				group by A.ModuleID ) NOTES_PEDAGO_DUE on NOTES_PEDAGO_DUE.ModuleID = RES.ModuleID

		left join ( select B.ModuleID, COUNT(*) as NotesPedagoFound from dbo.c_SeancesIntraVarPedagos A
			inner join dbo.c_SeancesIntraVars B on B.ID = A.ID 
			where ISNULL( A.Label, '' ) <> '' or ISNULL( A.Remarques, '' ) <> '' or ISNULL( A.Conseils, '' ) <> '' or ISNULL( A.TravailPerso, '' ) <> ''
			group by B.ModuleID ) NOTES_PEDAGO_FOUND on NOTES_PEDAGO_FOUND.ModuleID = RES.ModuleID

		-- les résultats, évaluations et questionnaires de début et de fin
		-- evaluation planifiée (rapport de progrès): une date par module pour tous les stagiaires
		left join ( select A.ModuleID, min( A.DateHourFrom ) as Evaluation
			from dbo.c_SeancesIntraVars A where A.Label like '% (E)' group by A.ModuleID ) EVALUATION on EVALUATION.ModuleID = RES.ModuleID

		-- evaluation realisee: une date par stagiaire
		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_EvaluationsIntras A group by A.ModuleStagiaireID ) EVALS_INTRAS on EVALS_INTRAS.ModuleStagiaireID = RES.ModuleStagiaireID

		-- evaluation validée
		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_EmailSents A where A.Label like 'Rapport de Progr%' group by A.ModuleStagiaireID ) RAPPORT_VALIDE on RAPPORT_VALIDE.ModuleStagiaireID = RES.ModuleStagiaireID

		-- questionnaire de début: planned date
		-- le questionnaire de debut est planifié pour la troisième séance
		left join ( select ModuleID, NSeance, DayDate
			from dbo.c_SeancesIntraVars A ) QDPLANNED on QDPLANNED.ModuleID = RES.ModuleID and QDPLANNED.NSeance = 3

		-- questionnaire de début: date
		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_StagiaireSatisfactionStartsEcs A group by A.ModuleStagiaireID ) QDEBUT on QDEBUT.ModuleStagiaireID = RES.ModuleStagiaireID

		-- questionnaire de fin: date et resultat
		left join ( select A.ModuleStagiaireID, min( A.DayDate ) as DayDate, min( A.ReprendreFormation ) as ReprendreFormation
			from dbo.c_StagiaireSatisfactionsEcs A group by A.ModuleStagiaireID ) QFIN on QFIN.ModuleStagiaireID = RES.ModuleStagiaireID

	-- ==============================================================================================================================
	select
		  'Inters' as Source
		-- COURS level
		, COURS.ID as CoursID
		, COURS.Label as CoursLabel
		, COURS.FormuleID
		, FORMULES.Label as FormuleLabel
		, COURS.DateFrom as CoursDateFrom
		, COURS.DateTo as CoursDateTo
		, COURS.NStagiaires as CoursNbStagiaires
		, COURS.DureeCours as CoursDureeMinutes
		, CAST( COURS.DureeCours / 60 AS VARCHAR ) + ':' + RIGHT( '00' + CAST( COURS.DureeCours % 60 AS VARCHAR(2)), 2 ) as CoursDureeHeures
		, COURS.SoldeToPlann as CoursSoldeToPlann
		, COURS.CentreID
		, CENTRES.Label as CentreLabel
		, COURS.RefPedagoID as RefPedagoID
		, PEDAGO.Label as RefPedagoLabel
		, COURS.LangueID
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
		, SEANCES.DernierCours as SeancesDernierCours
		-- date mediane
		-- soit la date mediane des cours si tout a été planifié, sinon la date médiane de la convention
		, CASE
			WHEN COURS.SoldeToPlann = 0 THEN DATEADD( DAY, DATEDIFF( DAY, SEANCES.PremierCours, SEANCES.DernierCours ) / 2, SEANCES.PremierCours )
			ELSE DATEADD( DAY, DATEDIFF( DAY, CONVENTIONS.ConventionDateFromMin, CONVENTIONS.ConventionDateToMax ) / 2, CONVENTIONS.ConventionDateFromMin )
		  END as SeancesMiParcoursDate
		, CASE
			WHEN COURS.SoldeToPlann = 0 THEN
				CASE
					WHEN DATEADD( DAY, DATEDIFF( DAY, SEANCES.PremierCours, SEANCES.DernierCours ) / 2, SEANCES.PremierCours ) < GETDATE() THEN 'Passee'
					ELSE ''
				END
			ELSE 
				CASE
					WHEN DATEADD( DAY, DATEDIFF( DAY, CONVENTIONS.ConventionDateFromMin, CONVENTIONS.ConventionDateToMax ) / 2, CONVENTIONS.ConventionDateFromMin ) < GETDATE() THEN 'Passee'
					ELSE ''
				END
		  END as SeancesMiParcoursPassée
		-- Date et contenu de la note la plus récente
		, NOTES.Label as LastNoteLabel
		, NOTES.Notes as LastNoteContent
		, NOTES.DayDate as LastNoteDate
		-- Note pédagogique manquante : non  / oui (avec date si oui ) -> SeancesIntraVars.NoShow ?
		, NOTES_PEDAGO_DUE.NotesPedagoDue
		, NOTES_PEDAGO_FOUND.NotesPedagoFound
		, ( NOTES_PEDAGO_DUE.NotesPedagoDue - NOTES_PEDAGO_FOUND.NotesPedagoFound ) as NotesPedagoManquantes
		-- les séances
		, ISNULL( SEANCES_PASSEES.SeancesCount, 0 ) as SeancesPassees
		-- Signature formateur manquante : non/ oui (avec date si oui)
		, ISNULL( SIGN_FORMATEUR_MANQUANTES.SignFormateurManquantes, 0 ) as SeanceSignFormateurManquantes
		-- stagiaires
		, COURS_STAGIAIRES.ID as CoursStagiaireID
		, COURS_STAGIAIRES.label as CoursStagiaireLabel
		, PERSONS.ID as PersonID
		, PERSONS.Label as PersonLabel
		, PERSONS.Civility as PersonCivility
		, PERSONS.Email as PersonEmail
		-- Signature stagiaire manquante : non / oui (avec date si oui )
		, ISNULL( SIGN_STAG_MANQUANTES.SignStagManquantes, 0 ) as StagiaireSignManquantes
		-- Absence stagiaire : pourcentage et nombre d'heures d'absence
		--, ISNULL( ABSENCES.AbsencesMinutes, 0 ) as StagiaireAbsencesMinutes
		--, ( ISNULL( ABSENCES.AbsencesMinutes, 0 ) * 100 / COURS.DureeCours ) as StagiaireAbsencesPercentMinutes
		, ISNULL( ABSENCES.AbsencesCount, 0 ) as StagiaireAbsencesCount
		, CASE
			WHEN SEANCES_PASSEES.SeancesCount IS NULL OR SEANCES_PASSEES.SeancesCount = 0 THEN ''
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
		-- Date rapport de progrès validé / à valider
		, CASE
			WHEN RAPPORT_VALIDE.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, RAPPORT_VALIDE.DayDate, 120 )
		  END as RapportProgresValide
		-- Questionnaire Début (QD) : date planifiée
		, CASE
			--WHEN QDPLANNED.DayDate IS NULL or QDPLANNED.DayDate < GETDATE() THEN ''
			WHEN QDPLANNED.DayDate IS NULL THEN '' --'(null)'
			WHEN QDPLANNED.DayDate > GETDATE() THEN '' --'(future)'
			WHEN QDEBUT.DayDate is not null THEN '' --'(done)'
			ELSE CONVERT( VARCHAR, QDPLANNED.DayDate, 120 )
		  END as QuestionnaireDebutDue
		-- Questionnaire Début (QD) : date renseigné
		-- Quest.ionnaire Début (QD) : non renseigné
		, CASE
			WHEN QDEBUT.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, QDEBUT.DayDate, 120 )
		  END as QuestionnaireDebutDone
		-- Questionnaire FIN (QF) : date planifié
		-- Questionnaire Fin (QF) : date renseigné (+ si possible note globale et si veut continuer Oui/Non)
		-- Questionnaire Fin (QF) : non renseigné
		, CASE
			WHEN QFIN.DayDate IS NULL THEN ''
			ELSE CONVERT( VARCHAR, QFIN.DayDate, 120 )
		  END as QuestionnaireFin
		, ISNULL( case QFIN.ReprendreFormation
			when -1 then 'Ne sais pas'
			when 0 then 'Oui'
			when 1 then 'Non'
		  end, '' ) as ReprendreFormation

		from ( select ID as CoursStagiaireID, CoursID from dbo.c_CoursStagiaires where CoursID in (
				-- les modules en cours, ou qui commencent dans moins de 1 mois, ou terminés depuis moins de 1 mois
				select ID from dbo.c_Cours where DateFrom < DATEADD(MONTH, +1, GETDATE()) and DateTo > DATEADD(MONTH, -1, GETDATE())
				-- 11128 -- 5 stagiaires x 30 séances
				-- 10987 -- notes pedago manquantes
		)) RES

		left join dbo.c_Cours COURS on COURS.ID = RES.CoursID
		left join dbo.c_CoursStagiaires COURS_STAGIAIRES on COURS_STAGIAIRES.ID = RES.CoursStagiaireID
		left join dbo.c_Centres CENTRES on CENTRES.ID = COURS.CentreID 
		left join dbo.c_Employees PEDAGO on PEDAGO.ID = COURS.RefPedagoID 
		left join dbo.c_Formules FORMULES on FORMULES.ID = COURS.FormuleID 
		left join dbo.c_Langues LANGUES on LANGUES.ID = COURS.LangueID 

		left join ( select C.CoursID, max(C.CompanyID) as CompanyID, max(C.CompanyName) as CompanyName,
			string_agg( C.Label, '/ ') as ConventionLabel, min( C.DateConv) as ConventionDateFromMin, max( C.DateTo) as ConventionDateToMax
			from dbo.c_ConventionsCours C group by C.CoursID ) CONVENTIONS on CONVENTIONS.CoursID = COURS.ID

		-- les seances planifiées
		left join ( select A.CoursID, min( A.DayDate ) as PremierCours, max( A.DayDate ) as DernierCours from dbo.c_SeancesInterVars A group by A.CoursID ) SEANCES on SEANCES.CoursID = COURS.ID

		-- content and date of most recent attached note
		left join (
			select A.CoursID, A.Label, A.Notes, A.DayDate, row_number() over ( partition by A.CoursID order by A.DayDate desc ) as rn
				from dbo.c_Notes A ) NOTES on NOTES.CoursID = RES.CoursID and rn=1

		-- les notes pédagogiques à renseigner par le formateur pour chaque séance
		-- la note est dûe si la logistique de la session dit qu'il y a un formateur
		-- la note est attachée à la séance, commune à tous les stagiaires participants
		left join ( select A.CoursID, count(*) as NotesPedagoDue from dbo.c_SeancesInterVars A
			inner join dbo.e_LogisticVarType B on B.Code = A.LogisticVarType and B.IsFormateur = 1 and A.DayDate < GETDATE()
			group by A.CoursID
				 ) NOTES_PEDAGO_DUE on NOTES_PEDAGO_DUE.CoursID = RES.CoursID

		left join ( select B.CoursID, COUNT(*) as NotesPedagoFound from dbo.c_SeancesInterVarPedagos A
			inner join dbo.c_SeancesInterVars B on B.ID = A.ID 
			where ISNULL( A.Label, '' ) <> '' or ISNULL( A.Remarques, '' ) <> '' or ISNULL( A.Conseils, '' ) <> '' or ISNULL( A.TravailPerso, '' ) <> ''
			group by B.CoursID ) NOTES_PEDAGO_FOUND on NOTES_PEDAGO_FOUND.CoursID = RES.CoursID

		-- les séances exécutées
		left join ( select A.CoursStagiaireID, count( A.DateHourFrom ) as SeancesCount
			from dbo.c_StagiairesSeancesInterVars A where A.DateHourFrom < GETDATE() group by A.CoursStagiaireID ) SEANCES_PASSEES on SEANCES_PASSEES.CoursStagiaireID = RES.CoursStagiaireID

		left join ( select A.CoursID, count( A.DayDate ) as SignFormateurManquantes
			from dbo.c_SeancesInterVars A
				inner join dbo.e_LogisticVarType B on B.Code = A.LogisticVarType
				where A.NoShow = 0 and A.DayDate < GETDATE() and A.FormateurID is not null and A.SignImage is null and B.IsFormateur = 1 group by A.CoursID ) SIGN_FORMATEUR_MANQUANTES on SIGN_FORMATEUR_MANQUANTES.CoursID = COURS.ID

		-- the stagiaire name
		left join dbo.c_Persons PERSONS on PERSONS.ID = COURS_STAGIAIRES.PersonID

		-- la présence du stagiaire
		left join ( select A.CoursStagiaireID, sum( A.NMinutes ) as AbsencesMinutes, count( A.DateHourFrom ) as AbsencesCount
			from dbo.c_StagiairesSeancesInterVars A where A.DateHourFrom < GETDATE() and A.TypePresence like 'AB%' group by A.CoursStagiaireID ) ABSENCES on ABSENCES.CoursStagiaireID = RES.CoursStagiaireID

		left join ( select A.CoursStagiaireID, count( A.DateHourFrom ) as SignStagManquantes
			from dbo.c_StagiairesSeancesInterVars A 
				inner join dbo.c_SeancesInterVars B on B.ID = A.SeanceInterVarID
				where A.DateHourFrom < GETDATE() and A.SignImage is null and A.TypePresence <> 'PRS' and A.TypePresence not like 'AB%' and B.NoShow = 0 and B.LogisticVarType <> 'ST'
				group by A.CoursStagiaireID ) SIGN_STAG_MANQUANTES on SIGN_STAG_MANQUANTES.CoursStagiaireID = RES.CoursStagiaireID

		-- les résultats, évaluations et questionnaires de début et de fin
		left join ( select A.CoursID, min( A.DateHourFrom ) as Evaluation from dbo.c_SeancesInterVars A where A.Label like '% (E)' group by A.CoursID ) EVALUATION on EVALUATION.CoursID = RES.CoursID

		left join ( select A.CoursStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_EvaluationsInters A group by A.CoursStagiaireID ) EVALS_INTRAS on EVALS_INTRAS.CoursStagiaireID = RES.CoursStagiaireID

		-- evaluation validée
		left join ( select A.CoursStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_EmailSents A where A.Label like 'Rapport de Progr%' group by A.CoursStagiaireID ) RAPPORT_VALIDE on RAPPORT_VALIDE.CoursStagiaireID = RES.CoursStagiaireID

		-- questionnaire de début: planned date
		-- le questionnaire de debut est planifié pour la troisième séance
		left join ( select CoursID, NSeance, DayDate
			from dbo.c_SeancesInterVars A ) QDPLANNED on QDPLANNED.CoursID = RES.CoursID and QDPLANNED.NSeance = 3

		left join ( select A.CoursStagiaireID, min( A.DayDate ) as DayDate
			from dbo.c_StagiaireSatisfactionStartsEcs A group by A.CoursStagiaireID ) QDEBUT on QDEBUT.CoursStagiaireID = RES.CoursStagiaireID

		left join ( select A.CoursStagiaireID, min( A.DayDate ) as DayDate, min( A.ReprendreFormation ) as ReprendreFormation
			from dbo.c_StagiaireSatisfactionsEcs A group by A.CoursStagiaireID ) QFIN on QFIN.CoursStagiaireID = RES.CoursStagiaireID
