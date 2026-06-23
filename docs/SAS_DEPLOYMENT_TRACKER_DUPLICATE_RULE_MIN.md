# SAS Deployment Tracker Duplicate Rule

Duplicate only when the same normalized identifier is explicitly marked deployed yes more than once in the Deployment Tracker.

Repeated identifier alone is not a duplicate.

## Required agent logic

1. Normalize the identifier.
2. Ignore blank and placeholder values.
3. Group tracker rows by normalized identifier.
4. Count only rows explicitly marked deployed yes.
5. Emit a duplicate exception only when that count is greater than one.

## Classification

- One deployed yes row: not duplicate.
- Multiple matching rows with zero deployed yes rows: not duplicate.
- Multiple matching rows with one deployed yes row: not duplicate.
- Multiple matching rows with more than one deployed yes row: duplicate exception.
- Blank or placeholder identifier: not eligible for duplicate detection.

## Review artifact requirement

When a duplicate exception is emitted, preserve workbook, sheet, row, cell, identifier field, identifier value, deployed yes count, and matching row count.
