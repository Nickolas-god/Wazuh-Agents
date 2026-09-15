#Requires -RunAsAdministrator
<#
    Deploy padrão S3 - Sysmon + Wazuh Agent (via SMB)
    Puxa os instaladores e configs de um compartilhamento de rede em vez
    de baixar da internet. Útil quando a rede do cliente não tem saída
    para internet, ou pra evitar banda desperdiçada em N máquinas.

    Estrutura esperada no compartilhamento SMB (copie a pasta toda pra lá):
        \\servidor\s3deploy\
        ├── Sysmon64.exe
        ├── wazuh-agent.msi
        ├── configs\
        │   ├── sysmonconfig-full.xml
        │   └── ossec-agent-windows.conf
        └── scripts\
            └── deploy-s3-agent-smb.ps1   <- este arquivo

    Uso: rodar localmente em cada máquina como Admin, ou via Invoke-Command
    remotamente / PsExec (ver README.docx).
#>

# ==================== CONFIG (ajuste antes de rodar) ====================
$WazuhManagerIP   = "IP_DO_SEU_MANAGER"
$WazuhAgentGroup  = "windows-endpoints"

# Caminho UNC do compartilhamento onde estão os arquivos (pasta raiz do pacote)
$SharePath        = "\\IP_OU_HOSTNAME_DO_SERVIDOR_SMB\s3deploy"
$SmbUser          = ""   # deixe em branco se a máquina já tem acesso (ex: domínio)
$SmbPass          = ""   # idem

$WorkDir       = "C:\S3-Deploy"
$OssecConfPath = "C:\Program Files (x86)\ossec-agent\ossec.conf"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ==================== 0. CONECTAR NO SHARE (se necessário) ====================
if ($SmbUser -ne "") {
    Write-Host "[0/5] Autenticando no compartilhamento..." -ForegroundColor Cyan
    $securePass = ConvertTo-SecureString $SmbPass -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($SmbUser, $securePass)
    New-PSDrive -Name "S3Deploy" -PSProvider FileSystem -Root $SharePath -Credential $cred -ErrorAction Stop | Out-Null
} else {
    if (-Not (Test-Path $SharePath)) {
        Write-Host "ERRO: não foi possível acessar $SharePath. Preencha `$SmbUser/`$SmbPass ou verifique a rede." -ForegroundColor Red
        exit 1
    }
}

if ($WazuhManagerIP -eq "IP_DO_SEU_MANAGER") {
    Write-Host "ERRO: preencha a variável `$WazuhManagerIP` no topo do script antes de rodar." -ForegroundColor Red
    exit 1
}

# ==================== 1. COPIAR ARQUIVOS DO SHARE ====================
Write-Host "[1/5] Copiando arquivos do share..." -ForegroundColor Cyan
Copy-Item "$SharePath\Sysmon64.exe" "$WorkDir\Sysmon64.exe" -Force
Copy-Item "$SharePath\configs\sysmonconfig-full.xml" "$WorkDir\sysmonconfig-full.xml" -Force
Copy-Item "$SharePath\configs\ossec-agent-windows.conf" "$WorkDir\ossec-agent-windows.conf" -Force
Copy-Item "$SharePath\wazuh-agent.msi" "$WorkDir\wazuh-agent.msi" -Force

# ==================== 2. INSTALAR SYSMON ====================
Write-Host "[2/5] Instalando Sysmon..." -ForegroundColor Cyan
$existingSysmon = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if ($existingSysmon) {
    & "$WorkDir\Sysmon64.exe" -c "$WorkDir\sysmonconfig-full.xml"
} else {
    & "$WorkDir\Sysmon64.exe" -accepteula -i "$WorkDir\sysmonconfig-full.xml"
}

Start-Sleep -Seconds 3
if (Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue) {
    Write-Host "Sysmon OK." -ForegroundColor Green
} else {
    Write-Host "ATENÇÃO: Sysmon64 não subiu." -ForegroundColor Yellow
}

# ==================== 3. INSTALAR WAZUH AGENT ====================
Write-Host "[3/5] Instalando Wazuh Agent..." -ForegroundColor Cyan
$msiArgs = "/i `"$WorkDir\wazuh-agent.msi`" /q WAZUH_MANAGER='$WazuhManagerIP' WAZUH_AGENT_GROUP='$WazuhAgentGroup'"
Start-Process msiexec.exe -ArgumentList $msiArgs -Wait

Stop-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue

# ==================== 4. APLICAR O ossec.conf COMPLETO ====================
Write-Host "[4/5] Aplicando ossec-agent-windows.conf (FIM, PowerShell, Sysmon, registro)..." -ForegroundColor Cyan
$ossecContent = Get-Content -Path "$WorkDir\ossec-agent-windows.conf" -Raw
$ossecContent = $ossecContent -replace "IP_DO_WAZUH_MANAGER", $WazuhManagerIP
Set-Content -Path $OssecConfPath -Value $ossecContent -Encoding UTF8 -Force

# ==================== 5. INICIAR SERVIÇO ====================
Write-Host "[5/5] Iniciando serviço..." -ForegroundColor Cyan
NET START WazuhSvc

Start-Sleep -Seconds 3
$wazuhSvc = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($wazuhSvc -and $wazuhSvc.Status -eq "Running") {
    Write-Host "`nDeploy concluído: $env:COMPUTERNAME (ossec.conf completo aplicado)" -ForegroundColor Green
} else {
    Write-Host "`nATENÇÃO: WazuhSvc não rodando em $env:COMPUTERNAME" -ForegroundColor Red
}

# Limpeza local (os arquivos originais continuam no share)
Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
if ($SmbUser -ne "") { Remove-PSDrive -Name "S3Deploy" -ErrorAction SilentlyContinue }
