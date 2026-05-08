#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                    StreamVault - Script de Instalación                    ║
# ║                    VM Network Services Installer                          ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para打印 mensajes
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verificar que se ejecute como root
# ─────────────────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
   print_error "Este script debe ejecutarse como root (sudo)"
   echo "Usage: sudo $0"
   exit 1
fi

print_header "StreamVault - Instalador de Servicios de Red"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Detectar sistema operativo
# ─────────────────────────────────────────────────────────────────────────────
print_info "Detectando sistema operativo..."

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    print_error "No se puede detectar el sistema operativo"
    exit 1
fi

print_success "Sistema detectado: $OS $VER"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Instalar Docker
# ─────────────────────────────────────────────────────────────────────────────
print_header "Instalando Docker"

if command -v docker &> /dev/null; then
    print_success "Docker ya está instalado: $(docker --version)"
else
    print_info "Instalando Docker..."

    # Linux Mint y otros basados en Ubuntu usan el código de Ubuntu
    case $OS in
        ubuntu|debian|mint|linuxmint)
            # Actualizar repositorios
            apt update -y

            # Instalar dependencias
            apt install -y ca-certificates curl gnupg lsb-release

            # Linux Mint usa repositorio de Ubuntu
            # Determinar versión base para el repositorio
            if [[ "$OS" == "mint" ]] || [[ "$OS" == "linuxmint" ]]; then
                # Obtener versión base de Ubuntu desde /etc/os-release
                if [[ -f /etc/upstream-release/lsb-release ]]; then
                    . /etc/upstream-release/lsb-release
                    DISTRO_CODENAME="${DISTRIB_CODENAME}"
                else
                    # Por defecto usar nombre de versión de lsb-release
                    DISTRO_CODENAME=$(lsb_release -cs)
                fi
                print_info "Linux Mint detectado - usando repositorio Ubuntu: $DISTRO_CODENAME"
            else
                DISTRO_CODENAME=$(lsb_release -cs)
            fi

            # Agregar clave GPG de Docker
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

            # Agregar repositorio (siempre usar ubuntu para mint/debian)
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${DISTRO_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

            # Instalar Docker
            apt update -y
            apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            # Habilitar y iniciar Docker
            systemctl enable docker
            systemctl start docker
            ;;
        centos|fedora|rhel)
            # Instalar Docker usando el script oficial
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker
            systemctl start docker
            ;;
        *)
            print_error "Sistema operativo no soportado: $OS"
            echo ""
            echo "Sistemas soportados:"
            echo "  - Ubuntu / Debian / Linux Mint"
            echo "  - CentOS / Fedora / RHEL"
            exit 1
            ;;
    esac

    print_success "Docker instalado correctamente"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Verificar Docker
# ─────────────────────────────────────────────────────────────────────────────
print_header "Verificando Docker"

# Agregar usuario no-root al grupo docker
# El usuario real (no root) necesita acceso a Docker
REAL_USER=${SUDO_USER:-$(whoami)}
if [[ "$REAL_USER" != "root" ]]; then
    usermod -aG docker $REAL_USER 2>/dev/null || true
    print_info "Usuario $REAL_USER agregado al grupo docker"
    print_warning "IMPORTANT: Cerrá sesión y volvé a abrirla para aplicar los permisos"
    print_warning "O ejecutá: newgrp docker"
fi

# Verificar que Docker funciona (con sudo o sin él)
if docker run --rm hello-world &> /dev/null; then
    print_success "Docker está funcionando correctamente"
else
    print_warning "Docker no funciona sin sudo, intentando con sudo..."
    if sudo docker run --rm hello-world &> /dev/null; then
        print_success "Docker funciona con sudo"
    else
        print_error "Docker tiene problemas. Verifica con: sudo docker ps"
    fi
fi

# Verificar docker compose
if docker compose version &> /dev/null; then
    print_success "Docker Compose instalado: $(docker compose version)"
else
    print_error "Docker Compose no está instalado"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Verificar archivo .env
# ─────────────────────────────────────────────────────────────────────────────
print_header "Verificando archivo .env"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [[ -f "$ENV_FILE" ]]; then
    print_success "Archivo .env encontrado"
else
    if [[ -f "$ENV_EXAMPLE" ]]; then
        print_info "Creando archivo .env desde .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        print_success ".env creado - EDITALO ANTES DE CONTINUAR"
        print_warning "⚠️  Abre $ENV_FILE y configura:"
        print_warning "   - POSTFIX_MYNETWORKS (tu subnet)"
        print_warning "   - POSTGRES_PASSWORD"
        print_warning "   - MINIO_ROOT_PASSWORD"
    else
        print_error "No se encontró .env.example"
        exit 1
    fi
fi

# ⚠️ NO SE MODIFICA NINGUNA CONFIGURACIÓN DE RED
# Las configuraciones de red (DNS, Postfix, etc.) ya están definidas
# en los archivos de infrastructure/ - no tocamos nada

# ─────────────────────────────────────────────────────────────────────────────
# 7. Descargar imágenes de Docker
# ─────────────────────────────────────────────────────────────────────────────
print_header "Descargando imágenes de Docker"

cd "$SCRIPT_DIR"

print_info "Esto puede tomar varios minutos dependiendo de tu conexión..."

# Pull de todas las imágenes
docker compose pull

print_success "Imágenes descargadas correctamente"

# ─────────────────────────────────────────────────────────────────────────────
# 8. Iniciar servicios
# ─────────────────────────────────────────────────────────────────────────────
print_header "Iniciando servicios"

docker compose up -d

# Esperar a que los servicios estén saludables
print_info "Verificando servicios..."

sleep 10

# Verificar estado
docker compose ps

# ─────────────────────────────────────────────────────────────────────────────
# 9. Verificación final
# ─────────────────────────────────────────────────────────────────────────────
print_header "Verificación de servicios"

SERVICES=("streamvault-dns" "streamvault-postgres" "streamvault-minio" "streamvault-dovecot" "streamvault-postfix" "streamvault-webmail")

ALL_RUNNING=true
for service in "${SERVICES[@]}"; do
    if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
        print_success "$service está运行"
    else
        print_error "$service no está corriendo"
        ALL_RUNNING=false
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Final
# ─────────────────────────────────────────────────────────────────────────────
echo ""
print_header "Instalación Completada"

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Resumen:${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  📁 Archivos de configuración:"
echo "     - .env: $ENV_FILE"
echo "     - Docker Compose: $SCRIPT_DIR/docker-compose.yml"
echo ""
echo "  🌐 Puertos expuestos:"
echo "     - DNS:      53 (TCP/UDP)"
echo "     - PostgreSQL: 5432"
echo "     - MinIO:    9000 (API), 9001 (Console)"
echo "     - SMTP:     25"
echo "     - IMAP:     143, 993"
echo "     - Webmail:  8080"
echo ""
echo "  🔧 Comandos útiles:"
echo "     - Ver estado:    docker compose ps"
echo "     - Ver logs:      docker compose logs -f"
echo "     - Detener:      docker compose down"
echo "     - Reiniciar:    docker compose restart"
echo ""
echo "  ⚠️  IMPORTANTE:"
echo "     - Cambia las contraseñas en .env antes de producción"
echo "     - Contraseña PostgreSQL por defecto: streamvault2025"
echo "     - Contraseña MinIO por defecto: minioadmin2025"
echo "     - Usuarios mail: noreply@streamvault.com / admin@streamvault.com"
echo ""

if [[ "$ALL_RUNNING" == "true" ]]; then
    print_success "¡Todos los servicios están corriendo!"
else
    print_warning "Algunos servicios no están corriendo. Verifica con: docker compose logs"
fi

exit 0