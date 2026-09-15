#!/bin/bash
# ==============================================================================
# Deploy padrão S3 - auditd + Wazuh Agent para Linux
# Funciona em Debian/Ubuntu (apt) e RHEL/CentOS/Fedora (yum/dnf)
# Uso: sudo ./deploy-s3-agent-linux.sh
#
# Este script espera a estrutura de pastas do pacote original:
#     pacote-deploy-wazuh-sysmon/
#     ├── configs/
#     │   ├── audit.rules
#     │   └── ossec-agent-linux.conf
#     └── scripts/
#         └── deploy-s3-agent-linux.sh   <- este arquivo
#
# Antes de usar: ajuste WAZUH_MANAGER_IP e WAZUH_AGENT_GROUP abaixo.
# ==============================================================================

set -e

# ==================== CONFIG (ajuste antes de rodar) ====================
WAZUH_MANAGER_IP="IP_DO_SEU_MANAGER"
WAZUH_AGENT_GROUP="linux-endpoints"
WAZUH_REPO_KEY_URL="https://packages.wazuh.com/key/GPG-KEY-WAZUH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/../configs"
AUDIT_RULES_SRC="$CONFIGS_DIR/audit.rules"
OSSEC_CONF_SRC="$CONFIGS_DIR/ossec-agent-linux.conf"
OSSEC_CONF_DEST="/var/ossec/etc/ossec.conf"

# ==================== 0. VALIDAÇÕES ====================
if [ "$EUID" -ne 0 ]; then
    echo "ERRO: rode este script como root (sudo)." >&2
    exit 1
fi

if [ ! -f "$AUDIT_RULES_SRC" ]; then
    echo "ERRO: audit.rules não encontrado em $CONFIGS_DIR. Abortando." >&2
    exit 1
fi

if [ ! -f "$OSSEC_CONF_SRC" ]; then
    echo "ERRO: ossec-agent-linux.conf não encontrado em $CONFIGS_DIR. Abortando." >&2
    exit 1
fi

if [ "$WAZUH_MANAGER_IP" == "IP_DO_SEU_MANAGER" ]; then
    echo "ERRO: preencha a variável WAZUH_MANAGER_IP no topo do script antes de rodar." >&2
    exit 1
fi

# Detecta o gerenciador de pacotes
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
else
    echo "ERRO: gerenciador de pacotes não reconhecido (apt/dnf/yum)." >&2
    exit 1
fi

echo "[0/6] Gerenciador de pacotes detectado: $PKG_MANAGER"

# ==================== 1. INSTALAR AUDITD ====================
echo "[1/6] Instalando auditd..."
case "$PKG_MANAGER" in
    apt)
        apt-get update -qq
        apt-get install -y auditd audispd-plugins
        ;;
    dnf)
        dnf install -y audit
        ;;
    yum)
        yum install -y audit
        ;;
esac

systemctl enable auditd
systemctl start auditd

# ==================== 2. APLICAR AS REGRAS DE AUDITORIA ====================
echo "[2/6] Aplicando audit.rules..."
mkdir -p /etc/audit/rules.d
cp "$AUDIT_RULES_SRC" /etc/audit/rules.d/s3-hardening.rules

# Se existir o augenrules (padrão em distros modernas), usa ele
if command -v augenrules >/dev/null 2>&1; then
    augenrules --load
else
    # Fallback: aplica direto via auditctl
    auditctl -R /etc/audit/rules.d/s3-hardening.rules
fi

systemctl restart auditd || service auditd restart

echo "Regras de auditoria aplicadas."

# ==================== 3. INSTALAR O AGENTE WAZUH ====================
echo "[3/6] Instalando o agente Wazuh..."
case "$PKG_MANAGER" in
    apt)
        curl -so /tmp/wazuh-gpg.key "$WAZUH_REPO_KEY_URL"
        gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import /tmp/wazuh-gpg.key
        chmod 644 /usr/share/keyrings/wazuh.gpg
        echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
        apt-get update -qq
        WAZUH_MANAGER="$WAZUH_MANAGER_IP" apt-get install -y wazuh-agent
        ;;
    dnf|yum)
        rpm --import "$WAZUH_REPO_KEY_URL"
        cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=$WAZUH_REPO_KEY_URL
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
        WAZUH_MANAGER="$WAZUH_MANAGER_IP" $PKG_MANAGER install -y wazuh-agent
        ;;
esac

# ==================== 4. APLICAR O ossec.conf COMPLETO ====================
echo "[4/6] Aplicando ossec-agent-linux.conf..."
sed "s/IP_DO_WAZUH_MANAGER/$WAZUH_MANAGER_IP/g" "$OSSEC_CONF_SRC" > "$OSSEC_CONF_DEST"
chown root:wazuh "$OSSEC_CONF_DEST" 2>/dev/null || true

# ==================== 5. REGISTRAR NO GRUPO (se agent-auth disponível) ====================
echo "[5/6] Registrando agente no grupo '$WAZUH_AGENT_GROUP'..."
if [ -x /var/ossec/bin/agent-auth ]; then
    /var/ossec/bin/agent-auth -m "$WAZUH_MANAGER_IP" -G "$WAZUH_AGENT_GROUP" || \
        echo "AVISO: agent-auth falhou — registre manualmente no Manager se necessário."
fi

# ==================== 6. INICIAR SERVIÇO ====================
echo "[6/6] Iniciando o serviço do agente..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

sleep 3
if systemctl is-active --quiet wazuh-agent; then
    echo ""
    echo "✅ Deploy concluído com sucesso. Agente rodando, auditd ativo, ossec.conf completo aplicado."
else
    echo ""
    echo "⚠️  ATENÇÃO: o serviço wazuh-agent não está ativo. Verifique: /var/ossec/logs/ossec.log" >&2
    exit 1
fi
