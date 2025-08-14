#!/bin/bash

# Script completo de instalação para NFC Reader no Raspberry Pi
# Inclui Java, drivers ACR122U e configuração do serviço

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuração
INSTALL_DIR="/opt/nfc-reader"
JAR_NAME="nfc-reader.jar"
SERVICE_NAME="nfc-reader"

# URL do JAR (modifique com a URL real)
JAR_URL="https://ewas1.pcloud.com/D4ZIQqopEZMeelRf7ZZZBpa6VkZ2ZZtdzZkZ3mqHZT4ZiLZcVZzwIEZfPqWhxMjJ2Sdn08T34Kpgz4RMOBy/reader.jar"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Instalação Completa NFC Reader${NC}"
echo -e "${BLUE}  com suporte ACR122U${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Execute como root: sudo $0${NC}"
    exit 1
fi

# 1. Detectar usuário padrão
echo -e "${YELLOW}[1/11] Detectando usuário...${NC}"
DEFAULT_USER="root"
if ! id "$DEFAULT_USER" &>/dev/null; then
    for USER in ubuntu debian admin $SUDO_USER; do
        if id "$USER" &>/dev/null; then
            DEFAULT_USER="$USER"
            break
        fi
    done
fi
echo -e "${GREEN}✓ Usando usuário: $DEFAULT_USER${NC}"
echo

# 2. Atualizar sistema
echo -e "${YELLOW}[2/11] Atualizando sistema...${NC}"
apt-get update
echo -e "${GREEN}✓ Sistema atualizado${NC}"
echo

# 3. Instalar Java
echo -e "${YELLOW}[3/11] Verificando Java...${NC}"
if ! command -v java &> /dev/null; then
    echo "Instalando Java..."
    apt-get install -y default-jre-headless
    echo -e "${GREEN}✓ Java instalado${NC}"
else
    JAVA_VERSION=$(java -version 2>&1 | grep version | awk '{print $3}' | tr -d '"')
    echo -e "${GREEN}✓ Java já instalado: versão $JAVA_VERSION${NC}"
fi
echo

# 4. Instalar drivers ACR122U e PC/SC
echo -e "${YELLOW}[4/11] Instalando drivers ACR122U...${NC}"
apt-get install -y \
    pcscd \
    pcsc-tools \
    libpcsclite1 \
    libpcsclite-dev \
    libccid \
    libacsccid1 \
    libusb-1.0-0 \
    libusb-1.0-0-dev \
    libnfc-bin \
    libnfc-dev \
    libnfc-examples 2>/dev/null || true

echo -e "${GREEN}✓ Drivers instalados${NC}"
echo

# 5. Configurar udev rules e prevenir conflitos
echo -e "${YELLOW}[5/11] Configurando regras udev e prevenindo conflitos...${NC}"

# Remover drivers conflitantes
modprobe -r pn533_usb 2>/dev/null || true
modprobe -r pn533 2>/dev/null || true
modprobe -r nfc 2>/dev/null || true

# Criar blacklist para drivers conflitantes
cat > /etc/modprobe.d/blacklist-nfc.conf << 'EOF'
# Blacklist drivers NFC do kernel que conflitam com ACR122U
blacklist pn533
blacklist pn533_usb
blacklist nfc
EOF

# Criar regras udev
cat > /etc/udev/rules.d/99-acr122u.rules << 'EOF'
# ACR122U NFC Reader
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2200", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2214", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2215", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", ATTRS{idProduct}=="2216", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="072f", GROUP="pcscd", MODE="0660"
EOF

# Configurar libnfc para evitar conflitos
mkdir -p /etc/nfc
cat > /etc/nfc/libnfc.conf << 'EOF'
# Permitir introspecção de dispositivos
allow_intrusive_scan = true

# Não permitir autoscan (evita conflitos com pcscd)
allow_autoscan = false

# Configuração do ACR122U
device.name = "ACR122U"
device.connstring = "acr122_usb"
EOF

udevadm control --reload-rules
udevadm trigger

# Adicionar usuário aos grupos
usermod -a -G dialout,plugdev,pcscd $DEFAULT_USER 2>/dev/null || true

echo -e "${GREEN}✓ Permissões configuradas e conflitos prevenidos${NC}"
echo

# 6. Configurar e iniciar PC/SC
echo -e "${YELLOW}[6/11] Configurando PC/SC daemon...${NC}"

# Parar pcscd se estiver rodando
systemctl stop pcscd 2>/dev/null || true
killall -9 pcscd 2>/dev/null || true

# Limpar cache do pcscd
rm -rf /var/run/pcscd 2>/dev/null || true
rm -f /var/run/pcscd.* 2>/dev/null || true

# Habilitar e iniciar pcscd
systemctl enable pcscd
systemctl start pcscd
sleep 3

if systemctl is-active --quiet pcscd; then
    echo -e "${GREEN}✓ PC/SC daemon iniciado${NC}"
else
    echo -e "${YELLOW}⚠ PC/SC pode não ter iniciado corretamente${NC}"
fi
echo

# 7. Criar estrutura de diretórios
echo -e "${YELLOW}[7/11] Criando estrutura de diretórios...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/config"
echo -e "${GREEN}✓ Diretórios criados${NC}"
echo

# 8. Baixar JAR
echo -e "${YELLOW}[8/11] Baixando JAR do NFC Reader...${NC}"
if [ -f "$INSTALL_DIR/$JAR_NAME" ]; then
    echo "Removendo versão anterior..."
    rm -f "$INSTALL_DIR/$JAR_NAME"
fi

echo "URL: $JAR_URL"
wget -q --show-progress -O "$INSTALL_DIR/$JAR_NAME" "$JAR_URL"

if [ -f "$INSTALL_DIR/$JAR_NAME" ]; then
    echo -e "${GREEN}✓ JAR baixado com sucesso${NC}"
    
    # Verificar se é um arquivo JAR válido
    if file "$INSTALL_DIR/$JAR_NAME" | grep -q "Java archive"; then
        echo -e "${GREEN}✓ JAR válido${NC}"
    else
        echo -e "${YELLOW}⚠ Arquivo pode não ser um JAR válido${NC}"
    fi
else
    echo -e "${RED}✗ Erro ao baixar JAR${NC}"
    exit 1
fi
echo

# 9. Criar arquivo de configuração
echo -e "${YELLOW}[9/11] Criando arquivo de configuração...${NC}"

# Solicitar porta do WebSocket
echo -e "${BLUE}Configuração do WebSocket${NC}"
echo "Host padrão: nfcbrasil.top"
echo
read -p "Digite a porta do WebSocket (padrão: 16007): " WS_PORT
WS_PORT=${WS_PORT:-16007}

# Validar se é um número
if ! [[ "$WS_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}⚠ Porta inválida, usando padrão: 16007${NC}"
    WS_PORT=16007
fi

echo -e "${GREEN}✓ Porta configurada: $WS_PORT${NC}"

cat > "$INSTALL_DIR/config.properties" << EOF
# Configurações do WebSocket
websocket.host=nfcbrasil.top
websocket.port=$WS_PORT
websocket.path=/websocket1
websocket.protocol=ws

# Token de autenticação
auth.token=nfc_token

# Tipo de operação
operation.type=read

# Configurações de reconexão
reconnect.delay=5000
reconnect.max_attempts=0

# Configurações de heartbeat (em milissegundos)
heartbeat.interval=30000
EOF

echo -e "${GREEN}✓ Arquivo de configuração criado com porta $WS_PORT${NC}"
echo

# 10. Criar serviço systemd
echo -e "${YELLOW}[10/11] Configurando serviço systemd...${NC}"

cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=NFC Reader Service with ACR122U Support
After=network.target pcscd.service
Requires=pcscd.service
Wants=network-online.target

[Service]
Type=simple
User=$DEFAULT_USER
Group=$DEFAULT_USER
WorkingDirectory=$INSTALL_DIR
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/java -jar $INSTALL_DIR/$JAR_NAME
Restart=always
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/service.log
StandardError=append:$INSTALL_DIR/logs/service-error.log

# Ambiente
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Limites
LimitNOFILE=4096
TimeoutStartSec=30
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✓ Serviço systemd criado${NC}"
echo

# 11. Criar scripts auxiliares
echo -e "${YELLOW}[11/11] Criando scripts auxiliares...${NC}"

# Script de teste
cat > $INSTALL_DIR/test_nfc.sh << 'EOF'
#!/bin/bash

echo "=== Teste do Sistema NFC ==="
echo

echo "1. PC/SC Status:"
if systemctl is-active --quiet pcscd; then
    echo "✓ PC/SC rodando"
else
    echo "✗ PC/SC parado"
fi

echo
echo "2. Leitores conectados:"
pcsc_scan -n | head -n 10

echo
echo "3. Dispositivos USB ACR122U:"
lsusb | grep -i "072f" || echo "Nenhum ACR122U detectado"

echo
echo "4. Serviço NFC Reader:"
systemctl status nfc-reader --no-pager | head -n 5
EOF

chmod +x $INSTALL_DIR/test_nfc.sh

# Script de status rápido
cat > /usr/local/bin/nfc-status << 'EOF'
#!/bin/bash

echo "=== NFC Reader Status ==="
echo
echo "Serviço: $(systemctl is-active nfc-reader)"
echo "PC/SC: $(systemctl is-active pcscd)"
echo
if lsusb | grep -q "072f"; then
    echo "ACR122U: Conectado"
else
    echo "ACR122U: Não detectado"
fi
echo
echo "Logs recentes:"
tail -n 5 /opt/nfc-reader/logs/service.log 2>/dev/null || echo "Sem logs"
EOF

chmod +x /usr/local/bin/nfc-status

# Script de desinstalação
cat > $INSTALL_DIR/uninstall.sh << EOF
#!/bin/bash

echo "Desinstalando NFC Reader..."

# Parar e desabilitar serviço
systemctl stop $SERVICE_NAME
systemctl disable $SERVICE_NAME
rm -f /etc/systemd/system/$SERVICE_NAME.service

# Remover arquivos
rm -rf $INSTALL_DIR
rm -f /usr/local/bin/nfc-status

# Recarregar systemd
systemctl daemon-reload

echo "✓ Desinstalação concluída"
EOF

chmod +x $INSTALL_DIR/uninstall.sh

# Aplicar permissões
chown -R $DEFAULT_USER:$DEFAULT_USER $INSTALL_DIR
chmod 755 $INSTALL_DIR
chmod 644 $INSTALL_DIR/$JAR_NAME

echo -e "${GREEN}✓ Scripts auxiliares criados${NC}"
echo

# Habilitar e iniciar serviço
echo -e "${YELLOW}Habilitando serviço...${NC}"
systemctl daemon-reload
systemctl enable $SERVICE_NAME.service
echo -e "${GREEN}✓ Serviço habilitado para auto-inicialização${NC}"
echo

# Perguntar se deseja iniciar agora
read -p "Deseja iniciar o serviço agora? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    systemctl start $SERVICE_NAME.service
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ Serviço iniciado com sucesso!${NC}"
    else
        echo -e "${RED}✗ Falha ao iniciar o serviço${NC}"
        echo "Use: systemctl status $SERVICE_NAME.service para mais detalhes"
    fi
fi

# Verificação final
echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Verificação Final${NC}"
echo -e "${BLUE}========================================${NC}"
echo

echo -e "${YELLOW}1. PC/SC Daemon:${NC}"
if systemctl is-active --quiet pcscd; then
    echo -e "${GREEN}✓ Rodando${NC}"
else
    echo -e "${RED}✗ Parado${NC}"
fi

echo -e "${YELLOW}2. ACR122U:${NC}"
if lsusb | grep -q "072f"; then
    echo -e "${GREEN}✓ Detectado${NC}"
    lsusb | grep "072f"
else
    echo -e "${YELLOW}⚠ Não detectado (conecte o leitor)${NC}"
fi

echo -e "${YELLOW}3. Serviço NFC Reader:${NC}"
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓ Rodando${NC}"
else
    echo -e "${YELLOW}⚠ Não está rodando${NC}"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Instalação Concluída!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}Comandos úteis:${NC}"
echo "  nfc-status                       # Status rápido"
echo "  $INSTALL_DIR/test_nfc.sh         # Teste completo"
echo "  sudo systemctl status $SERVICE_NAME     # Status detalhado"
echo "  sudo systemctl restart $SERVICE_NAME    # Reiniciar serviço"
echo "  sudo journalctl -u $SERVICE_NAME -f     # Ver logs"
echo "  pcsc_scan                        # Verificar leitores"
echo "  nfc-list                         # Listar dispositivos NFC"
echo
echo -e "${RED}IMPORTANTE:${NC}"
echo "Se o ACR122U não foi detectado, conecte-o e execute:"
echo "  sudo systemctl restart pcscd"
echo "  sudo systemctl restart $SERVICE_NAME"
echo
