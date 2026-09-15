#Requires -RunAsAdministrator
<#
    Deploy padrão S3 - Sysmon + Wazuh Agent (via internet)
    Funciona em máquinas com ou sem domínio (independente de GPO/RMM).
    Uso: rodar localmente como Admin, ou via Invoke-Command / cópia manual.

    Este script espera a estrutura de pastas do pacote original:
        pacote-deploy-wazuh-sysmon/
        ├── configs/
        │   ├── sysmonconfig-full.xml
        │   └── ossec-agent-windows.conf
        └── scripts/
            └── deploy-s3-agent.ps1   <- este arquivo

    Antes de usar: ajuste WazuhManagerIP e WazuhAgentGroup abaixo.
#>

# ==================== CONFIG (ajuste antes de rodar) ====================
$WazuhManagerIP   = "IP_DO_SEU_MANAGER"          # IP ou hostname do Wazuh Manager
$WazuhAgentGroup  = "windows-endpoints"          # Grupo criado no Manager (agent_groups -a -g <nome>)
$WazuhAgentMSIUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi"
$SysmonZipUrl     = "https://download.sysinternals.com/files/Sysmon.zip"

# Caminhos dos arquivos de config, relativos à pasta do pacote (../configs)
$ConfigsDir     = Join-Path $PSScriptRoot "..\configs"
$SysmonConfig   = Join-Path $ConfigsDir "sysmonconfig-full.xml"
$OssecConfig    = Join-Path $ConfigsDir "ossec-agent-windows.conf"
$OssecConfPath  = "C:\Program Files (x86)\ossec-agent\ossec.conf"

$WorkDir = "C:\S3-Deploy"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ==================== 0. VALIDAR ARQUIVOS DE CONFIG ====================
if (-Not (Test-Path $SysmonConfig)) {
    Write-Host "ERRO: sysmonconfig-full.xml não encontrado em $ConfigsDir. Abortando." -ForegroundColor Red
    exit 1
}
if (-Not (Test-Path $OssecConfig)) {
    Write-Host "ERRO: ossec-agent-windows.conf não encontrado em $ConfigsDir. Abortando." -ForegroundColor Red
    exit 1
}
if ($WazuhManagerIP -eq "IP_DO_SEU_MANAGER") {
    Write-Host "ERRO: preencha a variável `$WazuhManagerIP` no topo do script antes de rodar." -ForegroundColor Red
    exit 1
}

# ==================== 1. INSTALAR SYSMON ====================
Write-Host "[1/5] Baixando Sysmon..." -ForegroundColor Cyan
$SysmonZip = "$WorkDir\Sysmon.zip"
Invoke-WebRequest -Uri $SysmonZipUrl -OutFile $SysmonZip
Expand-Archive -Path $SysmonZip -DestinationPath "$WorkDir\Sysmon" -Force
Copy-Item $SysmonConfig "$WorkDir\Sysmon\sysmonconfig-full.xml" -Force

Write-Host "[2/5] Instalando Sysmon com a config..." -ForegroundColor Cyan
$existingSysmon = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if ($existingSysmon) {
    & "$WorkDir\Sysmon\Sysmon64.exe" -c "$WorkDir\Sysmon\sysmonconfig-full.xml"
} else {
    & "$WorkDir\Sysmon\Sysmon64.exe" -accepteula -i "$WorkDir\Sysmon\sysmonconfig-full.xml"
}

Start-Sleep -Seconds 3
if (Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue) {
    Write-Host "Sysmon instalado e rodando." -ForegroundColor Green
} else {
    Write-Host "ATENÇÃO: serviço Sysmon64 não encontrado após instalação." -ForegroundColor Yellow
}

# ==================== 2. INSTALAR WAZUH AGENT ====================
Write-Host "[3/5] Baixando e instalando Wazuh Agent..." -ForegroundColor Cyan
$WazuhMSI = "$WorkDir\wazuh-agent.msi"
Invoke-WebRequest -Uri $WazuhAgentMSIUrl -OutFile $WazuhMSI

$msiArgs = "/i `"$WazuhMSI`" /q WAZUH_MANAGER='$WazuhManagerIP' WAZUH_AGENT_GROUP='$WazuhAgentGroup'"
Start-Process msiexec.exe -ArgumentList $msiArgs -Wait

# Garante que o serviço não subiu ainda com o ossec.conf básico do instalador
Stop-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue

# ==================== 3. APLICAR O ossec.conf COMPLETO ====================
Write-Host "[4/5] Aplicando ossec-agent-windows.conf (FIM, PowerShell, Sysmon, registro)..." -ForegroundColor Cyan
$ossecContent = Get-Content -Path $OssecConfig -Raw
$ossecContent = $ossecContent -replace "IP_DO_WAZUH_MANAGER", $WazuhManagerIP
Set-Content -Path $OssecConfPath -Value $ossecContent -Encoding UTF8 -Force

# ==================== 4. INICIAR SERVIÇO ====================
Write-Host "[5/5] Iniciando serviço do agente..." -ForegroundColor Cyan
NET START WazuhSvc

Start-Sleep -Seconds 3
$wazuhSvc = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($wazuhSvc -and $wazuhSvc.Status -eq "Running") {
    Write-Host "`nDeploy concluído com sucesso. Agente rodando, no grupo '$WazuhAgentGroup', com ossec.conf completo aplicado." -ForegroundColor Green
} else {
    Write-Host "`nATENÇÃO: serviço WazuhSvc não está rodando. Verifique logs em C:\Program Files (x86)\ossec-agent\ossec.log" -ForegroundColor Red
}

# Limpeza
Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
