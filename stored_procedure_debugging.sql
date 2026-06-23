-- ============================================================================
-- SQL Server Stored Procedure Debugging Guide
-- Real Production Issues and Solutions
-- Author: Hernan Rubio Pacheco
-- ============================================================================

-- ============================================================================
-- ISSUE #1: DUPLICATE INSERT PROBLEM
-- ============================================================================
-- BROKEN VERSION (finds duplicates):
CREATE PROCEDURE sp_ProcessEmployeePayment_BROKEN
    @EmployeeID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    -- PROBLEM: No WHERE clause - inserts ALL records instead of just this employee
    INSERT INTO PaymentHistory (EmployeeID, Amount, ProcessDate)
    SELECT EmployeeID, @Amount, GETDATE()
    FROM Employees;
    -- Result: 4,000+ records inserted instead of 1!
END;

-- FIXED VERSION:
CREATE PROCEDURE sp_ProcessEmployeePayment_FIXED
    @EmployeeID INT,
    @Amount DECIMAL(10,2)
AS
BEGIN
    BEGIN TRANSACTION
    BEGIN TRY
        -- FIX: Added WHERE clause to filter specific employee
        INSERT INTO PaymentHistory (EmployeeID, Amount, ProcessDate)
        SELECT EmployeeID, @Amount, GETDATE()
        FROM Employees
        WHERE EmployeeID = @EmployeeID;  -- KEY FIX
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;

-- ============================================================================
-- ISSUE #2: WRONG WHERE CLAUSE LOGIC
-- ============================================================================
-- BROKEN VERSION:
CREATE PROCEDURE sp_UpdateActiveEmployees_BROKEN
AS
BEGIN
    -- PROBLEM: Updates the WRONG employees (all except Active)
    UPDATE Employees
    SET Status = 'Active'
    WHERE Status != 'Active';  -- WRONG LOGIC
    -- Result: Sets all inactive to Active, but what about maintaining them?
END;

-- FIXED VERSION:
CREATE PROCEDURE sp_UpdateActiveEmployees_FIXED
AS
BEGIN
    BEGIN TRANSACTION
    BEGIN TRY
        -- FIX: Clearer logic - only update recently hired
        UPDATE Employees
        SET Status = 'Active'
        WHERE Status IN ('Pending', 'OnBoarding')
          AND DATEDIFF(DAY, HireDate, GETDATE()) <= 30;
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;

-- ============================================================================
-- ISSUE #3: CALCULATION ERROR
-- ============================================================================
-- BROKEN VERSION:
CREATE PROCEDURE sp_CalculateBonus_BROKEN
    @BaseSalary DECIMAL(10,2),
    @YearsOfService INT
AS
BEGIN
    DECLARE @Bonus DECIMAL(10,2);
    
    -- PROBLEM: Wrong calculation formula
    SET @Bonus = @BaseSalary * @YearsOfService / 100;  -- Missing parentheses
    -- Result: For $100K, 5 years = $5K (correct by accident)
    --         For $50K, 10 years = $5K (very wrong)
    
    SELECT @Bonus AS BonusAmount;
END;

-- FIXED VERSION:
CREATE PROCEDURE sp_CalculateBonus_FIXED
    @BaseSalary DECIMAL(10,2),
    @YearsOfService INT
AS
BEGIN
    DECLARE @Bonus DECIMAL(10,2);
    DECLARE @BonusRate DECIMAL(5,2);
    
    -- FIX: Clear logic with bonus tiers
    SET @BonusRate = CASE
        WHEN @YearsOfService >= 10 THEN 0.15  -- 15% for 10+ years
        WHEN @YearsOfService >= 5 THEN 0.10   -- 10% for 5+ years
        WHEN @YearsOfService >= 2 THEN 0.05   -- 5% for 2+ years
        ELSE 0.02  -- 2% for new employees
    END;
    
    SET @Bonus = @BaseSalary * @BonusRate;
    
    SELECT @Bonus AS BonusAmount;
END;

-- ============================================================================
-- ISSUE #4: MISSING TRANSACTION MANAGEMENT
-- ============================================================================
-- BROKEN VERSION:
CREATE PROCEDURE sp_TransferDepartment_BROKEN
    @EmployeeID INT,
    @NewDepartment NVARCHAR(100)
AS
BEGIN
    -- PROBLEM: No transaction - if UPDATE fails, records are inconsistent
    UPDATE Employees
    SET Department = @NewDepartment
    WHERE EmployeeID = @EmployeeID;
    
    -- What if this fails? Data corruption!
    INSERT INTO AuditLog (EmployeeID, Action, ActionDate)
    VALUES (@EmployeeID, 'Department Changed', GETDATE());
END;

-- FIXED VERSION:
CREATE PROCEDURE sp_TransferDepartment_FIXED
    @EmployeeID INT,
    @NewDepartment NVARCHAR(100)
AS
BEGIN
    BEGIN TRANSACTION
    BEGIN TRY
        -- FIX: Both operations succeed together or both fail together
        UPDATE Employees
        SET Department = @NewDepartment,
            LastModified = GETDATE()
        WHERE EmployeeID = @EmployeeID;
        
        INSERT INTO AuditLog (EmployeeID, Action, ActionDate, Details)
        VALUES (@EmployeeID, 'Department Changed', GETDATE(), @NewDepartment);
        
        COMMIT TRANSACTION;
        PRINT 'Department transfer completed successfully.';
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        PRINT 'Department transfer failed. All changes rolled back.';
        THROW;
    END CATCH
END;

-- ============================================================================
-- KEY LEARNINGS FOR DEBUGGING:
-- 1. Always use WHERE clauses - verify which records you're modifying
-- 2. Use transactions for multi-step operations
-- 3. Test calculations with multiple scenarios
-- 4. Wrap procedures in BEGIN TRY / BEGIN CATCH
-- 5. Use ROLLBACK to undo on error
-- 6. Write clear logic - future you will thank you
-- ============================================================================
