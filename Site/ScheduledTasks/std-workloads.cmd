@echo off
rem Standard workloads on all machines

set WORKLOAD=C:\INLINGUA\Site\Commands\workload.cmd
set RUNNER=/RU %COMPUTERNAME%\inlingua-user /RP GRlCvlNazmGcvRL0a3Ow

set JOB=daily.user
echo %JOB%
@schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "net user inlingua-user /active:yes" /SC DAILY /ST 04:59 /F /RU SYSTEM
schtasks /Change /TN Inlingua\%JOB% /Enable

set JOB=daily.morning
echo %JOB%
@schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 05:00 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Enable

set JOB=daily.evening
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC DAILY /ST 23:30 /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Enable

set JOB=startup
echo %JOB%
schtasks /Delete /TN Inlingua\%JOB% /F 1>NUL 2>NUL
schtasks /Create /TN Inlingua\%JOB% /TR "%WORKLOAD% %JOB%" /SC ONSTART /F %RUNNER%
schtasks /Change /TN Inlingua\%JOB% /Enable
