@echo off
rem Tom-Production defines scheduled tasks for both:
rem - the "live" production
rem   > full backup on the morning
rem   > diff backups during the day (here every 2h)
rem - the "backup" production
rem   > monitor the "live" backups, transfert and restore each of them
rem
rem While two machines may run both the "live" workloads, it is OF THE PRIME IMPORTANCE that AT MOST ONE have the "backup" role (and the good one if possible)
rem Because the "backup" production will override its own databases with the "live" production backups, it must not be considered as "live" itself.
rem The above consideration is the main reason for having chosen "scheduled tasks" to maintain the distinction between "live" and "backup", because it is
rem a lot easier to enable/disable tasks than to go to update a JSON configuration file at the very bottom of tree of files...
rem
rem So, here all tasks required for "live" and "backup" are defined and default to be disabled. and this script can be safely run on both sides.
rem This script must be run with Administrator privileges in an Administrator command prompt session.

set WORKLOAD=C:\INLINGUA\Site\Commands\workload.cmd
set RUNNER=/RU %COMPUTERNAME%\inlingua-user /RP GRlCvlNazmGcvRL0a3Ow

rem TOM17

set JOB=tom17.live.morning
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 06:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom17.live.every.2h
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /XML "%~dp0\%JOB%.xml" /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom17.live.evening
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 23:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom17.backup
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 05:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

rem TOM21

set JOB=tom21.live.morning
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 06:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom21.live.every.2h
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /XML "%~dp0\%JOB%.xml" /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom21.live.evening
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 23:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom21.backup
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 05:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

rem TOM59

set JOB=tom59.live.morning
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 06:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom59.live.every.2h
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /XML "%~dp0\%JOB%.xml" /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom59.live.evening
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 23:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom59.live.monday
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC WEEKLY /D MON /ST 06:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom59.live.sunday
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC WEEKLY /D SUN /ST 23:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable

set JOB=tom59.backup
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 05:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Disable
