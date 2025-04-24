@echo off
	rem The Tools Project - Tools System and Working Paradigm for IT Production
	rem Copyright (C) 1998-2023 Pierre Wieser (see AUTHORS)
	rem Copyright (C) 2023-2025 PWI Consulting
	rem
	rem TheToolsProject is free software; you can redistribute it and/or
	rem modify it under the terms of the GNU General Public License as
	rem published by the Free Software Foundation; either version 2 of the
	rem License, or (at your option) any later version.
	rem
	rem TheToolsProject is distributed in the hope that it will be useful,
	rem but WITHOUT ANY WARRANTY; without even the implied warranty of
	rem MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
	rem General Public License for more details.
	rem
	rem You should have received a copy of the GNU General Public License
	rem along with TheToolsProject; see the file COPYING. If not,
	rem see <http://www.gnu.org/licenses/>.
	rem
	rem TTP boostrapping in a cmd environment

	setlocal EnableDelayedExpansion

	REM Default config directories
	set "default_dirs=C:\ProgramData\ttp.d %USERPROFILE%\.ttp.d"

	REM Allow override via command-line
	if "%~1"=="" (
		set "config_dirs=%default_dirs%"
	) else (
		set "config_dirs=%*"
	)

	REM Reset variables
	set "TTP_ROOTS="
	set "prepend_roots="
	set "append_roots="

	REM Load .conf files from specified directories
	for %%D in (%config_dirs%) do (
		for %%F in ("%%D\*.conf") do (
			if exist "%%F" (
				for /f "usebackq tokens=* delims=" %%L in ("%%F") do (
					set "line=%%L"
					REM Skip comments and empty lines
					if not "!line!"=="" if "!line:~0,1!" NEQ "#" (
						REM Handle lines starting with '-'
						if "!line:~0,1!"=="-" (
							set "line=!line:~1!"
							if defined prepend_roots (
								set "prepend_roots=!prepend_roots!;!line!"
							) else (
								set "prepend_roots=!line!"
							)
						) else (
							if defined append_roots (
								set "append_roots=!append_roots!;!line!"
							) else (
								set "append_roots=!line!"
							)
						)
					)
				)
			)
		)
	)

	REM Build TTP_ROOTS: prepend_roots ; append_roots
	if defined prepend_roots (
		if defined append_roots (
			set "TTP_ROOTS=!prepend_roots!;!append_roots!"
		) else (
			set "TTP_ROOTS=!prepend_roots!"
		)
	) else (
		set "TTP_ROOTS=!append_roots!"
	)

	REM Build PERL5LIB from TTP_ROOTS
	set "PERL5LIB="
	for %%D in (%TTP_ROOTS:;= %) do (
		if defined PERL5LIB (
			set "PERL5LIB=!PERL5LIB!;%%D\libexec\perl"
		) else (
			set "PERL5LIB=%%D\libexec\perl"
		)
	)

	REM Set TTP_NODE if not defined
	if not defined TTP_NODE (
		set "TTP_NODE=%COMPUTERNAME%"
	)

	REM Export and show
	set TTP_ROOTS=%TTP_ROOTS%
	set PERL5LIB=%PERL5LIB%
	set TTP_NODE=%TTP_NODE%

	@echo TTP_ROOTS: %TTP_ROOTS%
	@echo PERL5LIB : %PERL5LIB%
	@echo TTP_NODE : %TTP_NODE%

	endlocal & (
		set "TTP_ROOTS=%TTP_ROOTS%"
		set "PERL5LIB=%PERL5LIB%"
		set "TTP_NODE=%TTP_NODE%"
	)
