/***************************************************************************************************************/
-- ���          : ���� �����
-- ���� � ���   : 2020/06/07
-- ������       : Support Task 282601
-- ������������ : Test Automation - 
-- ��������     : ��������� �� ����������� ������ �� ������������ �� ��� �� �����
-- ���������    : ����
/***************************************************************************************************************/

/*********************************************************************************************************************/
/* Procedure: [dbo].[SP_TAXES_CALCULATE_PREV_COMMON_TA] -> ver.1.0.1 2022/05/31 */
/* ver.1.0.2 2022/06/07 - ������� ���� � ��� �������� �� ������� */
/* ver.1.0.3 2022/06/08 - ��� ���������� �� ���������� �������� �������� ����� � SYS_LOG_PROC */
CREATE OR ALTER PROCEDURE [dbo].[SP_TAXES_CALCULATE_PREV_COMMON_TA]
(
	@ROW_ID INT
,	@RESULT_SUM VARCHAR(255) = NULL OUT
,	@RESULT_CCY VARCHAR(8) = NULL OUT
,	@UPDATE_REGISTER BIT = 1
,	@DATE DATE = NULL
,	@TRACE BIT = 0
)
AS
BEGIN
	/* *************************************************************************************************************** */
	/* �������� �� ����������� �� �����������:
		- @ROW_ID INT - ID �� �������� ������ ( ������ ��������� )
		- @RESULT_SUM - ����������� ���� �� ������� ( ������ ��������� )
		- @RESULT_CCY - ������ � ����� � ��������� ���� ( ������ ��������� )
		- @UPDATE_REGISTER BIT - ���� ��������� ���� �� �� ����� ������������ �� �� ��������� ( ������ ��������� )
		- @DATE DATE  - ���� - ����� ���� ������ ��������� � ����� �� ������������ �� �������� ���� ( ������ ��������� )
		- @TRACE BIT  - ���� �� ����������	
	****************************************************************************************************************** */
	IF (@DATE IS NULL)
		SET @DATE = CAST(GETDATE() AS DATE)

	DECLARE @REF_ID		INT = -1
	DECLARE @DEAL_TYPE	INT = -1
	DECLARE @TAX_CODE	INT = -1
	DECLARE @PREF_CODE	INT = -1
	DECLARE @UI_SUM		FLOAT = 0
	DECLARE @TA_TYPE	VARCHAR(50)
	DECLARE @Msg 		nvarchar(2000) = N'',@Sql nvarchar(2000) = N'';

	SELECT 	@REF_ID		= [REF_ID]
		, 	@DEAL_TYPE	= [DEAL_TYPE]
		,	@TAX_CODE	= ISNULL([TAX_CODE], 0)
		,	@PREF_CODE	= ISNULL([PREF_CODE], 0)
		,	@UI_SUM		= CONVERT(FLOAT, REPLACE([UI_SUM], ' ', ''))
		,	@TA_TYPE	= [TA_TYPE]
	FROM dbo.[PREV_COMMON_TA] WITH(NOLOCK) 
	WHERE [ROW_ID] = @ROW_ID

	DECLARE	@DEAL_CURRENCY_CODE CHAR(3) /* ������ �� ��������� ������ */
		,	@TAX_CURRENCY VARCHAR(4)	/* ������ �� ������� */
	;
	EXEC dbo.[SP_DEALS_GET_DEAL_CURRENCY_CODE] @REF_ID, @DEAL_TYPE, @DEAL_CURRENCY_CODE OUT
	;

	DECLARE @TypePref varchar(64) = 'Pref'
		,	@TypeTax  varchar(64) = 'Tax'
		,	@X_CCY	  varchar(4)  = 'X'
		,	@CorrTaxServices int = 3 /* eTaxServices (3) - ���������� �� ����� */
	;	

	/* ������ � ����� �� �� ����� �������, �� ��������� ������ ��� �������� �� �������� �� ���������� */
	DECLARE @COLLECT_CURRENCY_CODE CHAR(3)
		= 	( SELECT [CURRENCY] FROM dbo.[DEALS_CORR_TA] WITH(NOLOCK) 
				WHERE	[REF_ID]		= @REF_ID 
					AND [TA_TYPE]		= @TA_TYPE 
					AND [UI_DEAL_TYPE] 	= @DEAL_TYPE 
					AND [DB_CORR_TYPE]	= @CorrTaxServices /* 3 - ���������� �� �����*/ );

	IF (@COLLECT_CURRENCY_CODE IS NULL)
		SET @COLLECT_CURRENCY_CODE = @DEAL_CURRENCY_CODE

	DECLARE @TAX_COMMISSIONS_TABLE  TABLE( [ROW_ID] INT, [COMMISSION_ORDER] INT, [TAX_CURRENCY] VARCHAR(4))
	;

	DECLARE @ACCUMULATED_AMOUNT FLOAT = 0
	DECLARE @ACCUMULATED_TAX FLOAT = 0
	DECLARE @TEMP_RESULT FLOAT = 0

	IF (@PREF_CODE > 0)
	BEGIN

		INSERT INTO @TAX_COMMISSIONS_TABLE
			SELECT [ROW_ID], [COMMISSION_ORDER], [CURRENCY] FROM dbo.[TAXES_INFO_COMMISSION_TA] WITH(NOLOCK)
			WHERE [TAX_CODE] = @PREF_CODE
				AND [TYPE] = @TypePref
				AND [IS_DEFAULT_CURRENCY] = 1
			ORDER BY [COMMISSION_ORDER]

		IF EXISTS (SELECT * FROM dbo.[TAXES_INFO_TA] WITH(NOLOCK) WHERE [PREF_PLAN_BASE_ON_DAILY_TURNOVER] > 0 AND [CODE] = @PREF_CODE AND [TYPE] = @TypePref)
		BEGIN

			SELECT 	@ACCUMULATED_AMOUNT = SUM(CONVERT(FLOAT, REPLACE([A].[UI_SUM], ' ', '')))
				,	@ACCUMULATED_TAX	= SUM([A].[TAX_SUM])
			FROM dbo.[PREV_COMMON_TA] AS [A] WITH(NOLOCK)
			INNER JOIN dbo.[PREV_COMMON_TA] AS [B] WITH(NOLOCK)
				ON	[A].[REF_ID] = [B].[REF_ID]
				AND [A].[DEAL_TYPE] = [B].[DEAL_TYPE]
			WHERE [B].[ROW_ID] = @ROW_ID
				AND [A].[RUNNING_ORDER]	< [B].[RUNNING_ORDER]
				AND [A].[PREF_CODE]		= [B].[PREF_CODE]
				AND @DATE = CAST(A.TEST_STATUS_HIST AS DATE)
		END
		ELSE
		BEGIN
			select	@Sql = N'SELECT * FROM dbo.[TAXES_INFO_TA] WITH(NOLOCK) WHERE [PREF_PLAN_BASE_ON_DAILY_TURNOVER] > 0 AND [CODE] = @PREF_CODE AND [TYPE] = Pref'
				,	@Msg = 'Not found preference with ID: '+str(@PREF_CODE,len(@PREF_CODE),0)
						+', @PREF_CODE: '			+ str(@PREF_CODE,len(@PREF_CODE),0)
						+', @ROW_ID: '				+ str(@ROW_ID,len(@ROW_ID),0)
						+', @TAX_CODE: '			+ str(@TAX_CODE ,len(@TAX_CODE),0)						
						+', @TA_TYPE: '				+ @TA_TYPE
						+', @UI_SUM: '				+ LTRIM(STR(@UI_SUM, 20, 2))						
						+', @DEAL_TYPE: '			+ str(@DEAL_TYPE,len(@DEAL_TYPE),0)
						+', @DEAL_CURRENCY_CODE: '	+ @DEAL_CURRENCY_CODE
						+', @COLLECT_CURRENCY_CODE:'+ @COLLECT_CURRENCY_CODE
					;
			exec dbo.[SP_SYS_LOG_PROC] @@PROCID, @Sql, @Msg;
			if @TRACE = 1 print( @Msg );			
		END

		SET @ACCUMULATED_TAX = DBO.TRANS_VAL_TO_VAL_TA(@ACCUMULATED_TAX, @COLLECT_CURRENCY_CODE, @DEAL_CURRENCY_CODE)

		SELECT	@TEMP_RESULT  = SUM( dbo.FN_TAXES_CALCULATE_PREFFERENCE_TA( [ROW_ID], @UI_SUM, ISNULL(@ACCUMULATED_AMOUNT, 0), ISNULL(@ACCUMULATED_TAX, 0), @DEAL_CURRENCY_CODE) )
			,	@TAX_CURRENCY = MIN( case when [TAX_CURRENCY] = @X_CCY then @DEAL_CURRENCY_CODE else [TAX_CURRENCY] end )
		FROM @TAX_COMMISSIONS_TABLE

	END
	ELSE IF (@TAX_CODE > 0)
	BEGIN

		INSERT INTO @TAX_COMMISSIONS_TABLE
			SELECT [ROW_ID], [COMMISSION_ORDER], [CURRENCY] FROM dbo.[TAXES_INFO_COMMISSION_TA] WITH(NOLOCK)
			WHERE [TAX_CODE] = @TAX_CODE
				AND [TYPE] = @TypeTax
				AND [IS_DEFAULT_CURRENCY] = 0
				AND [CURRENCY] = @DEAL_CURRENCY_CODE
			ORDER BY [COMMISSION_ORDER]

		IF NOT EXISTS (SELECT TOP 1 * FROM @TAX_COMMISSIONS_TABLE)
			INSERT INTO @TAX_COMMISSIONS_TABLE
				SELECT [ROW_ID], [COMMISSION_ORDER], [CURRENCY] FROM dbo.[TAXES_INFO_COMMISSION_TA] WITH(NOLOCK)
				WHERE [TAX_CODE] = @TAX_CODE
					AND [TYPE]	 = @TypeTax
					AND [IS_DEFAULT_CURRENCY] = 1
				ORDER BY [COMMISSION_ORDER]

		IF EXISTS (SELECT * FROM dbo.[TAXES_INFO_TA] WITH(NOLOCK) WHERE [ACUMULATIVE_TAX] > 0 AND [CODE] = @TAX_CODE AND [TYPE] = @TypeTax)
		BEGIN

			SELECT 	@ACCUMULATED_AMOUNT = SUM(CONVERT(FLOAT, REPLACE([A].[UI_SUM], ' ', '')))
				,	@ACCUMULATED_TAX	= SUM([A].[TAX_SUM])
			FROM dbo.[PREV_COMMON_TA] AS [A] WITH(NOLOCK)
			INNER JOIN dbo.[PREV_COMMON_TA] AS [B] WITH(NOLOCK)
				ON	[A].REF_ID = [B].[REF_ID]
				AND [A].DEAL_TYPE = [B].[DEAL_TYPE]
			WHERE [B].[ROW_ID] = @ROW_ID
				AND [A].[RUNNING_ORDER] < [B].[RUNNING_ORDER]
				AND [A].[TAX_CODE] = [B].[TAX_CODE]
				AND @DATE = CAST([A].[TEST_STATUS_HIST] AS DATE)
		END

		SET @ACCUMULATED_TAX = dbo.TRANS_VAL_TO_VAL_TA(@ACCUMULATED_TAX, @COLLECT_CURRENCY_CODE, @DEAL_CURRENCY_CODE)

		SELECT	@TEMP_RESULT = SUM( dbo.FN_TAXES_CALCULATE_COMMISSION_TA( [ROW_ID], @UI_SUM, ISNULL(@ACCUMULATED_AMOUNT, 0), ISNULL(@ACCUMULATED_TAX, 0), @DEAL_CURRENCY_CODE) )
			,	@TAX_CURRENCY = MIN(case when [TAX_CURRENCY] = @X_CCY then @DEAL_CURRENCY_CODE else [TAX_CURRENCY] end)
		FROM @TAX_COMMISSIONS_TABLE

	END

	SELECT	@RESULT_SUM = LTRIM(STR(@TEMP_RESULT, 20, 2))
		,	@RESULT_CCY = @TAX_CURRENCY
	;

	IF @TRACE = 1 OR @RESULT_SUM IS NULL OR @RESULT_CCY IS NULL
	BEGIN 
		select	@Sql = str(@ROW_ID,len(@ROW_ID),0)
			,	@Msg = N'Calculated tax amout: '+ IsNull(@TAX_CURRENCY,'null') +' ' + case when @TEMP_RESULT is null then 'null' else LTRIM(STR(@TEMP_RESULT, 20, 2)) end
					+', @TA_TYPE: '				+ IsNull(@TA_TYPE,'null')
					+', @TAX_CODE: '			+ IsNull(str(@TAX_CODE ,len(@TAX_CODE),0), 'null')
					+', @PREF_CODE: '			+ IsNull(str(@PREF_CODE,len(@PREF_CODE),0), 'null')
					+', @DEAL_TYPE: '			+ IsNull(str(@DEAL_TYPE,len(@DEAL_TYPE),0), 'null' )
					+', @UI_SUM: '				+ LTRIM(STR(IsNull(@UI_SUM,-1), 20, 2))
					+', @DEAL_CURRENCY_CODE: '	+ IsNull(@DEAL_CURRENCY_CODE, 'null')
					+', @ACCUMULATED_AMOUNT: '	+ IsNull(LTRIM(STR(@ACCUMULATED_AMOUNT, 20, 2)), 'null')
					+', @ACCUMULATED_TAX: '		+ IsNull(LTRIM(STR(@ACCUMULATED_TAX, 20, 2)), 'null')
					+', @COLLECT_CURRENCY_CODE:'+ IsNull(@COLLECT_CURRENCY_CODE, 'null')
		;
		exec dbo.[SP_SYS_LOG_PROC] @@PROCID, @Sql, @Msg;
		IF @TRACE = 1 PRINT( @Msg );
	END

	IF (@UPDATE_REGISTER = 1)
		UPDATE [PREV_COMMON_TA]
			SET [TAX_SUM]		= @TEMP_RESULT
			,	[TAX_CURRENCY]	= @RESULT_CCY
		WHERE [ROW_ID] = @ROW_ID

	RETURN 0;
END
GO
