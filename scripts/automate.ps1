<#
    The script utilizes the dbo.usp_THKBackupDb stored procedure to automate database backups of the Customer First and db_changes databases.
#>

clear
$scriptName = "THINK Subscription Development Backups"

Write-Host "															       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "===========||														       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "POWERED BY:||														       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "===========||														       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "															       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "TtTTTttTTTTTT++TtT^|IIIH     HIH   88I  8NnNii .. N87^|KkI    KKKKik							       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "TtTTTsSitttTTtiT+T^|I~IH     HHH....8I  Nnn777i   Nn7^|KkI   IkKKi  ....						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "      TttTit ~~~~~^|I~IH     HHI . 77I  TN8  777n NNK^|KkI ikKKi     ......						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "     Tti~Tt  ~~ . ^|IIIHaaaaaIII . i.I  T88 . NN7 ppS^|KkIkKKKi       ......						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "    TttTTt  ~~ .. ^|IIIHaaaaaHII ..77I  TNN .. nN7KN7^|KkIkKk          ......						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "   TtteTt  ~~ ... ^|iaiH     iiH . 77i  TNN ++  nNNaK^|KkI kKKi       ......						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "  TttTet  ~~..... ^|iIIH     aaI.. 88I  8NN ...  nN7+^|KkI   iiiK     .....						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host " TttTTe   ~...... ^|IIIH     aia.  III  Nnn  ...  N87^|KkI    IIiIk   ....						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "TTsstt  ......... ^|iIiH     HHH   i8I  nnn    ...NN7^|KkI     IIiKKk ....++++						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~~~....~~~~~~~~~~						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "..............................................................................						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "##############################################################################						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "             ${scriptName} Script										       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host "##############################################################################						       " -ForegroundColor Blue -BackgroundColor Gray
Write-Host ""

