#Requires -Version 5.1
# CANARY PROTOCOL NEGATIVE FIXTURE: intentionally violates the owned five-target guard.
# This branch must never merge. Its sole purpose is to prove CI rejects guard weakening.
$MaxTargets = 50
throw 'INTENTIONAL_CANARY_NEGATIVE_FIXTURE'
