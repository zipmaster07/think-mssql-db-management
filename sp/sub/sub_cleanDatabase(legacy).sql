USE [dbAdmin]
GO

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'sub_cleanDatabase')
	DROP PROCEDURE [dbo].[sub_cleanDatabase];
GO

CREATE PROCEDURE [dbo].[sub_cleanDatabase](
	@cleanDbName	nvarchar(128)
	,@thkVersion	numeric(2,1) = 7.3
	,@tempTableId	int
)
AS
/*
**	Global variables
*/
DECLARE	@dateTimeOverride		datetime
		,@printMessage			nvarchar(4000)
		,@errorMessage			nvarchar(4000)
		,@errorNbr				int
		,@errorSeverity			int
		,@sql					nvarchar(4000);

/*
**	Credit Card id_nbr/reference number variables.  These are used when updating the payment table
*/
DECLARE @cybSrc50Visa				varchar(250) 
		,@cybSrc50MasterCard		varchar(250) 
		,@cybSrc50Amex				varchar(250) 
		,@cybSrc50Discover			varchar(250) 
		,@cybSrc50Solo				varchar(250) 
		,@cybSrc50Switch			varchar(250) 
		,@cybSrc50ValueLink			varchar(250) 

		,@cybSrcOldVisa				varchar(250) 
		,@cybSrcOldMasterCard		varchar(250) 
		,@cybSrcOldAmex				varchar(250) 
		,@cybSrcOldDiscover			varchar(250) 
		,@cybSrcOldSolo				varchar(250) 
		,@cybSrcOldSwitch			varchar(250) 
		,@cybSrcOldValueLink		varchar(250) 

		,@cybSrcSecVisa				varchar(250) 
		,@cybSrcSecMasterCard		varchar(250) 
		,@cybSrcSecAmex				varchar(250) 
		,@cybSrcSecDiscover			varchar(250) 
		,@cybSrcSecSolo				varchar(250) 
		,@cybSrcSecSwitch			varchar(250) 
		,@cybSrcSecValueLink		varchar(250) 

		,@cybSrcSecSoapVisa			varchar(250) 
		,@cybSrcSecSoapMasterCard	varchar(250) 
		,@cybSrcSecSoapAmex			varchar(250) 
		,@cybSrcSecSoapDiscover		varchar(250) 
		,@cybSrcSecSoapSolo			varchar(250) 
		,@cybSrcSecSoapSwitch		varchar(250) 
		,@cybSrcSecSoapValueLink	varchar(250) 

		,@payFlowProVisa			varchar(250) 
		,@payFlowProMasterCard		varchar(250) 
		,@payFlowProAmex			varchar(250) 
		,@payFlowProDiscover		varchar(250) 
		,@payFlowProSolo			varchar(250) 
		,@payFlowProSwitch			varchar(250) 
		,@payFlowProValueLink		varchar(250) 

		,@payFlowProSecVisa			varchar(250) 
		,@payFlowProSecMasterCard	varchar(250) 
		,@payFlowProSecAmex			varchar(250) 
		,@payFlowProSecDiscover		varchar(250) 
		,@payFlowProSecSolo			varchar(250) 
		,@payFlowProSecSwitch		varchar(250) 
		,@payFlowProSecValueLink	varchar(250) 

		,@authVisa					varchar(250) 
		,@authMasterCard			varchar(250) 
		,@authAmex					varchar(250) 
		,@authDiscover				varchar(250) 
		,@authSolo					varchar(250) 
		,@authSwitch				varchar(250) 
		,@authValueLink				varchar(250) 

		,@paymentechVisa			varchar(250) 
		,@paymentechMasterCard		varchar(250) 
		,@paymentechAmex			varchar(250) 
		,@paymentechDiscover		varchar(250) 
		,@paymentechSolo			varchar(250) 
		,@paymentechSwitch			varchar(250) 
		,@paymentechValueLink		varchar(250) 

		,@payPalVisa				varchar(250) 
		,@payPalMasterCard			varchar(250) 
		,@payPalAmex				varchar(250) 
		,@payPalDiscover			varchar(250) 
		,@payPalSolo				varchar(250) 
		,@payPalSwitch				varchar(250) 
		,@payPalValueLink			varchar(250) 

		,@westPacVisa				varchar(250) 
		,@westPacMasterCard			varchar(250) 
		,@westPacAmex				varchar(250) 
		,@westPacDiscover			varchar(250) 
		,@westPacSolo				varchar(250) 
		,@westPacSwitch				varchar(250) 
		,@westPacValueLink			varchar(250) 

		,@litleVisa					varchar(250) 
		,@litleMasterCard			varchar(250) 
		,@litleAmex					varchar(250) 
		,@litleDiscover				varchar(250) 
		,@litleSolo					varchar(250) 
		,@litleSwitch				varchar(250) 
		,@litleValueLink			varchar(250) 

		,@optimalVisa				varchar(250) 
		,@optimalMasterCard			varchar(250) 
		,@optimalAmex				varchar(250) 
		,@optimalDiscover			varchar(250) 
		,@optimalSolo				varchar(250) 
		,@optimalSwitch				varchar(250) 
		,@optimalValueLink			varchar(250);


/*
**	Credit card id number variables.  These are used when updating the payment_account table
*/
DECLARE @cybSrcSecVisaCC			varchar(250) 
		,@cybSrcSecMasterCardCC		varchar(250) 
		,@cybSrcSecAmexCC			varchar(250) 
		,@cybSrcSecDiscoverCC		varchar(250) 
		,@cybSrcSecSoloCC			varchar(250) 
		,@cybSrcSecSwitchCC			varchar(250) 
		,@cybSrcSecValueLinkCC		varchar(250) 

		,@cybSrcSecSoapVisaCC		varchar(250) 
		,@cybSrcSecSoapMasterCardCC	varchar(250) 
		,@cybSrcSecSoapAmexCC		varchar(250) 
		,@cybSrcSecSoapDiscoverCC	varchar(250) 
		,@cybSrcSecSoapSoloCC		varchar(250) 
		,@cybSrcSecSoapSwitchCC		varchar(250) 
		,@cybSrcSecSoapValueLinkCC	varchar(250) 

		,@payFlowProSecVisaCC		varchar(250) 
		,@payFlowProSecMasterCardCC	varchar(250) 
		,@payFlowProSecAmexCC		varchar(250) 
		,@payFlowProSecDiscoverCC	varchar(250) 
		,@payFlowProSecSoloCC		varchar(250) 
		,@payFlowProSecSwitchCC		varchar(250) 
		,@payFlowProSecValueLinkCC	varchar(250) 

		,@litleVisaCC				varchar(250) 
		,@litleMasterCardCC			varchar(250) 
		,@litleAmexCC				varchar(250) 
		,@litleDiscoverCC			varchar(250) 
		,@litleSoloCC				varchar(250) 
		,@litleSwitchCC				varchar(250) 
		,@litleValueLinkCC			varchar(250) 

		,@optimalVisaCC				varchar(250) 
		,@optimalMasterCardCC		varchar(250) 
		,@optimalAmexCC				varchar(250) 
		,@optimalDiscoverCC			varchar(250) 
		,@optimalSoloCC				varchar(250) 
		,@optimalSwitchCC			varchar(250) 
		,@optimalValueLinkCC		varchar(250) 

		,@nonTokenizedVisaCC		varchar(250) 
		,@nonTokenizedMasterCardCC	varchar(250) 
		,@nonTokenizedAmexCC		varchar(250) 
		,@nonTokenizedDiscoverCC	varchar(250) 
		,@nonTokenizedSoloCC		varchar(250) 
		,@nonTokenizedSwitchCC		varchar(250) 
		,@nonTokenizedValueLinkCC	varchar(250);


SET @dateTimeOverride = GETDATE()

SET @cybSrc50Visa = 'w0WBENNN66kBKgugwjJVhIGGls9eLhDl/UXoy2PLhZwNClqR1LUDumvvNWfwtgo+xCJ5ANYgw7pU' + char(13) + char(10) + 'iwEh3dcsomA0cdQU6MdQk3tV/lO4mW0s+4xuyE2lg1xbV63J94YoeFLwjcSf36QTHivxiqbeLQim' + char(13) + char(10) + 'Iy5jZ0yvN3smcPVY8Vo'
SET @cybSrc50MasterCard	= 'PM52ZTw/8UCqq5owFMJhLYC6WuiOEDWN4F04aip1tikp4mWDbGlJ2pWeojkKtWWC+l5Fminm+kq1' + char(13) + char(10) + 'YZwCXX1Yh+OZ/l9ZYEg3UGlNQj12scE3C30pR2iO6kVTYSbQp3zDM56W+msyrWfx8taftAmTOH6w' + char(13) + char(10) + 'bEWev36ygPqVidb9zMI'
SET @cybSrc50Amex = '+vuGVLEu/QHBk4lYsu2zEmDs2LUtJq4LKlSEQmUvU5dAj9+i0zaPkqosF4vth9avIcw83cEzKgID' + char(13) + char(10) + 'pitNTTbAlAZJ4Ykjw3W0vISzGwaDFslyYY6oRcvanpA+uCuIf4Lh9PuHnKqtKBZeGZrlAxq9O6Cx' + char(13) + char(10) + 'D3ktJLjT7VeK9848gS0'
SET @cybSrc50Discover = '1ua23D5vv3Ej+7DaIgHqZZFowkHbx2Y9npwWd7C2S2cw66y2lxA3qVC6lmK9gFNcK2ro/rWDV40s' + char(13) + char(10) + '8gyu2ps6USy0PVKSmZwwUPgPXvDtG3pmc+X9KC1KOfgU7PhkW3H5yq0Inuco9fskNFfFj+tjpqpA' + char(13) + char(10) + 'G4lFQa926ddVKygugko'
SET @cybSrc50Solo = ''
SET @cybSrc50Switch = ''
SET @cybSrc50ValueLink = ''

SET @cybSrcOldVisa = 'Mg/lIO5riRbiF9RAjbWxFauqQePzSYVPmVO4Mz9sVRxiyT591z5BVbMqoFehhKLccnwlpfF0x60U' + char(13) + char(10) + 'THIHrY31K2T0/J8YufWzkVHavYm6mLQwCRv+7TwZt7LV2NfvUUW4qbphzjREUqy00vVLP3HJmA4a' + char(13) + char(10) + 'qfSzkV9gvj44zxP/4YQ'
SET @cybSrcOldMasterCard = 'FA/4KdEwzdHmPPoHHxUCBPGBrJ4E89y0tPnbidLINUyPHrBY8TetVlBX4nJhCUwFPHn3xeU5jMhU' + char(13) + char(10) + '7yZZpcR/iBz39oRTll2ij+iYVtYIZpBRj/2oTsNR1fIu14a0tA9oBF1EcLViV0VfMUBGBNJvBhwP' + char(13) + char(10) + 'Fx0E/F4oKOHUt8XYE8c'
SET @cybSrcOldAmex = 'VYhFwt81IFSGOpNE2E44FEgW0sfQTlmiruv57mqYelcoqgXgHpyqYrOvjryfITaPsjhUspkn8sAL' + char(13) + char(10) + '1WEHcQo6dRZIzH7+Hv9z+rtfy0izgDaOvD48oYma6iEKAsvtxOCqGhBDDS3pLsFOgwjJtJNnz9vJ' + char(13) + char(10) + 'g3ED/hyjSp2FhPCSLmE'
SET @cybSrcOldDiscover = 'dnXa3QW9ohj4qJ6xNKWyg5e/CiNM9Gr7daGcupWNlZUxbfjNRSx8UWOrFfnKLVD4yqlOTO7O8LZt' + char(13) + char(10) + '8KoA9Wfg1i7J9LLadeTIrTYrO8VpRjv3LeCCEkqgbfPhaW3EwkQVPwxPCHx3k/K3tX4pHczao9GB' + char(13) + char(10) + 'NE0wgd4kemj+1cptJcM'
SET @cybSrcOldSolo = ''
SET @cybSrcOldSwitch = ''
SET @cybSrcOldValueLink = ''

SET @cybSrcSecVisa = '3426531851040176056428||Ahj//wSRc4FdJ/RWy1DYICmrBw0ZMm7lk5T9mBLYMwBT9mBLYMzSB13ARMQyaSX+gWx6J2GBORc4FdJ/RWy1DYAAzjZI'
SET @cybSrcSecMasterCard = '3426534873180176056442||Ahj//wSRc4FyoTHxHgD0ICmrFg0ZMm7hsxT9teA8OECT9teA8OHSB13ARMQyaSX+gWx6J2GEyRc4FyoTHxHgD0AA3C6b'
SET @cybSrcSecAmex = '3426536079180176056470||Ahj//wSRc4F7MuV0UMEsICmrBo0ZMm7lszT9XHgByADT9XHgByDSB13ARMQyaSX+gWx6J2GDORc4F7MuV0UMEsAA2Q4s'
SET @cybSrcSecDiscover = '3426536367740176056470||Ahj//wSRc4F9P8is6IEsICmrFi0ZMm7lg0T9xMbuU8ET9xMbuU/SB13ARMQyaSX+gWx6J2GBqRc4F9P8is6IEsAAggDX'
SET @cybSrcSecSolo = ''
SET @cybSrcSecSwitch = ''
SET @cybSrcSecValueLink = ''

SET @cybSrcSecSoapVisa = '3426536567430176056442||Ahj//wSRc4F+qwST8Ej0ICmrBo0ZMm7ls2T9XHgB04BT9XHgB07SB13ARMQyaSX+gWx6J2GBORc4F+qwST8Ej0AAfC3s'
SET @cybSrcSecSoapMasterCard = '3426536719750176056442||Ahj//wSRc4F/wBYa7Ej0ICmrFg0ZMm7hs0T9teA8W0CT9teA8W3SB13ARMQyaSX+gWx6J2GEyRc4F/wBYa7Ej0AAyiYX'
SET @cybSrcSecSoapAmex = '3426536825890176056428||Ahj//wSRc4GAgSdk6njYICmrBq0ZMm7ZuyT9a16z7UDT9a16z7XSB13ARMQyaSX+gWx6J2GDORc4GAgSdk6njYAA1y+7'
SET @cybSrcSecSoapDiscover = '3426536911230176056470||Ahj//wSRc4GBHGLtr6ksICmrBy0ZMm7hs3T9pvmJpEET9pvmJpHSB13ARMQyaSX+gWx6J2GBqRc4GBHGLtr6ksAAowDZ'
SET @cybSrcSecSoapSolo = ''
SET @cybSrcSecSoapSwitch = ''
SET @cybSrcSecSoapValueLink = ''

SET @payFlowProVisa = '3o3KJtWOkGWw23sgeyCz5Ypnrf8RF6SybL9sR4tvOMIKMZJFzI46bUOvuZInqciUqd4oDNZx1Jyt' + char(13) + char(10) + 'R7V5vL/Nc64yB8hOrgrDQUc75GzKIhgZGE5nIoHuD4WDSozoY5w9EEG6HSLctX0SBv5tNkUHswBH' + char(13) + char(10) + 'pGuu7X0PCzsH3nzzGs0'
SET @payFlowProMasterCard = 'weZeFT9fjBXLrzs7Bk5RpqtJn2GkBZ7kO32m4EQj82jc91dQYb9mzFWVpQnNKKC/2Wr3DDU5O3uU' + char(13) + char(10) + '46domWkwf8U8EPz+dfW8uxcVrNtC5UvXtRxfYFDBK76iuGlwXTVk66DKbw7JMOlrRiD2J96WOuga' + char(13) + char(10) + 'ftANNZhvMYD2aWX5WM8'
SET @payFlowProAmex = 'HMdPMfCBZ7O/i9LCb1mAKeQ8b60CoYkgNU/w/ZMLnmVslcdAgA/ridGZKFue/STofugoqdiEmBXI' + char(13) + char(10) + '2FlyJrLcQ+edwXts3IYcfdM9PorIxWSbziQoC2iYfllP7FAaPxzwleXPln+oEcGsI0Tyz03abNDz' + char(13) + char(10) + 'BWxEUBU4wLbR+MZVsAI'
SET @payFlowProDiscover = 'zlRD64LpzQ1/rFp0ZKJEGegkR2aOiJX+wXB/0hJjSdwr9MaFgSzNzbS4BK2tvgSOE/gBTgQ2lE1i' + char(13) + char(10) + 'bqSaGS1v6eOSCIFawm+E8kwbXV0AIorsB0V3oS3a1Jq7cc+BCon4HFdNDg+6zVXnBBSOpHMTPghw' + char(13) + char(10) + 'WysYEjec6zgEI45Mi20'
SET @payFlowProSolo = ''
SET @payFlowProSwitch = ''
SET @payFlowProValueLink = ''

SET @payFlowProSecVisa = 'V24C2B9F395A'
SET @payFlowProSecMasterCard = 'V34C2BA428E8'
SET @payFlowProSecAmex = 'V25C2B9F39E1'
SET @payFlowProSecDiscover = 'V34C2BA42969'
SET @payFlowProSecSolo = ''
SET @payFlowProSecSwitch = ''
SET @payFlowProSecValueLink = ''

SET @authVisa = 'm9kOg4yntX05lVVJR+Y91cX274YZtqME2TnO9x0AuvleeCI1309fnn0PKYk/jMzK7th9muhPS98R' + char(13) + char(10) + '5T13mWsHR7MherCLsIZSm644HtIEQ/RpE5EtZu4+vekVdmj1TboOoA8Z578nItStwY69ONyKidj3' + char(13) + char(10) + 'AvAmhFSZKPddynNVhGU'
SET @authMasterCard = 'RGI4rogEVL9ew0arpdxY+vHXNOJvDtuOjhwJnN5xNwl5elATWDc/mXzNj59/AYVEbeIxhK2l5Lg9' + char(13) + char(10) + 'DD4/ev9d1orFgq0wfDx4HjfiFtFmq1V2bkOGvQuWZ2yzt5tr44J4oJ75IrSrEp978paI4ER1E0qE' + char(13) + char(10) + 'LtSMmWljAKoPQFVbLrU'
SET @authAmex = 'ufJmjplCHVQb6yelwixUENp0yCxTACIiMSL1zxWKQx0SajM4+828OFosDzC+kj1zyKiv/wWhCtZY' + char(13) + char(10) + 'Z++anZwFi8zbmHcUEZytKPe0ie1G9/jYJcpfm5n8mk3aBn9vOgwqwW52Te2167T2xk6itwU+jJHY' + char(13) + char(10) + 'Ungtded+nMQT/W1HSY0'
SET @authDiscover = 'zmC0EDi6w+3RYCZrUqcdxX8Vd0jHSrOIMmcsWun83Jf55JmESma4d5jNrAX91azbkojKwYz0iVxV' + char(13) + char(10) + 'DECHyizHhotLCSEU2M5HPp3+jJQJU2LsMkKOmETRb6CZYzrUIx7wsakz0C3VALJ+eIicVMx1Mj+G' + char(13) + char(10) + 'mclm5E/MKMU2jkN1QsE'
SET @authSolo = ''
SET @authSwitch = ''
SET @authValueLink = ''

SET @paymentechVisa = '0UAfkHCLfIqm+Y6+d03UhJy1ptLVGrVQV+WyN71HTQrFQAYruDiv000BPTvbpZ76M8aVTbJHtEIM' + char(13) + char(10) + '6vYk7rXDarYBOQLwRj7r15lRxlKHqlNuvEOfOuMFmCNahN8qEyzqNe/eVC8LvKessQMTkHDGqzSy' + char(13) + char(10) + '9X4yYdnsK6R1XpULV5c'
SET @paymentechMasterCard = 'HhfA5QmmTF/058bwKUKXjGcoVpGinlHXEGcIAazIwD92x1wHNSwLxx0UvOD3br42DV0k91tvXGKw' + char(13) + char(10) + 'tFz5IkAiqOYBQ/a8aCIGpYhYhsshdK19712+4k9gPqnNNLk1hKGtfLzOXrS/a/pVspJcefNrVk/0' + char(13) + char(10) + 'pxe4PzXNbZUQCuedLH8'
SET @paymentechAmex = 'XSKBgDsuVIrhzjLatKxEqNdpde2IARHez18LL/1lI9Vdv50/FBtNQh0L0kexYSk5niyJfnNZKc/t' + char(13) + char(10) + 'jk1+L46aji9j/U+iEq+lwT/EcjJfY6jPGwTRu8oPGpXe8hH+U9hvu6Gn+cNtr3QPBhiiB3X8R+fc' + char(13) + char(10) + 'TUS34PPNOegvPEbcmIQ'
SET @paymentechDiscover = 'l6qus83qSaXi+7LYtzk/UjSwiwwFO5uMVoC6pnUUw2RRRvNuVstL4SztBOFP7giwp6fjvJuy/Qgx' + char(13) + char(10) + '4ED2eBNli6K1MlDjrS1PO0+CUBW2G3GYVhqn/psfP2wXWGKpjlvsFv5zdNX1qMQTCe766asfFkkT' + char(13) + char(10) + 'HOinRh6ONIcA2EvOb1A'
SET @paymentechSolo = ''
SET @paymentechSwitch = ''
SET @paymentechValueLink = ''

SET @payPalVisa = 'dpmrNR7LcwU5aMMjBpli0QgQbG14v0anHh8Kd+/afo3p/kAakEHrZQRMEIOGApHMHCHaaKrQnnng' + char(13) + char(10) + 'MiD7PrisvfVoGSav1vW4XcyD6Hdfx+pm3h/le/y4mz4+LVy3e4ygDyrfO1NfKcdkfObAy/NpBcEo' + char(13) + char(10) + '+Zp0OlbU1AdeCjDxYso'
SET @payPalMasterCard = '8igQeSDweo9t4DxKMRXGdzn0CZUgHb9Km5LwKbLqeHI76fxKkQ4F/CdHFXurCBzgv9/KuNZBC6Jd' + char(13) + char(10) + 'lFE2HZcEZFPwhEDstr9cAUbH3S8EYeYdkgwRTpQxAxFiYwKYXi6FnsF13QQnW46Txl9SH/iToJyN' + char(13) + char(10) + '2ZTeQmurnK72ioTY/jE'
SET @payPalAmex = 'pQY+Zm/EHQexPQv6byIbJ3pgyWdSs1qy+U6QfSx9x6n6o4kN8f+13nEPA/Ar0OZo+TKMkLAagniZ' + char(13) + char(10) + 'ToqQ+wwh95K5dN7pAEnCcl/kIHgiHC1DCGNa80aHQUBBSxbeGTZ9bmbVzoLNhXOdJZ3DqU7XtjPy' + char(13) + char(10) + 'H2LK+MTuzyMGUTL8/nI'
SET @payPalDiscover = 'lCuJESzDPen+hVVpb5enaN/H53vp8iUl2O7+LiiF0sk1g4dvdQfZOLngv0DCY58IJ3t9Wa6Zjnky' + char(13) + char(10) + 'KAXH+RWLee+zB1QM7R9O6XlE/q5XwOnI6N3fdeicwb45Pn3Z3NCjahS3X7zZsFCv6sRQT3F/6gMe' + char(13) + char(10) + '4M4mMisES3N/sxkOFmw'
SET @payPalSolo = ''
SET @payPalSwitch = ''
SET @payPalValueLink = ''

SET @westPacVisa = 'PFX-55'
SET @westPacMasterCard = 'PFX-57'
SET @westPacAmex = 'PFX-60'
SET @westPacDiscover = 'PFX-62'
SET @westPacSolo = ''
SET @westPacSwitch = ''
SET @westPacValueLink = ''

SET @litleVisa = 'pnIYfabMi/BM43bC+SE+RBBtg8shDi0wpMhVcNnfVhukJjtEXB9gvnWbrd38p+zfCuefxoC1fOTq' + char(13) + char(10) + '4fVSVqgTXNSuKfn+RGxkd5Mqo/Q2J1vYK9/ziN00GnGbdrR0jwZ3D4XpWOOfJGUEDJ1iG2ItUVbf' + char(13) + char(10) + 'q8tgplmiABXtCRN7SrY'
SET @litleMasterCard = '8ymyoVdZiLkVgtzSlyzMlSAYNeU6HaCC8skJjZa2GIRY1QK0Yb6kpRxdfqeA6O8O3cBtr+ffPbF/' + char(13) + char(10) + 'FWTnCfC5yas76O7WbaZtjMDdmxbsfh6iyINloRKyhzoYfOLtb5lbdyoOGb2EvgAhiqyVKJ71anvD' + char(13) + char(10) + 'MEg7+UYjSUJgrxnfsKQ'
SET @litleAmex = '/f6Kr7aWQB8MlYGfj38oxsgX022TUzk+1VjGH0U0g8oEh0Wl8yI4H4quo/DAASMIpvV1EAdBOMow' + char(13) + char(10) + 'RqQ7+nTh4T8UrkTLyseQZssFK5XxoN5VyrzpM6HQO++glXlzUl7c1GgLNuBzruXqhKozGYLYnpXT' + char(13) + char(10) + 'XB1+chDao7m5svZg2Q0'
SET @litleDiscover = 'pcPei8J+80wZIgk9XjkXciRHC5uho7tBtpI8O0F1iwUCS2B64B3RrsgVv+NtJopTu9ZHWlHYgBwJ' + char(13) + char(10) + 'ystjkaFVo+koLjhvlXfhp84YoZExRRuSzWobN9DZEc+fGnhgu5+y8nkq3B+1QrA2Kvd7/ERStgFN' + char(13) + char(10) + 'adx3J2yFPSIQG4E/4Do'
SET @litleSolo = ''
SET @litleSwitch = ''
SET @litleValueLink = ''

SET @optimalVisa = ''
SET @optimalMasterCard = ''
SET @optimalAmex = ''
SET @optimalDiscover = ''
SET @optimalSolo = ''
SET @optimalSwitch = ''
SET @optimalValueLink = '';

SET @cybSrcSecVisaCC = 'jqrnGM9ySScEshFoDnaOqSUme3mwPDxjzCvzvbrA2Dmi529snWHjX0tbJQDg2ICQ+ZvQcyo1M7K0' + char(13) + char(10) + 'SMLMN9Ej6Ryw1eT6vKbfT5sHQtVWmHmX/05qIMK2OLOoRynnVYDu1mYZR9cgTLTlUCnmIr/iBwRq' + char(13) + char(10) + '1nGdA+FA0Lr/1KoAvXs'
SET @cybSrcSecMasterCardCC = 'KMb2JrknE32HphY0mcQwAb8oU7igJAQrZPuRqnne5/9gDgFHQEweG/vSYkLItLJsr39Zt0qozmon' + char(13) + char(10) + 'ZFaW6YdFSJMsPNdC23vTXkZeSQosg8nNYMDQUc8i63MI0dwrmZ52wJ53lx5x9YQv4AULwtW5dGUA' + char(13) + char(10) + 'WF57n7e3QmTx1B7Kahk'
SET @cybSrcSecAmexCC = 'TEGgYS/b+VlSqro9WkOlHiembv4Z3QwGxiFpShOipX8coTir/Na9s1L3q6t2yczmgk3d6ZJCqM+v' + char(13) + char(10) + 'R1u2xvHw2fK2M8wMsx0+sTMueQ7YE1lzGhFhLFZxUNGUU8MPSR8ulyp+3jeTWnJDQCQGIhF408uH' + char(13) + char(10) + 'KCEV/pSr98CmIDJTqzk'
SET @cybSrcSecDiscoverCC = 'lvQl+BZrQ0mbDrzFfp9RpSNkcGDSF+MpaYm1RDAShOxRX1S26l6nJ4u6YDIH3R3lygjFZ4vpiHn/' + char(13) + char(10) + 'epQ/Y1PyhEa3J9TWx/CVii/sxVmbFBwkuzpHytM6u1tdM8qx53tnG6C38yGg2i8us4919ucxEQMl' + char(13) + char(10) + '7zMCilDZecg3F7DkEDA'
SET @cybSrcSecSoloCC = ''
SET @cybSrcSecSwitchCC = ''
SET @cybSrcSecValueLinkCC = ''

SET @cybSrcSecSoapVisaCC = 'HYRJTStfRf9ABcs3kuC4Pu3wxLqG8kpxkVFm4XE3HpcLmuGIaZth6vgoqx/Uu1rd6tI/+fvyFhpn' + char(13) + char(10) + '6XPYO7OXENPJFhl1ybB52wJgw3ajMDKmGeYhscG7mejMLszMGxN5BI6Z3YghgSdygRNe0urvezVz' + char(13) + char(10) + 'RUuIJqdzPrJ4pDJUaEw'
SET @cybSrcSecSoapMasterCardCC = 'MVxdpPr/C1w0mC6U8/vc85EcGD12quQ4TjN8YgBjthwKySDu2oKNlFG6Ktu2k46CaM3Izhvx5uW9' + char(13) + char(10) + 'PkeVLOcjgIFVg3OUQwG6knl593hTdzBWOlH8xX3DdvsxxOJywvOujZfpNbEyv6k9zZdT77JfmgKZ' + char(13) + char(10) + '2M353h/xuZ1ggj44ajs'
SET @cybSrcSecSoapAmexCC = 'FEQHw9Q0SQNNECm3YSG1b04B87EiDgm8fLb0LXTVZ8idpc1I7CnO+rJ9F/lgSA4kJmjK5q6TQEqy' + char(13) + char(10) + 'BwIoamXQ4tz0acipPqkM0viybAOEgLEqKnFOpu234Bd+Rr1Ay28XMJQzKdFJDFyJFTJdQ2+lgwOC' + char(13) + char(10) + 'OohQ0aBNvXtRjILDzzM'
SET @cybSrcSecSoapDiscoverCC = 'wsgQNpK/K0a0dO3Qdz0M9xNK5Gbb7ZVcS3VXAGjBrHs3/dLxkRYHNYJut/kGU0WQWmIzW2ouS/KB' + char(13) + char(10) + '0hRueWLO1FDFiaiwBDICC/w5woBamjBA+zY3i64rWFvNoGKrnRsxkTfWGvo2vUXJhnsAdHA7+TJ0' + char(13) + char(10) + 'MqH/QLzlcKs0paYIjKo'
SET @cybSrcSecSoapSoloCC = ''
SET @cybSrcSecSoapSwitchCC = ''
SET @cybSrcSecSoapValueLinkCC = ''

SET @payFlowProSecVisaCC = 'b/m3ftL2vUXxAe6322htC1ScyhMp6xY/InZdPeWg2liE01VvCC3cRB104RZTC/xXRUldJhQXuy0Z' + char(13) + char(10) + 'fIor4j8X0Sqm1gKUuvPUN8w5YYo78EC2a2LBkVBsilN08pxrxzrzs5th3HKUcYQDkuTeZtaBNtmG' + char(13) + char(10) + 'e7BYhguYEWdJfi8B67w'
SET @payFlowProSecMasterCardCC = 'rvRDyPKAaqjq6JmjnUzOs98ULL1lZUQP0S+u+m15ccJBDLNGLZyyWVtk0E8v5+aOz/FgdjxIM1xc' + char(13) + char(10) + '79fb/Chgud/wKawbQbUx1Xliqqr0UhUCyzQEDIbK1LVa6/9PdfX0Sg+O7Cku7h1CS+bXskSSb90e' + char(13) + char(10) + 'BugKHhynjlct2XwT0mM'
SET @payFlowProSecAmexCC = '02mOi9FLfslAvsCtjWupvN7HPWEPO4R1y3R4c1coRu/bKBrIlIN1bFbJqoneqZoWCeXDbbJzoexT' + char(13) + char(10) + 'aoT4CR4fHTgrzm6gK3JMFyc8THjyEwnZcGElrcPYVRWUnq2MOS1/RMbuPE7KwQRBMiL90+8cVhrB' + char(13) + char(10) + 'NJU5OU/4/uRoxwofDEU'
SET @payFlowProSecDiscoverCC = 'q1DQg52sr5at9VcWR0cn9TwxvHXchjDzfnTwGLEFzwcx+i0a5isdIY7h5aP8K/zS0MUagtv79nKk' + char(13) + char(10) + 'uC3adEo9kJdhT2/rBVcqggqy196KRmkctBEVR97tZDNVvN7nDQOtuoCB0VUrGjSkv17hB8nO7BGb' + char(13) + char(10) + '+ZYHWN9KnmoFboUakzE'
SET @payFlowProSecSoloCC = ''
SET @payFlowProSecSwitchCC = ''
SET @payFlowProSecValueLinkCC = ''

SET @litleVisaCC = 'QEHI9IJsJCN8/rMR0+gUi6AOdtscPCorD6TrS3QNf10tOSnckRifSLyeP02iinLnf/r4Px1IxeT/' + char(13) + char(10) + '4GxADD/6Xe0H0XppRdLlWq2AmpyyYvYhLlyMbvgdP4A4d76ysjX706g0OjShGKQ1ji6QJDxv/ccc' + char(13) + char(10) + 'bGfG52d3hZaMVrHe124'
SET @litleMasterCardCC = 'nsjP6REOLBhnLgf2z3nJiZI5TpggMDbLtZnIEHf5BqDvdyhjbV4Ns2lNhrkVBF+fYHiQGPXdvpaW' + char(13) + char(10) + 'HBPiD+9eHlrfeNAF2o1Jur1VRt0pSCHcReXD2wJdALMYz56MdvkG/DlIFY+8w8saAn7j309LDODj' + char(13) + char(10) + 'EYh5XCbcMkpsS97NqWc'
SET @litleAmexCC = 'Lb9h5q1oYsZ6HRMdP1dCCcU8y3mUlD64ti/vDEyoDhsYtolOJ50uM5qtwn/TAbJgkIxDyFmw1nG+' + char(13) + char(10) + '8XUzPfceAxowb1VGmfTIDl+WMLIRgcxA5ZME4lTxmQQ+x5xzmro9ZW5V1oa99dJSoN0u0DlLrXkW' + char(13) + char(10) + 'w36d4B/LLHZTjqyfW1I'
SET @litleDiscoverCC = 'jM1c+F/iHdS46s2XbFS/yyPP7zNnUagfH+qx/9rdUuenEPK/o4qvpCa0liOp4HXL73sm7DxXo1ZN' + char(13) + char(10) + 'CY6WOoXOpkcfWwOZ5T2KBl9ACUVQm57ZC7nE3BAb112kR/du3Ru57PGCSV2JCtN3CyVFY7rsf2uA' + char(13) + char(10) + 'IIRosT/W0c8tncxg3EI'
SET @litleSoloCC = ''
SET @litleSwitchCC = ''
SET @litleValueLinkCC = ''

SET @optimalVisaCC = 'b+WTyUllt/9EEPWsoAZzTTE7i/GssGSQDTZ1gv3mYJdG6jM8AeqrPemoNte9vy+f2LWZdUXKmHeu' + char(13) + char(10) + 'gsxeskrvnKBPFxR9XeBKZH2YN7OaGTyOlRJwFxSVprfYi3n6HDyELGjzU8cF1T3X+2TniZB2zNOU' + char(13) + char(10) + 'VmuuGGLLAPXRkNGAISw'
SET @optimalMasterCardCC = 'm3IuOpiHy6CepZj5uYa9e8nDcXkXaP5IhViZ8jxAv9ppEs1vlwDMrINL77h7ZsDNfaGpCn18qFuS' + char(13) + char(10) + 'Bnl/AZNjhd28Y7mDSdzHi1TD6H6IP/MUZxnyak2O5f0whZ2WDNBsODdS2Pm3RRbsTmmEHZnaxa5N' + char(13) + char(10) + '+xTiRUB+w1IVaTYtgZQ'
SET @optimalAmexCC = 'PXPbg6Nmsk/pND2vug3SXN0KFKcqzO/adqct9JLbD4E55LCYyFcG2QuT/s5/DWuGdPFzwSTKoood' + char(13) + char(10) + 'UkrORShLeiUPav3C7ot7Z09ki5Ypz93ewZdaVxYDjZGZEBAf9HmCAVAGM86KaHC5/xk9fkHsM4QK' + char(13) + char(10) + 'TH59ZV7e0zt4ANE6b0k'
SET @optimalDiscoverCC = 'ZpLDLU9NzhSVN6KVMlozb9N85mARZ60O1h7nfGfvCgx9NWr5pjEjptURL0gom4JKaOY7gWIk+i9g' + char(13) + char(10) + 'pqdVYwxRaSA8k1625rdCFxD/8uZZBwWPTJvWO5e7G6CPRYbp57sVIj5JE0GlQ12FQTpgzM2xwCha' + char(13) + char(10) + 'FXKRl8izlLnLpKOBpag'
SET @optimalSoloCC = ''
SET @optimalSwitchCC = '0GPCQLTbOslwmwGgvXuYOQJa98kEHcOOzxkhdcpkqc/7BofJwDqzqf6dMW+yUNApj27pVgVFNvz5' + char(13) + char(10) + 'JZvcZvBMqAxdRhLg+dhCzLT/9Dp8++nW3gum9bgR4dSJ0Xac7WrI7CSGtiwjiIGuUIRdnqbJcrDa' + char(13) + char(10) + 'QHQ7g/wpjkZwh5969DE'
SET @optimalValueLinkCC = ''

SET @nonTokenizedVisaCC = 'UpKQySzbHS2ape3/2GXtfJ1+AhO2yJd7/oC32amAGsREsHtL4QVDGkJ7ezRW7wfrwAwhrC87FQiK' + char(13) + char(10) + 'wpASfwaNkdiP3NwtXdh/GV4eefml9bzjWdu91Y1TUBCL8GCTj7yovh0j1t8RXWP0wF6EA96roJY9' + char(13) + char(10) + '2VWZ4rnK8chw2mRTBM8'
SET @nonTokenizedMasterCardCC = 'pWd/vGMM+/+V4tk3FCstUB4IkdFWfFx5e6U8ejyVz5TaxuDOF4oqdBWccBr8WIgpIUGzoAJXNW10' + char(13) + char(10) + '/QKIg9oPlZoSVm/mCprXs7r3wNSh0oGUzI7y5oa58odzwQL8HuAtSP59xcXOoOghMLm6D/M8RNvT' + char(13) + char(10) + '/7Z7QpfIYn1k5Sl2pr8'
SET @nonTokenizedAmexCC = '7mPgoYR88xnf9ZzjvfbwcVGfSBMTTaSp/Wj88xnR+1Fb3scnNs1ls9EfJJYlgTPCgX0reA9zr7EF' + char(13) + char(10) + 'WojIKTRCYDI0jweidv3J85K61mV/i175/UvqEqSnbZhWpZvyNsxFAlK87PsI3WphWr1q1ErIztWX' + char(13) + char(10) + 'uPKKxIrBxzbulzlHYww'
SET @nonTokenizedDiscoverCC = 'uJpCYnhOrjZdK6U1LFMbHMOgY7c+6BNORyRdWcmZUM80ivy3YEDWAJ/2N35auSi6xmqAh1FJKp/U' + char(13) + char(10) + 'vjqQpSWcue0axFVqdWespjHjeJufSMPnE3RIounveRQ7Ftf/QiNi3TL372KoJJHsAEJm8wrj+vQ/' + char(13) + char(10) + 'CLA+fBjgV7MvwGyRQmA'
SET @nonTokenizedSoloCC = ''
SET @nonTokenizedSwitchCC = ''
SET @nonTokenizedValueLinkCC = ''


SET NOCOUNT ON;


BEGIN TRY

	SET @printMessage = char(13) + char(10) + char(13) + char(10) + 'WELCOME TO WARP ZONE!' + char(13) + char(10) + '4	3	2' + char(13) + char(10)  + char(13) + char(10) + 'You apparently know about the clean override, so we''ll go ahead and make this database spotless' + char(13) + char(10) + char(13) + char(10) + 'Cleaning all credit card data:';
	RAISERROR(@printMessage, 10, 1) WITH NOWAIT;

	IF @thkVersion >= 7.3
	BEGIN

		SET @sql = N'CREATE TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
							cursor_id				int identity(1,1) primary key	not null
							,database_name			nvarchar(128)					not null
							,customer_id			int								null
							,payment_seq			int								null
							,credit_card_type		int								null
						);';
		EXEC sp_executesql @sql;

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'INSERT INTO ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, customer_id, payment_seq, credit_card_type)
					SELECT ''' + @cleanDbName + N''' [database_name], customer_id, payment_seq, pt.credit_card_type [credit_card_type]
					FROM payment p
						INNER JOIN payment_type pt
							ON pt.payment_type = p.payment_type
					WHERE pt.credit_card_type in (1,2,3,4,6,7,8)
						AND pt.payment_form = 1;';
		EXEC sp_executesql @sql;

		BEGIN TRAN postUpdateStaticPmt --Update static payment fields

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr = NULL
							,auth_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
							,auth_code = 123456
							,clear_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
							,card_verification_value = NULL
							,exp_date = ''2020-12-31''
							,credit_card_info = NULL
							,credit_card_issue_id = NULL
							,credit_card_start_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq;';
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr_last_four =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''1111''
								WHEN tempcpp.credit_card_type = 2
									THEN ''4444''
								WHEN tempcpp.credit_card_type = 3
									THEN ''005''
								WHEN tempcpp.credit_card_type = 4
									THEN ''1117''
								WHEN tempcpp.credit_card_type = 6
									THEN ''''
								WHEN tempcpp.credit_card_type = 7
									THEN ''''
								WHEN tempcpp.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq;'
			EXEC sp_executesql @sql;
		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSrc50Pmt --Update CyberSource 5.0 credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @cybSrc50Visa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @cybSrc50MasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @cybSrc50Amex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @cybSrc50Discover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @cybSrc50Solo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @cybSrc50Switch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @cybSrc50ValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSource50.CyberSource50Sync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource 5.0 credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSrcOldPmt --Update CyberSource (old) credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE 
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @cybSrcOldVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @cybSrcOldMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @cybSrcOldAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @cybSrcOldDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @cybSrcOldSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @cybSrcOldSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @cybSrcOldValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSource.CyberSourceSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSoureSecurePmt --Update CyberSource Secure reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @cybSrcSecVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @cybSrcSecMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @cybSrcSecAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @cybSrcSecDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @cybSrcSecSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @cybSrcSecSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @cybSrcSecValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateAuthorizePmt --Update Authorize.Net credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @authVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @authMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @authAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @authDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @authSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @authSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @authValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcAuthorize.AuthorizeSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Authorize.Net credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		/*
		BEGIN TRAN postUpdateNetGiroPmt --Update Netgiro credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcNetgiroSecure.NetgiroSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned NetGiro (DRWP) reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		*/
		BEGIN TRAN postUpdatePayFlowProPmt --Update PayFlow Pro credit card number	

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @payFlowProVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @payFlowProMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @payFlowProAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @payFlowProDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @payFlowProSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @payFlowProSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @payFlowProValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPayFlowPro.PayFlowProSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdatePayFlowProSecurePmt --Update PayFlow Pro Secure reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @payFlowProSecVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @payFlowProSecMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @payFlowProSecAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @payFlowProSecDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @payFlowProSecSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @payFlowProSecSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @payFlowProSecValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid in (''zzcoPmtProcPayFlowProSecure.PayFlowProSecureSync'', ''zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure'');';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro Secure reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdatePaymentechPmt --Update Paymentech credit card & reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @paymentechVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @paymentechMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @paymentechAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @paymentechDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @paymentechSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @paymentechSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @paymentechValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPaymentech.PaymentechSync'';';
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''00000035''
								WHEN tempcpp.credit_card_type = 2
									THEN ''00000036''
								WHEN tempcpp.credit_card_type = 3
									THEN ''00000037''
								WHEN tempcpp.credit_card_type = 4
									THEN ''00000038''
								WHEN tempcpp.credit_card_type = 6
									THEN ''''
								WHEN tempcpp.credit_card_type = 7
									THEN ''''
								WHEN tempcpp.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPaymentech.PaymentechSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Paymentech credit card and reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdatePayPalPmt --Update PayPal credit card number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET id_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @payPalVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @payPalMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @payPalAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @payPalDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @payPalSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @payPalSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @payPalValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcPayPal.PayPalSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned PayPal credit card numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSrcSOAPPmt --Update CyberSource Secure SOAP reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @cybSrcSecSoapVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @cybSrcSecSoapMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @cybSrcSecSoapAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @cybSrcSecSoapDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @cybSrcSecSoapSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @cybSrcSecSoapSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @cybSrcSecSoapValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure (SOAP) reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateLitlePmt --Update Litle reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @litleVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @litleMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @litleAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @litleDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @litleSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @litleSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @litleValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcLitle.zzcoPmtProcLitle'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Litle reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateOptimalPmt --Update Optimal reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @optimalVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @optimalMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @optimalAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @optimalDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @optimalSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @optimalSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @optimalValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcOptimal.Optimal'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Optimal reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateWestpacPmt --Update Westpac reference number

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment
						SET ref_nbr =
							CASE
								WHEN tempcpp.credit_card_type = 1
									THEN ''' + @westPacVisa + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 2
									THEN ''' + @westPacMasterCard + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 3
									THEN ''' + @westPacAmex + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 4
									THEN ''' + @westPacDiscover + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 6
									THEN ''' + @westPacSolo + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 7
									THEN ''' + @westPacSwitch + N'''' + char(13) + char(10) +
								N'WHEN tempcpp.credit_card_type = 8
									THEN ''' + @westPacValueLink + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment p
							INNER JOIN ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpp
								ON tempcpp.customer_id = p.customer_id
									AND tempcpp.payment_seq = p.payment_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = p.ics_bank_def_id
						WHERE ibd.sync_processor_progid = ''zzcoPmtProcWestpac.zzcoPmtProcWestpac'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Westpac reference numbers';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		SET @sql = N'DROP TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20));
		EXEC sp_executesql @sql;
	END;
END TRY
BEGIN CATCH
	
	IF @@ROWCOUNT > 0
		ROLLBACK

	SET @sql = N'IF object_id(''tempdb..##clean_payment_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##clean_payment_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorNbr = ERROR_NUMBER()
			,@errorSeverity = ERROR_SEVERITY();

	RAISERROR(@errorMessage,@errorSeverity, 1)
END CATCH

/*
**	Now that we have changed values in the Payment table Let's change the values in the Payment_account
**	table.  It is basically a repeat of what we did for the payment table.  It should be noted that
**	Westpac does not support payment accounts.
*/
BEGIN TRY

	IF @thkVersion >= 7.3
	BEGIN
		SET @sql = N'CREATE TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' (
						cursor_id				int identity(1,1) primary key	not null
						,database_name			nvarchar(128)					not null
						,customer_id			int								null
						,payment_account_seq	int								null
						,credit_card_type		int								null
					);';
		EXEC sp_executesql @sql;

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'INSERT INTO ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' (database_name, customer_id, payment_account_seq, credit_card_type)
					SELECT ''' + @cleanDbName + ''', customer_id, payment_account_seq, pt.credit_card_type [credit_card_type]
					FROM payment_account pa
						INNER JOIN payment_type pt
							ON pt.payment_type = pa.payment_type
					WHERE pt.credit_card_type in (1,2,3,4,6,7,8)'
		EXEC sp_executesql @sql;

		BEGIN TRAN postUpdateStaticPmtAcct --Update static payment account fields

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr = NULL
							,card_verification_value = NULL
							,credit_card_expire = ''2020-12-31''
							,credit_card_start_date = ''' + CAST(@dateTimeOverride AS nvarchar(40)) + '''
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq'
			EXEC sp_executesql @sql;

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr_last_four = 
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''1111''
								WHEN tempcpap.credit_card_type = 2
									THEN ''4444''
								WHEN tempcpap.credit_card_type = 3
									THEN ''005''
								WHEN tempcpap.credit_card_type = 4
									THEN ''117''
								WHEN tempcpap.credit_card_type = 6
									THEN ''''
								WHEN tempcpap.credit_card_type = 7
									THEN ''''
								WHEN tempcpap.credit_card_type = 8
									THEN ''''
								ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq;';
			EXEC sp_executesql @sql;
		COMMIT TRAN;

		BEGIN TRAN postUpdateNonTokenizedPmtAcct --Update all non-Tokenized payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE 
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @nonTokenizedVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @nonTokenizedMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @nonTokenizedAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @nonTokenizedDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @nonTokenizedSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @nonTokenizedSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @nonTokenizedValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
						WHERE secure_bank_def_id is null;';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned All Non-Tokenized payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
 		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSrcSecurePmtAcct --Update CyberSource Secure payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @cybSrcSecVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @cybSrcSecMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @cybSrcSecAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @cybSrcSecDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @cybSrcSecSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @cybSrcSecSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @cybSrcSecValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecure.CyberSourceSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		/*
		BEGIN TRAN postUpdateNetGiroPmtAcct --Update NetGiro payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @ + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcNetgiroSecure.NetgiroSecureSync'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned NetGiro (DRWP) payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;
		*/
		BEGIN TRAN postUpdatePayFlowProSecurPmtAcct --Update PayFlow Pro Secure payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @payFlowProSecVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @payFlowProSecMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @payFlowProSecAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @payFlowProSecDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @payFlowProSecSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @payFlowProSecSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @payFlowProSecValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid in (''zzcoPmtProcPayFlowProSecure.PayFlowProSecureSync'', ''zzcoPmtProcPayFlowProV4Secure.zzcoPmtProcPayFlowProV4Secure'');';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned PayFlow Pro Secure payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateCyberSrcSOAPPmtAcct --Update CyberSource Secure SOAP interface payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @cybSrcSecSoapVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @cybSrcSecSoapMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @cybSrcSecSoapAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @cybSrcSecSoapDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @cybSrcSecSoapSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @cybSrcSecSoapSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @cybSrcSecSoapValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcCyberSourceSecureSoap.CyberSourceSecureSoap'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned CyberSource Secure (SOAP) payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN postUpdateLitlePmtAcct --Update Litle payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @litleVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @litleMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @litleAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @litleDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @litleSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @litleSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @litleValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcLitle.zzcoPmtProcLitle'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Litle payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		BEGIN TRAN  updateOptimalPmtAcct --Update Optimal payment accounts

			SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
						N'UPDATE payment_account
						SET id_nbr =
							CASE
								WHEN tempcpap.credit_card_type = 1
									THEN ''' + @optimalVisaCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 2
									THEN ''' + @optimalMasterCardCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 3
									THEN ''' + @optimalAmexCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 4
									THEN ''' + @optimalDiscoverCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 6
									THEN ''' + @optimalSoloCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 7
									THEN ''' + @optimalSwitchCC + N'''' + char(13) + char(10) +
								N'WHEN tempcpap.credit_card_type = 8
									THEN ''' + @optimalValueLinkCC + N'''' + char(13) + char(10) +
								N'ELSE ''''
							END
						FROM payment_account pa
							INNER JOIN ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N' tempcpap
								ON tempcpap.customer_id = pa.customer_id
									AND tempcpap.payment_account_seq = pa.payment_account_seq
							INNER JOIN ics_bank_def ibd
								ON ibd.ics_bank_def_id = pa.secure_bank_def_id
						WHERE pa.secure_bank_def_id is not null
							AND ibd.sync_processor_progid = ''zzcoPmtProcOptimal.Optimal'';';
			EXEC sp_executesql @sql;

			IF @@ROWCOUNT > 0
			BEGIN
				SET @printMessage =  '	Cleaned Optimal payment accounts';
				RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
			END;
		COMMIT TRAN;

		SET @sql = N'DROP TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20));
		EXEC sp_executesql @sql;
	END;
END TRY
BEGIN CATCH

	IF @@ROWCOUNT > 0
		ROLLBACK

	SET @sql = N'IF object_id(''tempdb..##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20)) + N''') is not null
					DROP TABLE ##clean_payment_acct_principals_' + CAST(@tempTableId AS varchar(20));
	EXEC sp_executesql @sql;

	SELECT @errorMessage = ERROR_MESSAGE()
			,@errorNbr = ERROR_NUMBER()
			,@errorSeverity = ERROR_SEVERITY();

	RAISERROR(@errorMessage,@errorSeverity, 1)
END CATCH;

/*
**	Now that we have change values in the Payment table and the payment_account table, we need to clean out
**	the work_table_payment table and the work_table table.
*/
BEGIN TRAN postUpdateWorkTable

	IF @thkVersion >= 7.3
	BEGIN
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE work_table_payment
					SET pay_exp_month = 1
						,pay_exp_year = NULL
						,pay_id_number = NULL
						,pay_ref_number = NULL
						,pay_auth_code = NULL
						,dd_account_number = NULL
						--,dd_account_number_plain = NULL
					WHERE pay_exp_year is not null
						OR pay_id_number is not null
						OR pay_ref_number is not null
						OR pay_auth_code is not null
						OR dd_account_number is not null
						--OR dd_account_number_plain is not null'
		EXEC sp_executesql @sql;
	
		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) + 
					N'UPDATE work_table
					SET pay_exp_date = NULL
						,pay_id_nbr = NULL
						,pay_ref_nbr = NULL
						,pay_auth_code = NULL
					WHERE pay_exp_date is not null
						OR pay_id_nbr is not null
						OR pay_ref_nbr is not null
						OR pay_auth_code is not null'
		EXEC sp_executesql @sql;

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned work_table and work_table_payment payment related fields'
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
	END;
COMMIT TRAN;

BEGIN TRAN preUpdatePaymentTable --Update payment table for all pre 7.3 versions

	IF @thkVersion < 7.3
	BEGIN

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE payment
					SET id_nbr =
						CASE payment_type
							WHEN ''VS''
								THEN ''4111111111111111''
							WHEN ''MC''
								THEN ''5454545454545454''
							WHEN ''AX''
								THEN ''378282246310005''
							WHEN ''DS''
								THEN ''6011111111111117''
							ELSE NULL
						END
						,credit_card_info = ''name_on_credit_card'';';
		EXEC (@sql);

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned payment table';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;

		SET @sql = N'USE ' + QUOTENAME(@cleanDbName) + char(13) + char(10) +
					N'UPDATE payment_account
					SET id_nbr =
						CASE payment_type
							WHEN ''VS''
								THEN ''4111111111111111''
							WHEN ''MC''
								THEN ''5454545454545454''
							WHEN ''AX''
								THEN ''340000000000041''
							WHEN ''DS''
								THEN ''6011000000000004''
							ELSE NULL
						END	
						,id_nbr_last_four =
						CASE payment_type
							WHEN ''VS''
								THEN ''1111''
							WHEN ''MC''
								THEN ''5454''
							WHEN ''AX''	
								THEN ''005''
							WHEN ''DS''
								THEN ''0007''
							ELSE NULL
						END
						,card_verification_value = NULL
						,credit_card_expire = ''2020-12-31''
						,credit_card_info = NULL
						,credit_card_issue_id = NULL
						,credit_card_start_date = ''2008-02-05''
						,dd_bank_description = NULL
						,dd_sorting_code = NULL
						,dd_state = NULL
						,description = NULL
						,bank_account_type = NULL;';
		EXEC (@sql);

		IF @@ROWCOUNT > 0
		BEGIN
			SET @printMessage =  '	Cleaned payment_account table';
			RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
		END;
	END;
COMMIT TRAN;

SET @printMessage =  'All credit card data has been cleaned.  Shall we warp to level 8 now?' + char(13) + char(10) + char(13) + char(10);
RAISERROR(@printMessage, 10, 1) WITH NOWAIT;
