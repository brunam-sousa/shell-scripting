#!/bin/bash

# auditd.sh: esse script não verifica a instalação/configuraçao do rsyslog. Para tal finalidade podemos utilizar o script que está na wiki
# para instalação do QRadar
# Pré requisitos:
# - auditd deve estar instalado nos servidores sem acesso à internet
# - nos servidores sem acesso a Internet o arquivo audit.rules deve estar previamente presente em "/tmp"

# Parametros:
# - local: para servidores sem acesso a Internet, ira utilizar o audit.rules de /tmp
# Exemplo chamada: ./auditd.sh local


# Verificar a distribuição
check_distribution() {
    # Determinar a distribuição do servidor
    # A sintaxe $(...) é preferível à antiga forma com crase (`...`), ela executa o comando(s) e guarda na variavel
    distribution=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
    
    
    case $distribution in
        "centos"|"rhel"|"fedora")
            echo "Distribuição detectada: $distribution"
            conf_global_bash="/etc/bash.bashrc"
            command_install_audit="yum install -y audit"
            ;;
        "ubuntu"|"debian"|"linuxmint")
            echo "Distribuição detectada: $distribution"
            conf_global_bash="/etc/profile.d/"
            command_install_audit="apt update && apt install -y auditd"
            ;;
        *)
            echo "Distribuição não reconhecida. O valor de 'ID' foi detectado como: $distribution"
            exit 1  # Encerra o script caso a distribuição não seja reconhecida
            ;;
    esac
}

# Verificar se o auditd está instalado
check_auditd_installed() {
    # &> é uma maneira curta de redirecionar stdout e stderr para o mesmo destino (arquivo ou outro fluxo).
    # command -v não imprime nada diretamente para a saída padrão Ele apenas retorna um código de saída que é interpretado pelo if
    # &> /dev/null apenas garante que qualquer possível saída (como mensagens de erro) seja descartada.
    if command -v auditd &> /dev/null; then
        echo "O auditd já está instalado no sistema."
        return 0
    else
        echo "O auditd não está instalado. Iniciando a instalação..."
        return 1
    fi
}

# Instalar o auditd
install_auditd() {
    echo "Executando: $command_install_audit"
    if eval $command_install_audit; then
        echo "O auditd foi instalado com sucesso."
    else
        # >&2: Redireciona a mensagem de erro para o stderr, que é o fluxo de saída de erro.
        echo "Erro ao tentar instalar o auditd. O script será encerrado." >&2
        exit 1  # Encerra o script caso a instalação falhe
    fi
}

configure_auditd(){
    # Definindo caminhos em variáveis
    local rules_dir="/etc/audit/rules.d"
    local audit_rules_file="$rules_dir/audit.rules"
    local backup_file="$rules_dir/audit.rules.old"
    local tmp_rules_file="/tmp/audit.rules"
    local url_audit_rules="https://raw.githubusercontent.com/Neo23x0/auditd/refs/heads/master/audit.rules"

       if [ -f $audit_rules_file ]; then
            echo "Criando backup do arquivo de regras: $backup_file"
            cp -p $audit_rules_file $backup_file && { echo "Backup $backup_file criado"; rm -f $audit_rules_file; }
        else
            echo "Arquivo de regras não encontrado, sera criado um novo."            
        fi

        # define /etc/audit/rules.d/audit.rules
        case $1 in
            "internet")
                # Comandos a serem executados quando o valor de $variavel corresponder a padrão1
                # Verifica se o curl está instalado
                if [ command -v curl ] &> /dev/null; then
                    echo "Usando curl para baixar o arquivo..."
                    curl -O $url_audit_rules
                # Se o curl não estiver instalado, verifica o wget
                elif command -v wget &> /dev/null; then
                    echo "Usando wget para baixar o arquivo..."
                    wget -O $audit_rules_file $url_audit_rules
                else
                    echo "Erro: Nenhum dos programas curl ou wget está instalado." >&2
                    return 1
                fi
            ;;
            "local")
                # Comandos a serem executados quando o valor de $variavel corresponder a padrão2
                # arquivo audit.rules deve estar previamente em /tmp
                cp $tmp_rules_file $audit_rules_file
            ;;
            *)
                # Comandos a serem executados se nenhum dos padrões anteriores corresponder
                echo "A chamada do script deve definir se a instalação do auditd será local ou via Internet"
                exit 1
            ;;
            esac
 
}


# configurar syslog.conf
conf_plugin_syslog(){

    # Define o caminho do arquivo de configuração syslog.conf
    path_plugin_syslog=$( [ -d "/etc/audisp/plugins.d" ] && echo "/etc/audisp/plugins.d/" || echo "/etc/audit/plugins.d/" )

    # Grava conteúdo no syslog.conf
    # cat <<EOL > arquivo sobreescreve o conteúdo entre <<EOL e o delimitador EOL no arquivo
    # cat <<EOL >> arquivo adiciona o conteúdo entre <<EOL e o delimitador EOL no final do arquivo 
    cat <<EOL > "$path_plugin_syslog/syslog.conf"
active = yes
direction = out
path = builtin_syslog
type = builtin
args = LOG_INFO
format = string
EOL

    # Verifica se o arquivo foi gravado corretamente
    if [ $? -eq 0 ]; then
        echo "Arquivo syslog.conf foi criado com sucesso em $path_plugin_syslog"
    else
        echo "Erro ao criar o arquivo syslog.conf" >&2
        exit 1 # Encerra o script caso a instalação falhe
    fi

}


# Reiniciar Serviços
restart_services(){
    service auditd restart
    service rsyslog restart
    service rsyslog status
}

# Configuração da Bash para Envio de Eventos
configure_bash(){
    local bash_conf_file="/etc/rsyslog.d/bash.conf"
    
    cat <<EOL >> $conf_global_bash
export PROMPT_COMMAND='RETRN_VAL=$?;logger -p local6.debug "$(whoami) [$$]: $(history 1 | sed "s/^[ ][0-9]\+[ ]//" ) [$RETRN_VAL]"'
EOL
    
    cat <<EOL > $bash_conf_file
    # && { echo "falha ao criar arquivo $bash_conf_file"; exit 1 }
echo "local6.* /var/log/secure" > /etc/rsyslog.d/bash.conf
EOL
   
    service rsyslog restart
    source $conf_global_bash
}

# Função principal que gerencia o fluxo
main() {
    # Chama a função para verificar a distribuição
    check_distribution
    
    # Verifica se o auditd está instalado 
    # check_auditd_installed retorna 0 para instalado ou 1 para nao instalado
    # O operador || em executa o comando à direita somente se o comando à esquerda falhar (código diferente de 0)
    #check_auditd_installed || install_auditd
    installed_auditd=check_auditd_installed

    case $1 in
        "internet")
            # Comandos a serem executados quando o valor de $variavel corresponder a padrão1
            # Verifica se o curl está instalado
            if [ command -v curl ] &> /dev/null; then
                echo "Usando curl para baixar o arquivo..."
                curl -O $url_audit_rules
            # Se o curl não estiver instalado, verifica o wget
            elif command -v wget &> /dev/null; then
                echo "Usando wget para baixar o arquivo..."
                wget -O $audit_rules_file $url_audit_rules
            else
                echo "Erro: Nenhum dos programas curl ou wget está instalado." >&2
                return 1
            fi
        ;;
        "local")
            #valida se arquivo de regras do audit esta em /tmp caso a instalacao seja local        
            if [ ! -f "/tmp/audit.rules" ]; then
                echo "O arquivo audit.rules não esta no /tmp, terminando execução..."
                exit 1
            elif [ ! installed_auditd ]; then
                echo "O audit não está previamente instalado, terminando execução..."
                exit 1
            fi

        ;;
        *)
            # Comandos a serem executados se nenhum dos padrões anteriores corresponder
            echo "A chamada do script deve definir se a instalação do auditd será local ou via Internet"
            exit 1
        ;;
    esac

    # auditd instalado e se a instalaçao for local o audit.rules já está em /tmp
    configure_auditd
    # configura plugin syslog
    conf_plugin_syslog
    # configurar bash
    configure_bash
    # restart dos serviços
    restart_services
}

# Ativa a saída imediata para erros (caso qualquer comando falhe, o script é interrompido)
set -e

# Executa a função principal
main "$1"