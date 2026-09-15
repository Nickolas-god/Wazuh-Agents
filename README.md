# Wazuh Agent + Sysmon — Deploy Windows

Pacote de configuração e automação para implantar o agente Wazuh e o Sysmon em endpoints Windows, com detecção alinhada ao MITRE ATT&CK.

## O que tem aqui

| Arquivo | Pasta | Para que serve |
|---|---|---|
| `sysmonconfig-full.xml` | `configs/` | Configuração do Sysmon (base [SwiftOnSecurity](https://github.com/SwiftOnSecurity/sysmon-config)), com `ProcessAccess` e `ImageLoad` habilitados para detectar dump de credencial (T1003) e DLL sideloading (T1574.002). |
| `ossec-agent-windows.conf` | `configs/` | Configuração do agente Wazuh para Windows: FIM em tempo real, coleta de PowerShell Script Block, Sysmon, Windows Defender, Task Scheduler e monitoramento de registro reforçado. |
| `deploy-s3-agent.ps1` | `scripts/` | Instala Sysmon + Wazuh Agent baixando os instaladores da internet, e já aplica as duas configs completas acima. |
| `deploy-s3-agent-smb.ps1` | `scripts/` | Mesma função, mas busca os instaladores e configs em um compartilhamento SMB — para redes sem saída à internet. |

## Antes de usar

Preencha nas duas primeiras linhas de cada script `.ps1`:

```powershell
$WazuhManagerIP   = "IP_DO_SEU_MANAGER"
$WazuhAgentGroup  = "windows-endpoints"
```

No script SMB, preencha também `$SharePath` com o caminho do compartilhamento de rede.

Os arquivos em `configs/` **não precisam ser editados manualmente** — os scripts substituem o placeholder de IP automaticamente ao aplicar a configuração.

## Instalação rápida (uma máquina)

```powershell
# Como Administrador, na pasta scripts/
.\deploy-s3-agent.ps1
```

Isso instala o Sysmon com a config completa, instala o agente Wazuh, substitui o `ossec.conf` padrão pelo `ossec-agent-windows.conf` completo (com o IP já preenchido), e inicia o serviço.

## Instalação em massa

- **PowerShell Remoting**: `Invoke-Command -ComputerName (Get-Content maquinas.txt) -FilePath .\deploy-s3-agent.ps1`
- **PsExec**: funciona em domínio ou workgroup, sem precisar de WinRM habilitado.
- **SMB + `deploy-s3-agent-smb.ps1`**: quando a rede do cliente não tem saída para internet.

## Configuração centralizada (recomendado para múltiplos endpoints)

Em vez de depender só do script, crie um grupo de agentes no Wazuh Manager:

```bash
sudo /var/ossec/bin/agent_groups -a -g windows-endpoints
```

E cole o conteúdo de `ossec-agent-windows.conf` (exceto a seção `<client>`) em:

```
/var/ossec/etc/shared/windows-endpoints/agent.conf
```

Assim, qualquer agente novo que entrar nesse grupo já recebe a configuração automaticamente.

## Estrutura de pastas

```
.
├── README.md
├── configs/
│   ├── sysmonconfig-full.xml
│   └── ossec-agent-windows.conf
└── scripts/
    ├── deploy-s3-agent.ps1
    └── deploy-s3-agent-smb.ps1
```

## Referências

- [Wazuh Documentation](https://documentation.wazuh.com)
- [SwiftOnSecurity/sysmon-config](https://github.com/SwiftOnSecurity/sysmon-config)
- [MITRE ATT&CK](https://attack.mitre.org)
