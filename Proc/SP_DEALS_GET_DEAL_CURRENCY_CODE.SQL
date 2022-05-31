
/*********************************************************************************************************************/
/* Procedure: [dbo].[SP_DEALS_GET_DEAL_CURRENCY_CODE] */
CREATE OR ALTER PROCEDURE [dbo].[SP_DEALS_GET_DEAL_CURRENCY_CODE]
	@ID INT,
	@TYPE INT,
	@RESULT CHAR(3) OUT,
	@TRACE BIT = 0
AS
	IF (@TYPE = 1)
		SELECT @RESULT = UI_CURRENCY_CODE FROM RAZPREG_TA WITH(NOLOCK) WHERE ROW_ID = @ID
	--ELSE IF (@TYPE = 2)
	--	SELECT @RESULT...
	ELSE
		SET @RESULT = 'X'
GO