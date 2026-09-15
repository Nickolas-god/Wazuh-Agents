<div align="center">

# 🛡️ Wazuh Agent + Sysmon — Deploy Windows

**Configuração e automação para implantar detecção alinhada ao MITRE ATT&CK em endpoints Windows**

![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-4.9-3AAFCB?logo=wazuh&logoColor=white)
![Sysmon](https://img.shields.io/badge/Sysmon-v13%2B-333333?logo=windows-terminal&logoColor=white)
![MITRE ATT&CK](https://img.shields.io/badge/MITRE-ATT%26CK-red)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 📋 Sumário

- [O que este pacote faz](#-o-que-este-pacote-faz)
- [Conteúdo](#-conteúdo)
- [Antes de usar](#️-antes-de-usar)
- [Instalação rápida](#-instalação-rápida-uma-máquina)
- [Instalação em massa](#-instalação-em-massa)
- [Configuração centralizada](#-configuração-centralizada-recomendado)
- [Estrutura de pastas](#-estrutura-de-pastas)
- [Referências](#-referências)

---

## 🎯 O que este pacote faz

Ao rodar os scripts deste repositório em um endpoint Windows, ele fica com:

- ✅ **Sysmon** instalado e configurado para detectar dump de credencial (`T1003`), DLL sideloading (`T1574.002`), persistência via registro, pipes de ferramentas de C2 e muito mais
- ✅ **Agente Wazuh** instalado, com FIM em tempo real, coleta de PowerShell Script Block, logs do Sysmon/Defender/Task Scheduler já integrados
- ✅ Tudo já **enviando eventos para o Wazuh Manager** da empresa/cliente, sem etapas manuais adicionais

---

## 📦 Conteúdo

### Windows

| Arquivo | Pasta | Para que serve |
|---|---|---|
| `sysmonconfig-full.xml` | `configs/` | Config do Sysmon (base [SwiftOnSecurity](https://github.com/SwiftOnSecurity/sysmon-config)) com `ProcessAccess` e `ImageLoad` habilitados |
| `ossec-agent-windows.conf` | `configs/` | Config do agente Wazuh: FIM em tempo real, PowerShell, Sysmon, Defender, Task Scheduler, registro reforçado |
| `deploy-s3-agent.ps1` | `scripts/` | Instala tudo baixando os instaladores da internet |
| `deploy-s3-agent-smb.ps1` | `scripts/` | Mesma coisa, mas puxando de um compartilhamento SMB (redes sem internet) |

### Linux

| Arquivo | Pasta | Para que serve |
|---|---|---|
| `audit.rules` | `configs/` | Regras do `auditd` (base [socfortress/Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules)) mapeadas com MITRE ATT&CK — equivalente ao papel do Sysmon no Windows |
| `ossec-agent-linux.conf` | `configs/` | Config do agente Wazuh: FIM com `whodata`, coleta do auditd/auth.log, SCA (CIS Benchmarks) |
| `deploy-s3-agent-linux.sh` | `scripts/` | Instala auditd + agente Wazuh (detecta apt/dnf/yum automaticamente) e aplica as duas configs |

---

## ⚙️ Antes de usar

> [!IMPORTANT]
> Preencha estas duas variáveis no topo de **cada** script antes de rodar:

**Windows** (`.ps1`):
```powershell
$WazuhManagerIP   = "IP_DO_SEU_MANAGER"
$WazuhAgentGroup  = "windows-endpoints"
```

**Linux** (`.sh`):
```bash
WAZUH_MANAGER_IP="IP_DO_SEU_MANAGER"
WAZUH_AGENT_GROUP="linux-endpoints"
```

No script SMB (Windows), preencha também `$SharePath` com o caminho do compartilhamento de rede.

> [!NOTE]
> Os arquivos em `configs/` **não precisam ser editados manualmente** — os scripts substituem o placeholder de IP automaticamente ao aplicar a configuração.

---

## 🚀 Instalação rápida (uma máquina)

**Windows** — como Administrador, dentro da pasta `scripts/`:
```powershell
.\deploy-s3-agent.ps1
```

**Linux** — como root, dentro da pasta `scripts/`:
```bash
sudo ./deploy-s3-agent-linux.sh
```

Os dois scripts seguem a mesma lógica:
1. Instalam a peça de coleta avançada (Sysmon no Windows / auditd no Linux) com a config completa
2. Instalam o agente Wazuh apontando pro Manager e grupo configurados
3. Substituem o `ossec.conf` padrão pela config completa do repositório
4. Iniciam o serviço e validam que subiu corretamente

> [!NOTE]
> O script Linux detecta automaticamente o gerenciador de pacotes (`apt`, `dnf` ou `yum`) — funciona em Debian/Ubuntu e RHEL/CentOS/Fedora sem precisar de ajuste manual.

---

## 🖧 Instalação em massa

| Método | Quando usar |
|---|---|
| **PowerShell Remoting** (`Invoke-Command`) | Máquinas com WinRM habilitado |
| **PsExec** | Domínio ou workgroup, sem precisar de WinRM |
| **SMB** (`deploy-s3-agent-smb.ps1`) | Rede do cliente sem saída para internet |

```powershell
Invoke-Command -ComputerName (Get-Content maquinas.txt) -FilePath .\deploy-s3-agent.ps1
```

---

## 🗂️ Configuração centralizada (recomendado)

Em vez de depender só do script, crie um grupo de agentes no Wazuh Manager:

```bash
sudo /var/ossec/bin/agent_groups -a -g windows-endpoints
```

Cole o conteúdo de `ossec-agent-windows.conf` (exceto a seção `<client>`) em:

```
/var/ossec/etc/shared/windows-endpoints/agent.conf
```

Assim, qualquer agente novo que entrar nesse grupo já recebe a configuração automaticamente — sem depender do script pra isso.

---

## 🌳 Estrutura de pastas

```
.
├── README.md
├── configs/
│   ├── sysmonconfig-full.xml
│   ├── ossec-agent-windows.conf
│   ├── audit.rules
│   └── ossec-agent-linux.conf
└── scripts/
    ├── deploy-s3-agent.ps1
    ├── deploy-s3-agent-smb.ps1
    └── deploy-s3-agent-linux.sh
```

---

## 📚 Referências

- [Wazuh Documentation](https://documentation.wazuh.com)
- [SwiftOnSecurity/sysmon-config](https://github.com/SwiftOnSecurity/sysmon-config)
- [socfortress/Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules)
- [MITRE ATT&CK](https://attack.mitre.org)

---

<div align="center">

*Mantido pela equipe de segurança para uso interno em implantações de clientes.*

</div>
