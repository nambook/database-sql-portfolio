-- ============================================================================
-- SQL Server Data Cleanup and Validation Suite
-- Purpose: Normalize and validate employee records at scale
-- Author: Hernan Rubio Pacheco
-- Date: 2026
-- ============================================================================
-- REAL PRODUCTION SCENARIO:
-- A customer database had 4,000+ employee records with inconsistent data:
-- - Duplicate names/IDs
-- - NULL values in critical fields
-- - Inconsistent data types
-- - Historical records not archived
-- This script resolved the issue using transactions and validation
-- ============================================================================

-- ENABLE ROLLBACK: Set @DryRun = 1 to test without making changes
DECLARE @DryRun BIT = 0; -- Change to 1 for testing

-- ============================================================================
-- STEP 1: IDENTIFY ISSUES (SELECT FIRST TO VALIDATE)
-- ============================================================================
SELECT 
    EmployeeID,
    FirstName,
    LastName,
    Email,
    Department,
    HireDate,
    Status,
    COUNT(*) AS DuplicateCount
FROM Employees
GROUP BY EmployeeID, FirstName, LastName, Email, Department, HireDate, Status
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC;

-- ============================================================================
-- STEP 2: VALIDATE DATA QUALITY ISSUES
-- ============================================================================
-- Find records with NULL values in critical fields
SELECT 
    EmployeeID,
    FirstName,
    LastName,
    Email,
    Department
FROM Employees
WHERE FirstName IS NULL 
   OR LastName IS NULL 
   OR Email IS NULL 
   OR Department IS NULL;

-- ============================================================================
-- STEP 3: DATA CLEANUP WITH TRANSACTION (ROLLBACK CAPABLE)
-- ============================================================================
BEGIN TRANSACTION

-- Remove duplicate records (keep first occurrence)
IF @DryRun = 0
BEGIN
    DELETE FROM Employees
    WHERE EmployeeID IN (
        SELECT EmployeeID
        FROM (
            SELECT 
                EmployeeID,
                ROW_NUMBER() OVER (PARTITION BY FirstName, LastName, Email ORDER BY HireDate) AS RN
            FROM Employees
        ) AS DuplicateCheck
        WHERE RN > 1
    );
    PRINT 'Duplicate records removed.';
END
ELSE
BEGIN
    PRINT '[DRY RUN] Would have removed duplicate records.';
END

-- Update NULL values with defaults
IF @DryRun = 0
BEGIN
    UPDATE Employees
    SET Department = 'Unassigned'
    WHERE Department IS NULL;
    
    UPDATE Employees
    SET Status = 'Active'
    WHERE Status IS NULL;
    
    PRINT 'NULL values updated with defaults.';
END
ELSE
BEGIN
    PRINT '[DRY RUN] Would have updated NULL values.';
END

-- ============================================================================
-- STEP 4: VALIDATE RESULTS
-- ============================================================================
IF @DryRun = 0
BEGIN
    SELECT 
        COUNT(*) AS TotalRecords,
        COUNT(DISTINCT EmployeeID) AS UniqueEmployees,
        COUNT(CASE WHEN FirstName IS NULL THEN 1 END) AS NullFirstNames,
        COUNT(CASE WHEN Department IS NULL THEN 1 END) AS NullDepartments
    FROM Employees;
    
    COMMIT TRANSACTION;
    PRINT 'Data cleanup completed successfully.';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT '[DRY RUN COMPLETE] No changes made. Review above SELECT statements.';
END

-- ============================================================================
-- STEP 5: SAMPLE CLEANED DATA
-- ============================================================================
SELECT TOP 20
    EmployeeID,
    FirstName,
    LastName,
    Email,
    Department,
    HireDate,
    Status
FROM Employees
ORDER BY EmployeeID;

-- ============================================================================
-- KEY LEARNINGS:
-- 1. Always use transactions for bulk changes
-- 2. Test with @DryRun = 1 first
-- 3. Validate before and after
-- 4. Document the issue and solution
-- 5. Get approval before removing data
-- ============================================================================
