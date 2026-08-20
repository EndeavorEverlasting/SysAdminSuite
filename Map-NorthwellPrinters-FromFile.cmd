@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title SysAdminSuite - Northwell Printers From File

rem Human-friendly alias for the canonical batch mapper.
rem The batch launcher owns UAC, file creation/editing, validation, plan confirmation,
rem canonical mapping, proof, evidence, and exit-code propagation.
call "%~dp0Map-NorthwellPrinters-Batch.cmd"
exit /b %ERRORLEVEL%
