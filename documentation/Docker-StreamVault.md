# Dockerización de StreamVault - Guía Completa

## Tabla de Contenidos

1. [Conceptos Fundamentales de Docker](#1-conceptos-fundamentales-de-docker)
2. [Arquitectura de Red de StreamVault](#2-arquitectura-de-red-de-streamvault)
3. [Archivos de Dockerización](#3-archivos-de-dockerización)
4. [Flujo de Construcción y Ejecución](#4-flujo-de-construcción-y-ejecución)
5. [Variables de Entorno](#5-variables-de-entorno)
6. [Actualización del Sistema](#6-actualización-del-sistema)
7. [Comandos Útiles](#7-comandos-útiles)
8. [Generación de Claves JWT](#8-generación-de-claves-jwt)
9. [Consideraciones de Seguridad](#9-consideraciones-de-seguridad)

---

## 1. Conceptos Fundamentales de Docker

### 1.1 ¿Qué es Docker?

Docker es una plataforma de **contenedorización** que permite打包 y ejecutar aplicaciones en entornos aislados llamados contenedores. A diferencia de las máquinas virtuales tradicionales, los contenedores comparten el kernel del sistema operativo del host, lo que los hace mucho más ligeros y rápidos.

### 1.2 Diferencia entre Imagen y Contenedor

| Concepto | Descripción | Analogía |
|----------|-------------|-----------|
| **Imagen** | Template de solo lectura que contiene todo lo necesario para ejecutar una aplicación (código, runtime, dependencias) | Como una clase en Java |
| **Contenedor** | Instancia en ejecución de una imagen | Como un objeto instanciado de una clase |

### 1.3 Estructura de Capas (Layers)

Las imágenes de Docker se construyen mediante capas:

```
┌─────────────────────────────────────────────────────────────────────┐
│ CAPAS DE UNA IMAGEN DOCKER                                          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Layer N: Tu código compilado (JAR)      │  ← Capa más reciente
├─────────────────────────────────────────┤
│ Layer N-1: Código fuente copiado        │
├─────────────────────────────────────────┤
│ Layer N-2: Dependencias Maven           │
├─────────────────────────────────────────┤
│ Layer N-3: Herramientas de build        │
├─────────────────────────────────────────┤
│ Layer Base: JDK 21 Alpine              │  ← Capa base original
└─────────────────────────────────────────┘

CACHÉ: Las capas se reutilizan en builds posteriores si no cambian
```

### 1.4 Multi-Stage Build

El Dockerfile utiliza Multi-Stage Build para optimizar el tamaño de la imagen final:

```
┌─────────────────────────────────────────────────────────────────────┐
│ MULTI-STAGE BUILD - dos etapas                                     │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────┐    ┌──────────────────────────────────┐
│ ETAPA 1: BUILD (compilación)        │    │ ETAPA 2: RUNTIME (producción)   │
│                                    │    │                                  │
│ FROM eclipse-temurin:21-jdk-alpine  │    │ FROM eclipse-temurin:21-jre-    │
│ + Maven                            │    │ alpine                          │
│ + Código fuente                    │    │ Solo el JAR compilado           │
│ + Compilar → Genera JAR            │    │ Imagen ~200MB (vs 600MB+)       │
│                                    │    │                                  │
│ Tamaño: ~500MB+                    │    │ Tamaño: ~180MB                  │
└──────────────────────────────────────┘    └──────────────────────────────────┘

RESULTADO: Imagen final optimizada con solo lo necesario para ejecutar
```

---

## 2. Arquitectura de Red de StreamVault

### 2.1 Distribución por Redes Virtuales

```
┌─────────────────────────────────────────────────────────────────────┐
│ ARQUITECTURA DE RED DE STREAMVAULT                                 │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│ RED 1: SERVICIOS CORE                                       │
│ (VM: srv-core.streamvault.local)                           │
│ ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │
│ │ DNS Server   │ │ PostgreSQL   │ │ SMTP/Mail Server   │ │
│ │ :53          │ │ :5432        │ │ :587               │ │
│ └──────────────┘ └──────────────┘ └────────────────────┘ │
│ ┌──────────────┐                                             │
│ │ MinIO/S3     │                                             │
│ │ :9000        │                                             │
│ └──────────────┘                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Conexión por DNS
                         ▼
┌────────────────────────────────────────────────────────────┐
│ RED 2: BACKEND (VM: srv-backend.streamvault.local)        │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ CONTENEDOR: StreamVault API                           │ │
│ │ - Puerto 8080 expuesto                               │ │
│ │ - Se conecta a servicios por nombre DNS              │ │
│ └──────────────────────────────────────────────────────┘ │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ Conexión por DNS/API
                         ▼
┌────────────────────────────────────────────────────────────┐
│ RED 3: FRONTEND (VM: srv-frontend.streamvault.local)      │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ - Conexión a API por DNS: srv-backend.streamvault.local │
│ └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

### 2.2 Resolución DNS

Cada servicio se comunica por nombre DNS, no por IP:

| Servicio | Hostname DNS | Puerto | Variables en .env |
|----------|-------------|--------|-------------------|
| PostgreSQL | `srv-db.streamvault.local` | 5432 | `DB_HOST=srv-db.streamvault.local` |
| SMTP/Mail | `srv-mail.streamvault.local` | 587 | `MAIL_HOST=srv-mail.streamvault.local` |
| MinIO/S3 | `srv-minio.streamvault.local` | 9000 | `MINIO_URL=http://srv-minio.streamvault.local:9000` |
| Backend | `srv-backend.streamvault.local` | 8080 | (expuesto al frontend) |

---

## 3. Archivos de Dockerización

### 3.1 Estructura de Archivos

```
streamvault-api/
├── Dockerfile              # Receta para construir la imagen
├── docker-compose.yml     # Orquestación del contenedor
├── .env.example           # Template de variables de entorno
├── .dockerignore          # Archivos a excluir del build
└── documentation/
    └── Docker-StreamVault.md  # Este documento
```

### 3.2 Descripción de Cada Archivo

#### Dockerfile

```dockerfile
# Este archivo define cómo se construye la imagen de Docker
# contiene dos etapas:
#   1. BUILD: Compila el código Java con Maven
#   2. RUNTIME: Crea una imagen ligera solo con JRE
#
# Uso: docker build -t streamvault-api .
```

#### docker-compose.yml

```yaml
# Define la configuración del contenedor
# Incluye:
#   - Imagen a construir
#   - Puertos a exponer
#   - Variables de entorno
#   - Recursos (memoria, CPU)
#   - Red interna
#
# Uso: docker-compose up -d
```

#### .env.example

```bash
# Template con todas las variables necesarias
# Copiar a .env y completar con valores reales
# NO commitear .env con credenciales reales
```

---

## 4. Flujo de Construcción y Ejecución

### 4.1 Secuencia Completa de Docker

```
┌─────────────────────────────────────────────────────────────────────┐
│ SECUENCIA COMPLETA: DEL CÓDIGO AL CONTENEDOR                       │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────┐
│ 1. ESCRIBIR     │  ← Tu código Java en project/streamvault-api/
│    CÓDIGO       │
└────────┬────────┘
         │ git commit
         ▼
┌─────────────────┐
│ 2. DOCKER BUILD │  ← docker build -t streamvault-api .
│    (compilar)   │
└────────┬────────┘
         │
         ▼lee Dockerfile
    ┌────────────────────────────────────────┐
    │ PROCESO DE BUILD:                      │
    │ 1. Descargar imagen base (caché)       │
    │ 2. Copiar pom.xml (caché si no cambia) │
    │ 3. Descargar dependencias (caché)     │
    │ 4. Copiar código fuente               │
    │ 5. Compilar con Maven                  │
    │ 6. Generar JAR                         │
    │ 7. Copiar JAR a imagen final           │
    └────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ 3. DOCKER RUN   │  ← docker run -d --name streamvault-api ...
│    (ejecutar)   │
└────────┬────────┘
         │
         ▼
    ┌────────────────────────────────────────┐
    │ CONTENEDOR EN EJECUCIÓN:               │
    │ - Proceso Java corriendo               │
    │ - Puerto 8080 escuchando               │
    │ - Variables de entorno cargadas        │
    │ - Conectado a servicios externos       │
    └────────────────────────────────────────┘
```

### 4.2 Construcción del Contenedor

```bash
# Método 1: Solo build (sin levantar)
docker build -t streamvault-api .

# Método 2: Build y levantar con docker-compose
docker-compose up -d --build

# Método 3: Build con tags específicos
docker build -t streamvault-api:1.0.0 .
docker build -t streamvault-api:latest .
```

---

## 5. Variables de Entorno

### 5.1 Variables Obligatorias (sin defaults seguros)

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `DB_HOST` | Hostname del servidor PostgreSQL | `srv-db.streamvault.local` |
| `DB_NAME` | Nombre de la base de datos | `streamvault` |
| `DB_USER` | Usuario de la base de datos | `streamvault_user` |
| `DB_PASSWORD` | Contraseña de la base de datos | `********` |
| `MAIL_HOST` | Hostname del servidor SMTP | `srv-mail.streamvault.local` |
| `MAIL_FROM` | Email remitente | `noreply@streamvault.local` |
| `MAIL_PASSWORD` | Contraseña del email | `********` |
| `JWT_PUBLIC_KEY` | Clave pública RSA (formato multilínea) | `-----BEGIN PUBLIC KEY-----\n...` |
| `JWT_PRIVATE_KEY` | Clave privada RSA (formato multilínea) | `-----BEGIN PRIVATE KEY-----\n...` |
| `MINIO_URL` | URL del servicio MinIO/S3 | `http://srv-minio.streamvault.local:9000` |
| `MINIO_ACCESS_KEY` | Access key de MinIO | `minioadmin` |
| `MINIO_SECRET_KEY` | Secret key de MinIO | `minioadmin` |

### 5.2 Variables Opcionales (con defaults)

| Variable | Default | Descripción |
|----------|---------|-------------|
| `SPRING_PROFILES_ACTIVE` | `prod` | Perfil de Spring |
| `SERVER_PORT` | `8080` | Puerto del servidor |
| `DB_PORT` | `5432` | Puerto de PostgreSQL |
| `MAIL_PORT` | `587` | Puerto SMTP |
| `MINIO_BUCKET_VIDEOS` | `streamvault-videos` | Bucket para videos |
| `MINIO_BUCKET_THUMBNAILS` | `streamvault-thumbnails` | Bucket para thumbnails |
| `CORS_ALLOWED_ORIGINS` | - | Orígenes permitidos para CORS |

### 5.3 Cómo Definir Variables

```bash
# Método 1: Archivo .env
DB_HOST=srv-db.streamvault.local
DB_USER=streamvault_user
# ...

# Método 2: En línea de comandos
docker run -e DB_HOST=srv-db.streamvault.local -e DB_USER=admin streamvault-api

# Método 3: En docker-compose.yml (bajo environment:)
environment:
  - DB_HOST=${DB_HOST}
```

---

## 6. Actualización del Sistema

### 6.1 Flujo de Actualización por Nueva Feature

```
┌─────────────────────────────────────────────────────────────────────┐
│ ACTUALIZAR EL SISTEMA CON NUEVAS FEATURES                           │
└─────────────────────────────────────────────────────────────────────┘

1. HACÉS CAMBIOS EN EL CÓDIGO
   └─> project/streamvault-api/src/main/java/...

2. HACÉS COMMIT EN GIT
   └─> git add . && git commit -m "feat: nueva funcionalidad"

3. REBUILD LA IMAGEN
   └─> docker-compose up -d --build
       (el flag --build fuerza recompilación)

4. EL CONTENEDOR SE REINICIA automáticamente
   └─> Con la nueva imagen compilada

5. VERIFICÁS QUE FUNCIONE
   └─> docker-compose logs -f streamvault-api
   └─> curl http://localhost:8080/actuator/health
```

### 6.2 Actualización sin Rebuild (solo configuración)

```bash
# Si solo cambias variables de entorno (sin tocar código)
docker-compose down
# Editar .env
docker-compose up -d

# O actualizar solo una variable
docker exec streamvault-api env DB_HOST=nuevo-host
```

### 6.3 actualization de Variables de Entorno en Producción

```bash
# Método 1: Editar .env y recrear
docker-compose down
# editar .env
docker-compose up -d

# Método 2: Actualizar variable específica
docker exec -it streamvault-api /bin/sh
# Dentro del contenedor: export NUEVA_VAR=valor
```

---

## 7. Comandos Útiles

### 7.1 Comandos Básicos

```bash
# Build de la imagen
docker build -t streamvault-api .

# Ver imágenes disponibles
docker images

# Levantar contenedor
docker run -d -p 8080:8080 --name streamvault-api streamvault-api

# Ver contenedores en ejecución
docker ps

# Ver todos los contenedores (incluidos parados)
docker ps -a

# Ver logs en tiempo real
docker logs -f streamvault-api

# Ver logs de un contenedor específico
docker-compose logs -f streamvault-api

# Entrar al contenedor (debugging)
docker exec -it streamvault-api /bin/sh

# Detener contenedor
docker stop streamvault-api

# Eliminar contenedor
docker rm streamvault-api
```

### 7.2 Comandos con Docker Compose

```bash
# Levantar servicios (modo detach)
docker-compose up -d

# Levantar con rebuild forzado
docker-compose up -d --build

# Recrea contenedores (útil para cambios en .env)
docker-compose up -d --force-recreate

# Bajar servicios
docker-compose down

# Bajar servicios y eliminar volúmenes
docker-compose down -v

# Ver estado de servicios
docker-compose ps

# Ver logs de todos los servicios
docker-compose logs -f

# Ver recursos (memoria, CPU)
docker stats streamvault-api
```

### 7.3 Comandos de Troubleshooting

```bash
# Ver configuración aplicada
docker inspect streamvault-api

# Ver variables de entorno del contenedor
docker exec streamvault-api env

# Ver consumo de recursos en tiempo real
docker stats

# Ver eventos del Docker daemon
docker events

# Limpiar imágenes sin usar
docker image prune -a

# Limpiar todo (cuidado!)
docker system prune -a
```

---

## 8. Generación de Claves JWT

### 8.1 Por Qué Necesitas Claves JWT

La aplicación usa JWT (JSON Web Tokens) para autenticación. En producción, debés generar tus propias claves RSA y nunca usar las que vienen por defecto.

### 8.2 Generar Claves

```bash
# 1. Generar clave privada RSA de 4096 bits
openssl genrsa -out jwt-private.pem 4096

# 2. Extraer clave pública desde la privada
openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem

# 3. Ver las claves generadas
cat jwt-public.pem
cat jwt-private.pem
```

### 8.3 formatar para .env

Las claves deben tener los saltos de línea escapados para el archivo .env:

```bash
# Para clave pública
cat jwt-public.pem | perl -pe 's/\n/\\n/g'

# Para clave privada
cat jwt-private.pem | perl -pe 's/\n/\\n/g'
```

Ejemplo en .env:
```env
JWT_PUBLIC_KEY=-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...\n-----END PUBLIC KEY-----
JWT_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggS...\n-----END PRIVATE KEY-----
```

### 8.4 Seguridad de las Claves

- **NUNCA** commitear las claves reales al repositorio
- Guardar las claves en un lugar seguro (password manager, Vault)
- Rotar las claves periódicamente
- Usar claves de al menos 2048 bits (4096 bits recomendado)

---

## 9. Consideraciones de Seguridad

### 9.1 Recomendaciones para Producción

1. **Usuario no-root**: El Dockerfile corre como usuario no-root (`streamvault`)
2. **Healthcheck**: Verifica que la app esté saludable
3. **Límites de recursos**: Configurados en docker-compose.yml
4. **Logs rotativos**: Máximo 3 archivos de 10MB cada uno
5. **Secrets**: Usar Docker Secrets o un gestor externo en producción

### 9.2 Variables Sensibles

```bash
# NUNCA hacer esto:
git add .env
git commit -m "add env"

# SIEMPRE hacer esto:
echo ".env" >> .gitignore
```

### 9.3 Puertos Expuestos

| Puerto | Propósito | Externo |
|--------|-----------|---------|
| 8080 | API de StreamVault | Sí (para Frontend) |
| 9000 | MinIO | No (solo red interna) |
| 5432 | PostgreSQL | No (solo red interna) |
| 25 | SMTP | No (solo red interna) |

---

## 10. Anexo: Checklist para Dockerización de Nuevos Servicios

Al dockerizar otros servicios de StreamVault, seguir este checklist:

- [ ] **Dockerfile**: Imagen base apropiada, multi-stage build
- [ ] **docker-compose.yml**: Puertos, variables, redes, healthchecks
- [ ] **.env.example**: Todas las variables documentadas
- [ ] **.dockerignore**: Archivos innecesarios excluidos
- [ ] **Puertos**: Documentar qué puertos expone y para qué
- [ ] **Servicios externos**: Definir cómo se conecta a BD, mail, etc.
- [ ] **Variables sensibles**: Identificar y marcar para no commitear
- [ ] **Tests**: Verificar que funciona con docker-compose

---

## Referencias

- [Docker Docs](https://docs.docker.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Spring Boot Docker](https://spring.io/guides/gs/spring-boot-docker/)
- [PostgreSQL Docker](https://hub.docker.com/_/postgres)
- [MinIO Docker](https://hub.docker.com/r/minio/minio)

---

*Documento creado: Abril 2026*
*Versión: 1.0*
*Proyecto: StreamVault*