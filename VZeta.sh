#!/usr/bin/env bash

# Colores para la consola
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
GRAY="\033[90m"
NC="\033[0;m" # Sin Color

DEPLOY_FILE=".aws_deployment"

# Función auxiliar para pausar y limpiar la pantalla
press_enter_to_continue() {
    echo -e ""
    read -p "Presiona [Enter] para continuar..." temp
    clear
}

# Buscar despliegue activo en AWS si se clonó de cero y se perdió .aws_deployment
detect_active_deployment_if_missing() {
    # Si el archivo .aws_deployment ya existe, no es necesario escanear
    if [ -f "$DEPLOY_FILE" ]; then
        local INST_CHECK
        INST_CHECK=$(grep 'INSTANCE_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
        if [ -n "$INST_CHECK" ]; then
            return 0
        fi
    fi

    # Si disponemos de AWS CLI y credenciales activas en CloudShell
    if command -v aws &> /dev/null && aws sts get-caller-identity &>/dev/null; then
        echo -e "${BLUE}[INFO] Buscando despliegue \"vzeta-stack-eft\"...${NC}"
        
        local INSTANCE_ID=""
        local PUBLIC_IP=""
        local SG_ID=""
        local STATE=""

        local AWS_INFO
        AWS_INFO=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=vzeta-stack-eft" \
            --query "Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]" \
            --output text 2>/dev/null)
        
        if [ -n "$AWS_INFO" ] && [ "$AWS_INFO" != "None" ] && [ "$AWS_INFO" != "" ]; then
            INSTANCE_ID=$(echo "$AWS_INFO" | awk '{print $1}')
            STATE=$(echo "$AWS_INFO" | awk '{print $2}')
            PUBLIC_IP=$(echo "$AWS_INFO" | awk '{print $3}')
        fi

        # Si la instancia está en estado stopped, ofrecer iniciarla
        if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ] && [ "$STATE" = "stopped" ]; then
            echo -e "${YELLOW}[INFO] Se detectó tu instancia EC2 'vzeta-stack-eft' en estado DETENIDA (stopped).${NC}"
            read -p "¿Deseas iniciar la instancia EC2 ahora? (s/n): " RESP
            if [[ "$RESP" =~ ^[sS]$ ]]; then
                echo -e "${BLUE}[INFO] Iniciando instancia EC2 $INSTANCE_ID...${NC}"
                aws ec2 start-instances --instance-ids "$INSTANCE_ID" &>/dev/null
                echo -e "${BLUE}[INFO] Esperando a que la instancia esté en estado de ejecución (running)...${NC}"
                aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
                
                # Obtener la IP pública actual
                PUBLIC_IP=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --query "Reservations[0].Instances[0].PublicIpAddress" \
                    --output text 2>/dev/null | tr -d '\r\n ')
                STATE="running"
            fi
        fi

        # Si la instancia está activa (running), buscar sus demás datos y guardarlos
        if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ] && [ "$STATE" = "running" ]; then
            local DETECTED_SG_ID
            DETECTED_SG_ID=$(aws ec2 describe-instances \
                --filters "Name=instance-id,Values=$INSTANCE_ID" \
                --query "Reservations[*].Instances[*].SecurityGroups[0].GroupId" \
                --output text 2>/dev/null | tr -d '\r\n ')
            if [ -n "$DETECTED_SG_ID" ] && [ "$DETECTED_SG_ID" != "None" ] && [ "$DETECTED_SG_ID" != "" ]; then
                SG_ID="$DETECTED_SG_ID"
            fi
            
            # Fallback del Security Group por nombre
            if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
                local DETECTED_SG_ID
                DETECTED_SG_ID=$(aws ec2 describe-security-groups \
                    --filters "Name=group-name,Values=vzeta-security-group" \
                    --query "SecurityGroups[0].GroupId" \
                    --output text 2>/dev/null | tr -d '\r\n ')
                if [ -n "$DETECTED_SG_ID" ] && [ "$DETECTED_SG_ID" != "None" ] && [ "$DETECTED_SG_ID" != "" ]; then
                    SG_ID="$DETECTED_SG_ID"
                fi
            fi

            # Buscar EIP Allocation ID por tag si existe
            local DETECTED_EIP_ALLOC_ID
            DETECTED_EIP_ALLOC_ID=$(aws ec2 describe-addresses \
                --filters "Name=tag:Name,Values=vzeta-eip-eft" \
                --query "Addresses[0].AllocationId" \
                --output text 2>/dev/null | tr -d '\r\n ')

            # Si encontramos EIP pero no está asociada, asociar
            if [ -n "$DETECTED_EIP_ALLOC_ID" ] && [ "$DETECTED_EIP_ALLOC_ID" != "None" ] && [ "$DETECTED_EIP_ALLOC_ID" != "" ]; then
                local ASSOC_CHECK
                ASSOC_CHECK=$(aws ec2 describe-addresses \
                    --allocation-ids "$DETECTED_EIP_ALLOC_ID" \
                    --query "Addresses[0].AssociationId" \
                    --output text 2>/dev/null | tr -d '\r\n ')
                if [ -z "$ASSOC_CHECK" ] || [ "$ASSOC_CHECK" = "None" ] || [ "$ASSOC_CHECK" = "" ]; then
                    aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$DETECTED_EIP_ALLOC_ID" &>/dev/null
                fi
                # Re-obtener IP pública para estar seguro de que es la EIP
                PUBLIC_IP=$(aws ec2 describe-addresses \
                    --allocation-ids "$DETECTED_EIP_ALLOC_ID" \
                    --query "Addresses[0].PublicIp" \
                    --output text 2>/dev/null | tr -d '\r\n ')
            fi

            if [ -n "$SG_ID" ] && [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
                echo "INSTANCE_ID=$INSTANCE_ID" > "$DEPLOY_FILE"
                echo "SG_ID=$SG_ID" >> "$DEPLOY_FILE"
                if [ -n "$DETECTED_EIP_ALLOC_ID" ] && [ "$DETECTED_EIP_ALLOC_ID" != "None" ] && [ "$DETECTED_EIP_ALLOC_ID" != "" ]; then
                    echo "EIP_ALLOC_ID=$DETECTED_EIP_ALLOC_ID" >> "$DEPLOY_FILE"
                fi
                echo "PUBLIC_IP=$PUBLIC_IP" >> "$DEPLOY_FILE"
                echo -e "${GREEN}[OK] Estado de despliegue recuperado desde AWS (IP: $PUBLIC_IP).${NC}"
            fi
        fi
    fi
}

# Limpiar pantalla al iniciar el script y escanear despliegues activos
clear
detect_active_deployment_if_missing

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}              VZETA - DESPLIEGUE Examen Final Transversal             ${NC}"
echo -e "${BLUE}          Asignatura: Infraestructura de Aplicaciones I (INY1105)     ${NC}"
echo -e "${BLUE}          Docente: Rodrigo Aguilar G.                                 ${NC}"
echo -e "${BLUE}          Estudiante: Hugo Cuellar                                    ${NC}"
echo -e "${BLUE}======================================================================${NC}"
# Función para cargar u obtener credenciales de AWS
setup_aws_credentials() {
    export AWS_DEFAULT_REGION="us-east-1"
    
    # Verificar si disponemos de credenciales activas en AWS CLI (ej: en CloudShell)
    echo -e "${BLUE}[INFO] Validando conexión con AWS...${NC}"
    aws sts get-caller-identity --query "Arn" --output text &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] Conectado exitosamente a AWS (Entorno pre-autenticado detectado).${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] No se detectaron credenciales de AWS activas en esta sesión o han expirado.${NC}"
        echo -e "${YELLOW}[CONSEJO] Asegúrate de ejecutar este script desde AWS CloudShell con una sesión iniciada.${NC}"
        return 1
    fi
}

# Generar script de inicialización (user-data) para la EC2
generate_user_data() {
    # 1. Comprimir estructura del proyecto en un archivo tar.gz temporal
    tar -czf project.tar.gz docker-compose.yml app/ nginx/
    
    # 2. Codificar en base64 y limpiar saltos de línea para el script
    local B64_CONTENT
    B64_CONTENT=$(base64 < project.tar.gz | tr -d '\r\n')
    
    # Limpiar archivo temporal local
    rm -f project.tar.gz

    # 3. Escribir el script de user-data que decodifica y desempaqueta en el EC2
    cat << EOF > user_data_script.sh
#!/bin/bash
# Actualizar el sistema
dnf update -y

# Instalar Docker Engine
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# Instalar Docker Compose CLI Plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.26.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -s /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Crear estructura y desempaquetar el tar.gz en base64
mkdir -p /home/ec2-user/vzeta
cd /home/ec2-user/vzeta
echo "$B64_CONTENT" > project.tar.gz.b64
base64 -d project.tar.gz.b64 > project.tar.gz
tar -xzf project.tar.gz
rm -f project.tar.gz project.tar.gz.b64

# Crear directorio de persistencia de Postgres
mkdir -p /home/ec2-user/vzeta/postgres_data
chmod 777 /home/ec2-user/vzeta/postgres_data

# Dar permisos a la carpeta y levantar el stack
chown -R ec2-user:ec2-user /home/ec2-user/vzeta
cd /home/ec2-user/vzeta
/usr/local/bin/docker-compose up -d --build
EOF
}

# Lógica común para desplegar en AWS (compartida entre AWS CLI y CloudShell)
deploy_to_aws() {
    echo -e "${BLUE}[INFO] Iniciando despliegue de infraestructura en AWS...${NC}"
    
    # 1. Comprobar si existe la clave vockey en AWS
    echo -e "${BLUE}[INFO] Buscando par de claves 'vockey'...${NC}"
    aws ec2 describe-key-pairs --key-names vockey --query "KeyPairs[0].KeyName" --output text &> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] No se encontró la clave SSH 'vockey' en AWS. AWS Learner Lab requiere que uses 'vockey'.${NC}"
        return 1
    fi
    echo -e "${GREEN}[OK] Key pair 'vockey' detectada.${NC}"

    # 2. Obtener el ID de la VPC por defecto
    echo -e "${BLUE}[INFO] Obteniendo VPC por defecto...${NC}"
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text)
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
        echo -e "${RED}[ERROR] No se encontró la VPC por defecto de tu cuenta AWS.${NC}"
        return 1
    fi
    echo -e "${GREEN}[OK] VPC por defecto encontrada: $VPC_ID${NC}"

    # 3. Crear el Security Group
    echo -e "${BLUE}[INFO] Creando Security Group 'vzeta-sg'...${NC}"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "vzeta-sg-$(date +%s)" \
        --description "Security Group para Stack VZeta (EFT INY1105)" \
        --vpc-id "$VPC_ID" \
        --query "GroupId" \
        --output text)
    
    if [ -z "$SG_ID" ]; then
        echo -e "${RED}[ERROR] No se pudo crear el Security Group.${NC}"
        return 1
    fi
    echo -e "${GREEN}[OK] Security Group creado con ID: $SG_ID${NC}"

    # 4. Configurar reglas del Security Group
    echo -e "${BLUE}[INFO] Configurando reglas de acceso (puertos 80, 443 y 22)...${NC}"
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 &> /dev/null
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 &> /dev/null
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 &> /dev/null
    echo -e "${GREEN}[OK] Puertos 80 (HTTP), 443 (HTTPS) y 22 (SSH) autorizados para entrada desde cualquier origen.${NC}"

    # 5. Definir la AMI de Amazon Linux 2023
    AMI_ID="ami-002192a70217ac181"
    echo -e "${GREEN}[OK] AMI seleccionada: $AMI_ID (Amazon Linux 2023)${NC}"

    # 6. Generar el script de user-data local temporal
    generate_user_data

    # 7. Crear la instancia EC2
    echo -e "${BLUE}[INFO] Lanzando instancia EC2 t2.micro con clave 'vockey'...${NC}"
    INSTANCE_INFO=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t2.micro \
        --key-name vockey \
        --security-group-ids "$SG_ID" \
        --user-data file://user_data_script.sh \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=vzeta-stack-eft}]' \
        --query "Instances[0].[InstanceId,PrivateIpAddress]" \
        --output text)
    
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | awk '{print $1}')
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}[ERROR] Error al crear la instancia EC2.${NC}"
        # Limpieza de SG si falló la creación de la instancia
        aws ec2 delete-security-group --group-id "$SG_ID" &> /dev/null
        rm -f user_data_script.sh
        return 1
    fi
    
    echo -e "${GREEN}[OK] Instancia EC2 creada exitosamente con ID: $INSTANCE_ID${NC}"
    rm -f user_data_script.sh

    # 8. Asignar y asociar una IP Elástica
    echo -e "${BLUE}[INFO] Asignando una dirección IP Elástica en AWS...${NC}"
    local EIP_ALLOC_OUT
    EIP_ALLOC_OUT=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=vzeta-eip-eft}]' \
        --query "[AllocationId,PublicIp]" \
        --output text 2>/dev/null)
    
    local EIP_ALLOC_ID=""
    local EIP_PUBLIC_IP=""
    
    if [ -n "$EIP_ALLOC_OUT" ] && [ "$EIP_ALLOC_OUT" != "None" ]; then
        EIP_ALLOC_ID=$(echo "$EIP_ALLOC_OUT" | awk '{print $1}')
        EIP_PUBLIC_IP=$(echo "$EIP_ALLOC_OUT" | awk '{print $2}')
    fi

    # Guardar ID de instancia y SG en archivo local para posterior eliminación (Opción 2)
    echo "INSTANCE_ID=$INSTANCE_ID" > "$DEPLOY_FILE"
    echo "SG_ID=$SG_ID" >> "$DEPLOY_FILE"

    if [ -n "$EIP_ALLOC_ID" ] && [ "$EIP_ALLOC_ID" != "None" ] && [ -n "$EIP_PUBLIC_IP" ] && [ "$EIP_PUBLIC_IP" != "None" ]; then
        echo "EIP_ALLOC_ID=$EIP_ALLOC_ID" >> "$DEPLOY_FILE"
        PUBLIC_IP="$EIP_PUBLIC_IP"
        echo "PUBLIC_IP=$PUBLIC_IP" >> "$DEPLOY_FILE"
        echo -e "${GREEN}[OK] IP Elástica asignada: $PUBLIC_IP${NC}"
        
        # Esperar a que la instancia esté en estado running antes de asociar
        echo -e "${BLUE}[INFO] Esperando a que la instancia EC2 esté en ejecución para asociar la IP Elástica...${NC}"
        aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
        
        # Asociar
        aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$EIP_ALLOC_ID" &>/dev/null
        echo -e "${GREEN}[OK] IP Elástica asociada a la instancia EC2.${NC}"
    else
        # Fallback a IP dinámica estándar si falla la IP elástica (por límites del Learner Lab)
        echo -e "${YELLOW}[WARN] No se pudo asignar una IP Elástica. Usando IP pública dinámica estándar...${NC}"
        echo -e "${BLUE}[INFO] Esperando a que AWS asigne la dirección IP pública dinámica a la instancia...${NC}"
        aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
        PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text)
        echo "PUBLIC_IP=$PUBLIC_IP" >> "$DEPLOY_FILE"
    fi

    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}                 DESPLIEGUE INICIADO EXITOSAMENTE                     ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "ID de la Instancia: ${CYAN}$INSTANCE_ID${NC}"
    echo -e "Security Group ID:  ${CYAN}$SG_ID${NC}"
    echo -e "IP Pública EC2:    ${CYAN}$PUBLIC_IP${NC}"
    echo -e ""
    echo -e "${YELLOW}[IMPORTANTE] El sistema está instalando Docker, NGINX y la aplicación Flask en la máquina virtual.${NC}"
    echo -e "Esperando a que el stack de contenedores responda exitosamente en http://$PUBLIC_IP/...${NC}"
    echo -e "Esto suele tardar entre 2 y 3 minutos mientras descarga las imágenes.${NC}"
    echo -e ""

    # Bucle de consulta HTTP (Verifica HTTP 200 en http://$PUBLIC_IP/)
    local MAX_ATTEMPTS=30
    local ATTEMPT=1
    local SUCCESS=1

    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        local HTTP_STATUS
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://$PUBLIC_IP/")

        if [ "$HTTP_STATUS" -eq 200 ]; then
            echo -e "\n${GREEN}[OK] ¡La aplicación está respondiendo HTTP 200 con éxito! El stack está completamente operativo.${NC}"
            SUCCESS=0
            break
        else
            echo -ne "\r[INFO] Verificando estado del stack... Intento $ATTEMPT/$MAX_ATTEMPTS (Código HTTP: $HTTP_STATUS). Esperando 10s..."
            sleep 10
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done

    if [ $SUCCESS -ne 0 ]; then
        echo -e "\n${YELLOW}[ADVERTENCIA] Se superó el tiempo máximo de espera sin recibir respuesta HTTP 200.${NC}"
        echo -e "Es posible que la inicialización aún esté en curso o haya un problema de red."
    fi

    echo -e "\n======================================================================"
    
    # Preguntar si desea conectarse directamente por SSH
    if [ $SUCCESS -eq 0 ]; then
        read -p "¿Deseas conectarte directamente por SSH a la instancia ahora? (s/n): " CONNECT_RESP
        if [[ "$CONNECT_RESP" =~ ^[sS]$ ]]; then
            clear
            connect_ssh_instance
        fi
    fi
}

# Conectarse por SSH a la Instancia EC2 (Acceso remoto interactivo - Ejecutado desde la Opción 1 del menú)
connect_ssh_instance() {
    if [ ! -f "$DEPLOY_FILE" ]; then
        echo -e "${RED}[ERROR] No se detectó ningún despliegue activo en '$DEPLOY_FILE'.${NC}"
        echo -e "${YELLOW}[INFO] Por favor inicia o recupera el despliegue primero.${NC}"
        return 1
    fi
    
    INSTANCE_ID=$(grep 'INSTANCE_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
    PUBLIC_IP=$(grep 'PUBLIC_IP' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
    
    if [ -z "$INSTANCE_ID" ] || [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "None" ]; then
        echo -e "${RED}[ERROR] Datos de despliegue incompletos en '$DEPLOY_FILE'.${NC}"
        return 1
    fi

    echo -e "${BLUE}[INFO] Estableciendo conexión usando AWS EC2 Instance Connect...${NC}"
    
    # Generar par de claves temporal en ~/.ssh/ si no existe
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo -e "${BLUE}[INFO] Generando par de claves temporales...${NC}"
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/id_rsa &>/dev/null
    fi

    # Obtener la Zona de Disponibilidad de la instancia
    AZ=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query "Reservations[*].Instances[*].Placement.AvailabilityZone" \
        --output text 2>/dev/null | tr -d '\r\n ')
    
    if [ -z "$AZ" ] || [ "$AZ" = "None" ]; then
        AZ="us-east-1a"
    fi

    # Purgar posibles entradas previas del host
    ssh-keygen -R "$PUBLIC_IP" &>/dev/null
    
    # Enviar clave pública temporal
    aws ec2-instance-connect send-ssh-public-key \
        --instance-id "$INSTANCE_ID" \
        --instance-os-user "ec2-user" \
        --ssh-public-key "file://~/.ssh/id_rsa.pub" \
        --availability-zone "$AZ" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] Clave SSH pública autorizada temporalmente en AWS.${NC}"
        echo -e "${YELLOW}[INFO] Conectando...${NC}"
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ec2-user@$PUBLIC_IP
        return $?
    else
        echo -e "${RED}[ERROR] No se pudo enviar la clave SSH pública mediante EC2 Instance Connect.${NC}"
        echo -e "${YELLOW}[CONSEJO] Asegúrate de tener credenciales activas y permisos de EC2 Instance Connect.${NC}"
        return 1
    fi
}

# Opción 2: Eliminación de Recursos de AWS (Limpieza)
cleanup_aws_resources() {
    echo -e "${BLUE}[INFO] Iniciando limpieza de recursos de AWS...${NC}"
    
    # 1. Configurar credenciales primero
    if ! setup_aws_credentials; then
        echo -e "${RED}[ERROR] No se pudo autenticar con AWS para realizar la limpieza.${NC}"
        return 1
    fi

    INSTANCE_ID=""
    SG_ID=""
    
    # 2. Intentar cargar datos del archivo temporal .aws_deployment
    if [ -f "$DEPLOY_FILE" ]; then
        echo -e "${GREEN}[OK] Detectado registro de despliegue en '$DEPLOY_FILE'.${NC}"
        INSTANCE_ID=$(grep 'INSTANCE_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
        SG_ID=$(grep 'SG_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
    fi
    
    # 3. Si no se cargan del archivo, intentar detectarlos dinámicamente consultando AWS
    if [ -z "$INSTANCE_ID" ] || [ -z "$SG_ID" ]; then
        echo -e "${BLUE}[INFO] Buscando recursos activos en tu cuenta de AWS...${NC}"
        
        # Buscar instancia activa por Tag Name
        DETECTED_INST_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=vzeta-stack-eft" "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --output text 2>/dev/null | tr -d '\r\n ')
        
        if [ -n "$DETECTED_INST_ID" ] && [ "$DETECTED_INST_ID" != "None" ] && [ "$DETECTED_INST_ID" != "" ]; then
            INSTANCE_ID="$DETECTED_INST_ID"
            echo -e "${GREEN}[OK] Instancia activa detectada en AWS: $INSTANCE_ID${NC}"
        fi
        
        # Buscar Security Group ID
        if [ -n "$INSTANCE_ID" ]; then
            # Buscar el del grupo asociado a la instancia
            DETECTED_SG_ID=$(aws ec2 describe-instances \
                --filters "Name=instance-id,Values=$INSTANCE_ID" \
                --query "Reservations[*].Instances[*].SecurityGroups[0].GroupId" \
                --output text 2>/dev/null | tr -d '\r\n ')
            if [ -n "$DETECTED_SG_ID" ] && [ "$DETECTED_SG_ID" != "None" ] && [ "$DETECTED_SG_ID" != "" ]; then
                SG_ID="$DETECTED_SG_ID"
            fi
        fi
        
        # Fallback: buscar por nombre de grupo vzeta-security-group
        if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
            DETECTED_SG_ID=$(aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=vzeta-security-group" \
                --query "SecurityGroups[0].GroupId" \
                --output text 2>/dev/null | tr -d '\r\n ')
            if [ -n "$DETECTED_SG_ID" ] && [ "$DETECTED_SG_ID" != "None" ] && [ "$DETECTED_SG_ID" != "" ]; then
                SG_ID="$DETECTED_SG_ID"
            fi
        fi
        
        if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
            echo -e "${GREEN}[OK] Security Group detectado en AWS: $SG_ID${NC}"
        fi
    fi
    
    # 4. Si aún no se detectan, preguntar al usuario
    if [ -z "$INSTANCE_ID" ] || [ -z "$SG_ID" ]; then
        echo -e "${YELLOW}[INFO] No se pudieron detectar todos los recursos automáticamente. Por favor ingresa los datos a mano:${NC}"
        if [ -z "$INSTANCE_ID" ]; then
            read -p "Ingresa el ID de la instancia EC2 a eliminar (Ej: i-0abcdef1234567890): " INSTANCE_ID
        fi
        if [ -z "$SG_ID" ]; then
            read -p "Ingresa el ID del Security Group a eliminar (Ej: sg-0abcdef1234567890): " SG_ID
        fi
    fi
    
    if [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}[ERROR] ID de Instancia vacío. Abortando limpieza.${NC}"
        return 1
    fi

    # Buscar si hay un Elastic IP en el archivo .aws_deployment o dinámicamente por tag Name=vzeta-eip-eft
    local EIP_ALLOC_ID=""
    if [ -f "$DEPLOY_FILE" ]; then
        EIP_ALLOC_ID=$(grep 'EIP_ALLOC_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
    fi

    if [ -z "$EIP_ALLOC_ID" ]; then
        EIP_ALLOC_ID=$(aws ec2 describe-addresses \
            --filters "Name=tag:Name,Values=vzeta-eip-eft" \
            --query "Addresses[0].AllocationId" \
            --output text 2>/dev/null | tr -d '\r\n ')
    fi

    if [ -n "$EIP_ALLOC_ID" ] && [ "$EIP_ALLOC_ID" != "None" ] && [ "$EIP_ALLOC_ID" != "" ]; then
        echo -e "${YELLOW}[INFO] Liberando dirección IP Elástica ($EIP_ALLOC_ID)...${NC}"
        local ASSOC_ID
        ASSOC_ID=$(aws ec2 describe-addresses \
            --allocation-ids "$EIP_ALLOC_ID" \
            --query "Addresses[0].AssociationId" \
            --output text 2>/dev/null | tr -d '\r\n ')
        if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ] && [ "$ASSOC_ID" != "" ]; then
            aws ec2 disassociate-address --association-id "$ASSOC_ID" &>/dev/null
        fi
        aws ec2 release-address --allocation-id "$EIP_ALLOC_ID" &>/dev/null
        echo -e "${GREEN}[OK] IP Elástica liberada con éxito.${NC}"
    fi

    # 1. Terminar la instancia EC2
    echo -e "${YELLOW}[INFO] Solicitando terminación de la instancia EC2 ($INSTANCE_ID)...${NC}"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --query "TerminatingInstances[0].[InstanceId,CurrentState.Name]" --output text
    
    # 2. Esperar a que se termine completamente
    echo -e "${BLUE}[INFO] Esperando a que la instancia finalice por completo (esto puede tardar 1 o 2 minutos)...${NC}"
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
    echo -e "${GREEN}[OK] Instancia EC2 terminada de forma segura.${NC}"
    
    # 3. Eliminar el Security Group
    if [ -n "$SG_ID" ]; then
        echo -e "${YELLOW}[INFO] Eliminando Security Group ($SG_ID)...${NC}"
        # Agregar un pequeño delay por si AWS demora en soltar los interfaces de red
        sleep 5
        aws ec2 delete-security-group --group-id "$SG_ID"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[OK] Security Group eliminado exitosamente.${NC}"
        else
            echo -e "${RED}[WARN] No se pudo eliminar el Security Group en el primer intento. Reintentando en 15 segundos...${NC}"
            sleep 15
            aws ec2 delete-security-group --group-id "$SG_ID"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[OK] Security Group eliminado exitosamente en el reintento.${NC}"
            else
                echo -e "${RED}[ERROR] No se pudo eliminar el Security Group. Verifica si tiene interfaces asignados o dependencias.${NC}"
            fi
        fi
    fi
    
    # Eliminar el archivo temporal de despliegue si existe
    rm -f "$DEPLOY_FILE"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}           LIMPIEZA DE RECURSOS COMPLETADA EXITOSAMENTE               ${NC}"
    echo -e "======================================================================"
}

# Helper para saber si hay un despliegue activo
is_deployed() {
    if [ -f "$DEPLOY_FILE" ]; then
        local INST_CHECK
        INST_CHECK=$(grep 'INSTANCE_ID' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
        if [ -n "$INST_CHECK" ] && [ "$INST_CHECK" != "None" ]; then
            return 0
        fi
    fi
    return 1
}

# Bucle principal del Menú
while true; do
    echo -e ""
    echo -e "${CYAN}Selecciona una opción del menú:${NC}"
    
    if is_deployed; then
        ACTIVE_IP=$(grep 'PUBLIC_IP' "$DEPLOY_FILE" | cut -d'=' -f2 | tr -d '\r\n ')
        echo -e "1) Despliegue Activo IP: ${GREEN}$ACTIVE_IP${NC} - Conectar vía SSH"
        echo -e "2) Limpieza y eliminación despliegue"
    else
        echo -e "1) Desplegar"
        echo -e "2) ${GRAY}Limpieza y eliminación despliegue (Inhabilitado)${NC}"
    fi
    echo -e "3) Salir"
    read -p "Opción [1-3]: " OPTION

    case $OPTION in
        1)
            clear
            if is_deployed; then
                connect_ssh_instance
            else
                if setup_aws_credentials; then
                    deploy_to_aws
                fi
            fi
            press_enter_to_continue
            ;;
        2)
            clear
            if ! is_deployed; then
                echo -e "${RED}[ERROR] No se detectó un despliegue activo para limpiar.${NC}"
            else
                cleanup_aws_resources
            fi
            press_enter_to_continue
            ;;
        3)
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Opción no válida. Por favor selecciona del 1 al 3.${NC}"
            press_enter_to_continue
            ;;
    esac
done
