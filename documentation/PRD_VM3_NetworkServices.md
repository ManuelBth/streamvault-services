# PRD — Network Services
## StreamVault by Betha
### VM-3 · BIND9 · Postfix · Dovecot · PostgreSQL · MinIO · Docker

---

> **Versión:** 1.0.0
> **VM:** VM-3 — `192.168.1.30`
> **Equipo:** Betha
> **Fecha:** 2025

---

## Tabla de Contenidos

1. [Visión General](#1-visión-general)
2. [Posición en la Arquitectura](#2-posición-en-la-arquitectura)
3. [Servicios que corren en VM-3](#3-servicios-que-corren-en-vm-3)
4. [Servicio DNS — BIND9](#4-servicio-dns--bind9)
5. [Servicio SMTP — Postfix](#5-servicio-smtp--postfix)
6. [Servicio de Buzones — Dovecot](#6-servicio-de-buzones--dovecot)
7. [Flujo Completo del Correo](#7-flujo-completo-del-correo)
8. [Base de Datos — PostgreSQL](#8-base-de-datos--postgresql)
9. [Almacenamiento de Video — MinIO](#9-almacenamiento-de-video--minio)
10. [Protocolos por Capa OSI](#10-protocolos-por-capa-osi)
11. [Configuración Docker](#11-configuración-docker)
12. [Variables de Entorno](#12-variables-de-entorno)
13. [Orden de Arranque de Servicios](#13-orden-de-arranque-de-servicios)
14. [Verificación y Pruebas](#14-verificación-y-pruebas)

---

## 1. Visión General

VM-3 es la **capa de infraestructura y servicios de red** de la plataforma StreamVault. No expone ninguna interfaz de usuario — su rol es proveer todos los servicios de soporte que necesitan VM-1 (Frontend) y VM-2 (Backend) para funcionar.

Concentra en una sola máquina virtual cinco responsabilidades críticas:

- **DNS interno** — resolución de nombres para todos los hosts de la AS
- **SMTP saliente** — recepción y entrega de emails enviados por el backend
- **Buzones de correo** — almacenamiento IMAP de los emails para que los usuarios los lean en Thunderbird
- **Base de datos relacional** — persistencia de todas las entidades de la plataforma
- **Almacenamiento de objetos** — videos HLS y miniaturas accesibles por el backend y el player

```
         ┌─────────────────────────────────────┐
         │           VM-3  192.168.1.30         │
         │                                     │
         │  ┌──────────┐   ┌─────────────────┐ │
         │  │  BIND9   │   │    Postfix      │ │
         │  │  DNS:53  │   │    SMTP:25      │ │
         │  └──────────┘   └────────┬────────┘ │
         │                          │           │
         │                 ┌────────▼────────┐  │
         │                 │    Dovecot      │  │
         │                 │    IMAP:143     │  │
         │                 └─────────────────┘  │
         │                                     │
         │  ┌──────────┐   ┌─────────────────┐ │
         │  │PostgreSQL│   │      MinIO      │ │
         │  │ TCP:5432 │   │    HTTP:9000    │ │
         │  └──────────┘   └─────────────────┘ │
         └─────────────────────────────────────┘
```

---

## 2. Posición en la Arquitectura

### Conexiones que recibe VM-3

| Origen | Servicio destino | Protocolo | Puerto | Propósito |
|---|---|---|---|---|
| VM-1 Frontend | BIND9 | UDP/TCP | `:53` | Resolución de nombres internos |
| VM-2 Backend | BIND9 | UDP/TCP | `:53` | Resolución de nombres internos |
| VM-2 Backend | Postfix | TCP / SMTP | `:25` | Recepción de emails del sistema |
| VM-2 Backend | PostgreSQL | TCP / R2DBC | `:5432` | Lectura y escritura de datos |
| VM-2 Backend | MinIO | TCP / HTTP | `:9000` | Subida y firma de URLs de video |
| Thunderbird (cliente) | Dovecot | TCP / IMAP | `:143` | Lectura de buzones de correo |
| Thunderbird (cliente) | Dovecot | TCP / IMAP TLS | `:993` | Lectura segura (opcional) |

### Diagrama de flujo general

```
VM-1 ──UDP:53──► BIND9      (¿qué IP es api.streamvault.local?)
VM-2 ──UDP:53──► BIND9      (¿qué IP es mail.streamvault.local?)
VM-2 ──TCP:25──► Postfix ──► Dovecot (entrega al buzón)
VM-2 ──TCP:5432─► PostgreSQL
VM-2 ──TCP:9000─► MinIO
Thunderbird ──TCP:143──► Dovecot (lee el buzón)
```

---

## 3. Servicios que corren en VM-3

| Servicio | Tecnología | Puerto | Imagen Docker |
|---|---|---|---|
| DNS | BIND9 | UDP/TCP `:53` | `internetsystemsconsortium/bind9:9.18` |
| SMTP | Postfix | TCP `:25` | `boky/postfix:latest` |
| Buzones IMAP | Dovecot | TCP `:143` / `:993` | `dovecot/dovecot:latest` |
| Base de datos | PostgreSQL 16 | TCP `:5432` | `postgres:16-alpine` |
| Almacenamiento | MinIO | TCP `:9000` / `:9001` | `minio/minio:latest` |

> **Nota:** El puerto `:9001` de MinIO es la consola web de administración. Solo accesible desde la red interna para el equipo Betha.

---

## 4. Servicio DNS — BIND9

### 4.1 Responsabilidad

BIND9 actúa como el **servidor DNS autoritativo** de la zona `streamvault.local`. Todas las VMs de la AS apuntan a `192.168.1.30` como su servidor DNS primario, de modo que cualquier hostname interno se resuelve sin necesitar DNS externo.

### 4.2 Zona directa — `streamvault.local`

Archivo: `/etc/bind/zones/streamvault.local.zone`

```dns
$TTL 86400
@   IN  SOA  ns1.streamvault.local. admin.streamvault.local. (
                2025010101  ; Serial
                3600        ; Refresh
                1800        ; Retry
                604800      ; Expire
                86400 )     ; Minimum TTL

; Name servers
@           IN  NS   ns1.streamvault.local.

; Name server A record
ns1         IN  A    192.168.1.30

; ── Registros A de la plataforma ──────────────────────────
streamvault.local.          IN  A    192.168.1.10   ; Frontend
api.streamvault.local.      IN  A    192.168.1.20   ; Backend REST
ws.streamvault.local.       IN  A    192.168.1.20   ; Backend WebSocket
mail.streamvault.local.     IN  A    192.168.1.30   ; SMTP Postfix
imap.streamvault.local.     IN  A    192.168.1.30   ; IMAP Dovecot
db.streamvault.local.       IN  A    192.168.1.30   ; PostgreSQL
minio.streamvault.local.    IN  A    192.168.1.30   ; MinIO S3
ns1.streamvault.local.      IN  A    192.168.1.30   ; DNS

; ── Registro MX (Mail Exchanger) ──────────────────────────
streamvault.local.          IN  MX   10 mail.streamvault.local.
```

### 4.3 Zona inversa — `1.168.192.in-addr.arpa`

Archivo: `/etc/bind/zones/192.168.1.rev`

```dns
$TTL 86400
@   IN  SOA  ns1.streamvault.local. admin.streamvault.local. (
                2025010101
                3600
                1800
                604800
                86400 )

@   IN  NS   ns1.streamvault.local.

; Registros PTR (reversa)
10  IN  PTR  streamvault.local.       ; VM-1 Frontend
20  IN  PTR  api.streamvault.local.   ; VM-2 Backend
30  IN  PTR  mail.streamvault.local.  ; VM-3 Servicios
```

### 4.4 Configuración principal de BIND9

Archivo: `/etc/bind/named.conf.local`

```
zone "streamvault.local" {
    type master;
    file "/etc/bind/zones/streamvault.local.zone";
    allow-query { 192.168.1.0/24; };
};

zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/192.168.1.rev";
    allow-query { 192.168.1.0/24; };
};
```

Archivo: `/etc/bind/named.conf.options`

```
options {
    directory "/var/cache/bind";

    // Solo responde consultas desde la red interna
    allow-query     { 192.168.1.0/24; localhost; };
    allow-recursion { 192.168.1.0/24; localhost; };

    // Reenvío a DNS externo para nombres que no son .local
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    forward only;

    dnssec-validation no;
    listen-on { 192.168.1.30; localhost; };
};
```

### 4.5 Configuración de DNS en cada VM

Todas las VMs de la AS deben apuntar a VM-3 como su DNS:

```
# /etc/resolv.conf (VM-1 y VM-2)
nameserver 192.168.1.30
search streamvault.local
```

### 4.6 Verificación

```bash
# Desde VM-1 o VM-2 — verificar resolución directa
dig @192.168.1.30 api.streamvault.local
dig @192.168.1.30 mail.streamvault.local
dig @192.168.1.30 db.streamvault.local

# Verificar registro MX
dig @192.168.1.30 MX streamvault.local

# Verificar resolución inversa
dig @192.168.1.30 -x 192.168.1.20
```

---

## 5. Servicio SMTP — Postfix

### 5.1 Responsabilidad

Postfix actúa como **MTA (Mail Transfer Agent)** de la plataforma. Recibe los emails enviados por el backend Spring Boot en el puerto 25 y los entrega al buzón local gestionado por Dovecot. Al ser una red cerrada, no hay relay externo — toda la entrega es local dentro del dominio `streamvault.local`.

### 5.2 Flujo de entrega

```
Spring Boot (VM-2)
    └── JavaMailSender → SMTP TCP:25 → Postfix (VM-3)
                                            │
                              ¿destinatario en @streamvault.local?
                                            │
                                    SÍ ─────┘
                                            │
                              Postfix → entrega a Dovecot
                              via LMTP o mailbox local
                                            │
                              Buzón: /var/mail/streamvault/{usuario}
```

### 5.3 Configuración principal

Archivo: `/etc/postfix/main.cf`

```ini
# ── Identidad del servidor ────────────────────────────────
myhostname    = mail.streamvault.local
mydomain      = streamvault.local
myorigin      = $mydomain

# ── Interfaces de escucha ─────────────────────────────────
inet_interfaces = all
inet_protocols  = ipv4

# ── Dominios que Postfix acepta como destino local ────────
mydestination = $myhostname, $mydomain, localhost.$mydomain, localhost

# ── Red interna autorizada para enviar correo ─────────────
mynetworks = 192.168.1.0/24, 127.0.0.0/8

# ── Entrega local via Dovecot (LMTP) ──────────────────────
virtual_transport         = lmtp:unix:private/dovecot-lmtp
virtual_mailbox_domains   = streamvault.local
virtual_mailbox_maps      = hash:/etc/postfix/vmailbox
virtual_alias_maps        = hash:/etc/postfix/virtual

# ── Límites ───────────────────────────────────────────────
message_size_limit  = 10240000   ; 10 MB máximo por email
mailbox_size_limit  = 51200000   ; 50 MB máximo por buzón

# ── Sin relay externo (red cerrada) ───────────────────────
relayhost =
smtp_use_tls = no
```

### 5.4 Tabla de buzones virtuales

Archivo: `/etc/postfix/vmailbox`

```
# formato: email@dominio    dominio/usuario/
noreply@streamvault.local        streamvault.local/noreply/
admin@streamvault.local          streamvault.local/admin/
```

> Los buzones de usuarios normales se agregan dinámicamente. Ver sección 6.4 para el proceso de creación de buzón al registrar un usuario.

Archivo: `/etc/postfix/virtual` (aliases)

```
# Redirige postmaster al admin
postmaster@streamvault.local    admin@streamvault.local
```

Después de editar estos archivos siempre ejecutar:

```bash
postmap /etc/postfix/vmailbox
postmap /etc/postfix/virtual
postfix reload
```

---

## 6. Servicio de Buzones — Dovecot

### 6.1 Responsabilidad

Dovecot actúa como **MDA (Mail Delivery Agent)** e **IMAP server**. Recibe los emails entregados por Postfix, los almacena en disco en formato Maildir, y los expone vía protocolo IMAP para que el cliente Thunderbird pueda leerlos.

### 6.2 Formato de almacenamiento — Maildir

Cada usuario tiene su propio directorio con la estructura:

```
/var/mail/streamvault/
├── noreply/
│   ├── cur/        ← emails leídos
│   ├── new/        ← emails nuevos sin leer
│   └── tmp/        ← emails en proceso de entrega
├── admin/
│   ├── cur/
│   ├── new/
│   └── tmp/
└── usuario1/       ← creado al registrarse en la plataforma
    ├── cur/
    ├── new/
    └── tmp/
```

### 6.3 Configuración principal

Archivo: `/etc/dovecot/dovecot.conf`

```ini
# ── Protocolos habilitados ────────────────────────────────
protocols = imap

# ── Interfaces de escucha ─────────────────────────────────
listen = 192.168.1.30, 127.0.0.1

# ── Sin TLS en red interna cerrada ────────────────────────
ssl = no

# ── Formato de buzón ──────────────────────────────────────
mail_location = maildir:/var/mail/streamvault/%u

# ── Autenticación ─────────────────────────────────────────
auth_mechanisms = plain login

passdb {
  driver = passwd-file
  args   = /etc/dovecot/passwd
}

userdb {
  driver = static
  args   = uid=vmail gid=vmail home=/var/mail/streamvault/%u
}

# ── Socket LMTP para recibir correo de Postfix ────────────
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    group = postfix
    mode  = 0600
    user  = postfix
  }
}

# ── Puerto IMAP ───────────────────────────────────────────
service imap-login {
  inet_listener imap {
    port = 143
  }
}
```

### 6.4 Gestión de usuarios en Dovecot

Los buzones se registran en el archivo de contraseñas de Dovecot:

Archivo: `/etc/dovecot/passwd`

```
# formato: usuario@dominio:{PLAIN}contraseña
noreply@streamvault.local:{PLAIN}noreply2025
admin@streamvault.local:{PLAIN}admin2025
```

#### Crear un buzón nuevo manualmente

Cuando se registra un usuario en la plataforma, el buzón debe crearse en VM-3. En la fase actual esto se hace **manualmente** por el administrador:

```bash
# 1. Crear el directorio Maildir
mkdir -p /var/mail/streamvault/usuario1/{cur,new,tmp}
chown -R vmail:vmail /var/mail/streamvault/usuario1

# 2. Agregar al archivo de contraseñas de Dovecot
echo "usuario1@streamvault.local:{PLAIN}contrasena123" \
  >> /etc/dovecot/passwd

# 3. Agregar a la tabla de buzones de Postfix
echo "usuario1@streamvault.local  streamvault.local/usuario1/" \
  >> /etc/postfix/vmailbox
postmap /etc/postfix/vmailbox
postfix reload

# 4. Recargar Dovecot
doveadm reload
```

> **Implicación para el backend:** En esta fase del proyecto el administrador crea los buzones manualmente después de que un usuario se registra. Una mejora futura sería que el backend llame a un script en VM-3 vía SSH o una API interna para automatizar este proceso.

### 6.5 Configuración de Thunderbird para leer el buzón

Cada usuario configura Thunderbird con los siguientes parámetros:

| Parámetro | Valor |
|---|---|
| Protocolo | IMAP |
| Servidor entrante | `imap.streamvault.local` o `192.168.1.30` |
| Puerto IMAP | `143` |
| Seguridad de conexión | Ninguna (red interna cerrada) |
| Método de autenticación | Contraseña normal |
| Usuario | `usuario@streamvault.local` |
| Contraseña | La definida en `/etc/dovecot/passwd` |

---

## 7. Flujo Completo del Correo

### 7.1 Email de bienvenida al registrarse

```
① Usuario llena formulario de registro en Angular (VM-1)
      email: usuario1@streamvault.local

② Angular → POST /api/v1/auth/register → Spring Boot (VM-2)

③ Spring Boot crea el usuario en PostgreSQL (VM-3 :5432)

④ Spring Boot → JavaMailSender
      from:    noreply@streamvault.local
      to:      usuario1@streamvault.local
      subject: Bienvenido a StreamVault
      body:    welcome.html (Thymeleaf)

⑤ JavaMailSender → SMTP TCP:25 → Postfix (VM-3)

⑥ Postfix consulta /etc/postfix/vmailbox
      usuario1@streamvault.local → streamvault.local/usuario1/

⑦ Postfix → LMTP socket → Dovecot

⑧ Dovecot escribe el email en:
      /var/mail/streamvault/usuario1/new/{timestamp}.eml

⑨ Usuario abre Thunderbird
      IMAP TCP:143 → imap.streamvault.local
      Bandeja de entrada → ve el email de bienvenida
```

### 7.2 Email entre usuarios (formulario de contacto)

```
① Usuario X llena el formulario de contacto en Angular
      to:      usuario2@streamvault.local
      subject: Hola
      body:    Mensaje de texto

② Angular → POST /api/v1/mail/send → Spring Boot (VM-2)

③ Spring Boot valida JWT, aplica rate limiting (5/hora)

④ Spring Boot guarda en PostgreSQL tabla mail_messages

⑤ Spring Boot → JavaMailSender
      from:     noreply@streamvault.local
      reply-to: usuario1@streamvault.local   ← email real del remitente
      to:       usuario2@streamvault.local
      subject:  [StreamVault] Hola

⑥ JavaMailSender → SMTP TCP:25 → Postfix (VM-3)

⑦ Postfix entrega → Dovecot → buzón de usuario2

⑧ Usuario2 abre Thunderbird → ve el mensaje en su bandeja
   Si responde, el email va a reply-to: usuario1@streamvault.local
   → Postfix → Dovecot → buzón de usuario1
```

### 7.3 Email de recuperación de contraseña

```
① Usuario solicita recuperación desde Angular
      POST /api/v1/auth/forgot-password { email: usuario1@streamvault.local }

② Spring Boot genera token de recuperación (UUID, TTL 1 hora)
   Guarda el token en PostgreSQL

③ Spring Boot → JavaMailSender
      to:      usuario1@streamvault.local
      subject: Recupera tu contraseña de StreamVault
      body:    reset-password.html
               Link: https://streamvault.local/reset?token={uuid}

④ Postfix → Dovecot → buzón de usuario1

⑤ Usuario1 abre Thunderbird → ve el email
   Hace clic en el link → Angular abre la vista de nueva contraseña

⑥ Angular → POST /api/v1/auth/reset-password { token, newPassword }
   Spring Boot valida el token, actualiza el hash en PostgreSQL
```

---

## 8. Base de Datos — PostgreSQL

### 8.1 Responsabilidad

PostgreSQL almacena todas las entidades relacionales de la plataforma. Es el único servicio de persistencia de la AS — MinIO solo almacena objetos binarios (videos y miniaturas).

### 8.2 Configuración

Archivo: `/etc/postgresql/16/main/postgresql.conf`

```ini
listen_addresses = '192.168.1.30, localhost'
port             = 5432
max_connections  = 100

# Rendimiento básico para VM de laboratorio
shared_buffers          = 128MB
work_mem                = 4MB
maintenance_work_mem    = 64MB
effective_cache_size    = 256MB

# Logging
log_destination         = 'stderr'
logging_collector       = on
log_directory           = 'log'
log_filename            = 'postgresql-%Y-%m-%d.log'
log_min_duration_statement = 1000   ; loguear queries > 1 segundo
```

Archivo: `/etc/postgresql/16/main/pg_hba.conf`

```
# TYPE  DATABASE    USER        ADDRESS             METHOD
local   all         postgres                        peer
host    streamvault streamvault 192.168.1.20/32     md5   # VM-2 Backend
host    all         all         127.0.0.1/32        md5
```

> Solo VM-2 (`192.168.1.20`) tiene acceso a la base de datos `streamvault`. Ninguna otra VM puede conectarse directamente.

### 8.3 Inicialización de la base de datos

```sql
-- Ejecutar como superusuario postgres en VM-3

CREATE DATABASE streamvault
    WITH ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE   = 'en_US.UTF-8';

CREATE USER streamvault WITH PASSWORD 'streamvault2025';
GRANT ALL PRIVILEGES ON DATABASE streamvault TO streamvault;

-- Conectar a la base de datos
\c streamvault

-- Extensión para UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

### 8.4 Migraciones con Flyway

Las migraciones son gestionadas desde el backend Spring Boot con Flyway. Al arrancar el backend, Flyway aplica automáticamente los scripts SQL en orden:

```
streamvault-backend/
└── src/main/resources/db/migration/
    ├── V1__create_users.sql
    ├── V2__create_profiles_subscriptions.sql
    ├── V3__create_content_catalog.sql
    ├── V4__create_watch_history.sql
    ├── V5__create_refresh_tokens.sql
    ├── V6__create_mail_messages.sql
    └── V7__seed_genres.sql
```

### 8.5 Esquema completo de tablas

```
users ──────────────── subscriptions       (1:1)
  │
  ├────────────────── profiles             (1:N, máx 4)
  │                      │
  │                      └──── watch_history ──── episodes
  │
  ├────────────────── refresh_tokens       (1:N)
  └────────────────── mail_messages        (1:N como sender)

content ─────────────── seasons            (1:N)
  │                        └──── episodes  (1:N)
  │
  └────────────────── content_genres ──── genres  (N:N)
```

### 8.6 Backup básico

```bash
# Backup manual de la base de datos
pg_dump -U streamvault -h localhost streamvault \
  > /backups/streamvault_$(date +%Y%m%d).sql

# Restaurar
psql -U streamvault -h localhost streamvault \
  < /backups/streamvault_20250101.sql
```

---

## 9. Almacenamiento de Video — MinIO

### 9.1 Responsabilidad

MinIO provee almacenamiento de objetos compatible con la API S3 de AWS. Almacena los videos en formato HLS (`.m3u8` + `.ts`) y las miniaturas de los contenidos. El backend genera URLs pre-firmadas con expiración para que el player Angular descargue directamente los segmentos de video sin pasar por el backend.

### 9.2 Estructura de buckets

```
Bucket: streamvault-videos
└── content/
      └── {contentId}/
            ├── hls/
            │     ├── master.m3u8          ← manifest principal
            │     ├── segment000.ts
            │     ├── segment001.ts
            │     └── ...
            └── episodes/                  ← para series
                  └── {episodeId}/
                        ├── master.m3u8
                        └── segment*.ts

Bucket: streamvault-thumbnails
└── content/
      └── {contentId}/
            └── thumbnail.{jpg|png|webp}
```

### 9.3 Políticas de acceso

| Bucket | Política | Razón |
|---|---|---|
| `streamvault-videos` | Privado | Solo accesible mediante URL pre-firmada con expiración de 2 horas |
| `streamvault-thumbnails` | Público de solo lectura | Las miniaturas se muestran libremente en el catálogo sin necesidad de firma |

### 9.4 Configuración del contenedor MinIO

```yaml
# En docker-compose.yml (ver sección 11)
environment:
  MINIO_ROOT_USER:     ${MINIO_ROOT_USER}
  MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
  MINIO_DOMAIN:        minio.streamvault.local

volumes:
  - minio_data:/data

command: server /data --console-address ":9001"
```

### 9.5 Inicialización de buckets

Al arrancar MinIO por primera vez, crear los buckets desde la consola web (`http://192.168.1.30:9001`) o via CLI con `mc` (MinIO Client):

```bash
# Instalar MinIO Client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/

# Configurar alias
mc alias set streamvault http://192.168.1.30:9000 \
  ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}

# Crear buckets
mc mb streamvault/streamvault-videos
mc mb streamvault/streamvault-thumbnails

# Política pública para miniaturas
mc anonymous set download streamvault/streamvault-thumbnails

# Verificar
mc ls streamvault
```

### 9.6 Creación del usuario de aplicación en MinIO

No se debe usar el usuario root desde el backend. Crear un usuario específico para la aplicación:

```bash
# Crear usuario de aplicación
mc admin user add streamvault streamvault-app ${MINIO_APP_PASSWORD}

# Crear política de acceso
cat > /tmp/streamvault-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::streamvault-videos/*",
        "arn:aws:s3:::streamvault-thumbnails/*"
      ]
    }
  ]
}
EOF

mc admin policy create streamvault streamvault-policy \
  /tmp/streamvault-policy.json

# Asignar política al usuario de aplicación
mc admin policy attach streamvault streamvault-policy \
  --user streamvault-app
```

> Las credenciales `streamvault-app` son las que se configuran en las variables de entorno del backend (`MINIO_ACCESS_KEY` y `MINIO_SECRET_KEY`), nunca las del usuario root.

---

## 10. Protocolos por Capa OSI

| Capa OSI | Protocolo | Servicio en VM-3 | Dirección |
|---|---|---|---|
| **L7 Aplicación** | DNS (queries/responses) | BIND9 | Entrante desde VM-1, VM-2 |
| **L7 Aplicación** | SMTP | Postfix | Entrante desde VM-2 |
| **L7 Aplicación** | IMAP | Dovecot | Entrante desde Thunderbird |
| **L7 Aplicación** | LMTP | Postfix → Dovecot | Interno en VM-3 |
| **L7 Aplicación** | PostgreSQL Wire Protocol | PostgreSQL | Entrante desde VM-2 |
| **L7 Aplicación** | HTTP / S3 API | MinIO | Entrante desde VM-2 |
| **L6 Presentación** | TLS 1.3 (opcional) | Dovecot IMAPS | Entrante desde Thunderbird |
| **L4 Transporte** | UDP | BIND9 | Queries DNS estándar |
| **L4 Transporte** | TCP | SMTP, IMAP, PostgreSQL, MinIO, DNS TCP | Todas las conexiones persistentes |
| **L3 Red** | IPv4 | Todos los servicios | Red interna `192.168.1.0/24` |

### Resumen de puertos abiertos en VM-3

| Puerto | Protocolo | Servicio | Accesible desde |
|---|---|---|---|
| `53` | UDP/TCP | BIND9 DNS | VM-1, VM-2 |
| `25` | TCP | Postfix SMTP | VM-2 (backend) |
| `143` | TCP | Dovecot IMAP | Clientes Thunderbird en la red |
| `993` | TCP | Dovecot IMAPS (TLS) | Opcional — clientes con TLS |
| `5432` | TCP | PostgreSQL | VM-2 exclusivamente |
| `9000` | TCP | MinIO S3 API | VM-2 exclusivamente |
| `9001` | TCP | MinIO Console Web | Administrador (red interna) |

---

## 11. Configuración Docker

### 11.1 `docker-compose.yml` completo para VM-3

```yaml
services:

  # ── DNS ────────────────────────────────────────────────
  dns:
    image: internetsystemsconsortium/bind9:9.18
    container_name: streamvault-dns
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./bind9/named.conf:/etc/bind/named.conf:ro
      - ./bind9/named.conf.options:/etc/bind/named.conf.options:ro
      - ./bind9/named.conf.local:/etc/bind/named.conf.local:ro
      - ./bind9/zones:/etc/bind/zones:ro
    restart: unless-stopped

  # ── SMTP ───────────────────────────────────────────────
  smtp:
    image: boky/postfix:latest
    container_name: streamvault-smtp
    ports:
      - "25:25"
    environment:
      - ALLOWED_SENDER_DOMAINS=streamvault.local
      - RELAYHOST=
      - POSTFIX_myhostname=mail.streamvault.local
      - POSTFIX_mydomain=streamvault.local
      - POSTFIX_mynetworks=192.168.1.0/24 127.0.0.0/8
    volumes:
      - ./postfix/main.cf:/etc/postfix/main.cf:ro
      - ./postfix/vmailbox:/etc/postfix/vmailbox:ro
      - ./postfix/virtual:/etc/postfix/virtual:ro
      - dovecot_socket:/var/spool/postfix/private
    depends_on:
      - imap
    restart: unless-stopped

  # ── IMAP ───────────────────────────────────────────────
  imap:
    image: dovecot/dovecot:latest
    container_name: streamvault-imap
    ports:
      - "143:143"
      - "993:993"
    volumes:
      - ./dovecot/dovecot.conf:/etc/dovecot/dovecot.conf:ro
      - ./dovecot/passwd:/etc/dovecot/passwd:ro
      - maildata:/var/mail/streamvault
      - dovecot_socket:/var/spool/postfix/private
    restart: unless-stopped

  # ── BASE DE DATOS ──────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    container_name: streamvault-postgres
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=streamvault
      - POSTGRES_USER=streamvault
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U streamvault"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ── ALMACENAMIENTO ─────────────────────────────────────
  minio:
    image: minio/minio:latest
    container_name: streamvault-minio
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
      - MINIO_DOMAIN=minio.streamvault.local
    volumes:
      - miniodata:/data
    command: server /data --console-address ":9001"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

# ── Volúmenes persistentes ─────────────────────────────────
volumes:
  pgdata:
  miniodata:
  maildata:
  dovecot_socket:

# ── Red interna del compose ────────────────────────────────
networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
```

### 11.2 Estructura de archivos de configuración en VM-3

```
vm3-services/
├── docker-compose.yml
├── .env
├── bind9/
│   ├── named.conf
│   ├── named.conf.options
│   ├── named.conf.local
│   └── zones/
│       ├── streamvault.local.zone
│       └── 192.168.1.rev
├── postfix/
│   ├── main.cf
│   ├── vmailbox
│   └── virtual
├── dovecot/
│   ├── dovecot.conf
│   └── passwd
└── postgres/
    ├── pg_hba.conf
    └── init.sql
```

---

## 12. Variables de Entorno

Archivo: `vm3-services/.env`

```env
# ── PostgreSQL ────────────────────────────────────────────
DB_PASSWORD=streamvault2025

# ── MinIO ─────────────────────────────────────────────────
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin2025
MINIO_APP_USER=streamvault-app
MINIO_APP_PASSWORD=minio-app-2025
```

| Variable | Descripción |
|---|---|
| `DB_PASSWORD` | Contraseña del usuario PostgreSQL `streamvault` |
| `MINIO_ROOT_USER` | Usuario root de MinIO — solo para administración inicial |
| `MINIO_ROOT_PASSWORD` | Contraseña root de MinIO |
| `MINIO_APP_USER` | Usuario de aplicación MinIO — usado por el backend |
| `MINIO_APP_PASSWORD` | Contraseña del usuario de aplicación MinIO |

> El archivo `.env` nunca debe subirse al repositorio. Agregar al `.gitignore`.

---

## 13. Orden de Arranque de Servicios

El orden es importante. Algunos servicios dependen de que otros estén listos primero:

```
1. DNS (BIND9)
      └── Sin dependencias — debe arrancar primero para que
          los demás servicios resuelvan nombres internos

2. PostgreSQL
      └── Sin dependencias de otros servicios en VM-3
          El backend (VM-2) no arranca hasta que este esté listo

3. MinIO
      └── Sin dependencias de otros servicios en VM-3

4. Dovecot (IMAP)
      └── Debe estar corriendo antes que Postfix
          para que el socket LMTP esté disponible

5. Postfix (SMTP)
      └── Depende de Dovecot (socket LMTP)

6. Backend Spring Boot (VM-2)
      └── Depende de PostgreSQL, MinIO y SMTP
          Flyway aplica migraciones al arrancar

7. Frontend Angular + NGINX (VM-1)
      └── Depende de que el backend esté respondiendo
```

```bash
# Arranque correcto en VM-3
cd vm3-services

# Arrancar en orden con espera entre servicios críticos
docker compose up -d dns
sleep 5
docker compose up -d postgres minio
sleep 10
docker compose up -d imap
sleep 5
docker compose up -d smtp

# Verificar que todos están healthy
docker compose ps
```

---

## 14. Verificación y Pruebas

### 14.1 Verificar DNS

```bash
# Desde VM-1 o VM-2
nslookup api.streamvault.local 192.168.1.30
nslookup mail.streamvault.local 192.168.1.30
nslookup db.streamvault.local 192.168.1.30

# Esperado: todas resuelven a sus IPs correctas
```

### 14.2 Verificar SMTP

```bash
# Desde VM-2 — probar conexión SMTP manualmente con telnet
telnet mail.streamvault.local 25

# Secuencia SMTP manual
EHLO vm2.streamvault.local
MAIL FROM:<noreply@streamvault.local>
RCPT TO:<admin@streamvault.local>
DATA
Subject: Test

Cuerpo del mensaje de prueba
.
QUIT
```

### 14.3 Verificar entrega en Dovecot

```bash
# Desde VM-3 — verificar que el email llegó al buzón
ls -la /var/mail/streamvault/admin/new/

# O usando doveadm
doveadm mailbox list -u admin@streamvault.local
doveadm fetch -u admin@streamvault.local "text" mailbox INBOX all
```

### 14.4 Verificar PostgreSQL

```bash
# Desde VM-3
psql -U streamvault -d streamvault -c "\dt"

# Desde VM-2 — verificar conectividad
pg_isready -h db.streamvault.local -p 5432 -U streamvault
```

### 14.5 Verificar MinIO

```bash
# Health check via HTTP
curl http://192.168.1.30:9000/minio/health/live

# Listar buckets
mc ls streamvault

# Esperado:
# [fecha] streamvault-videos
# [fecha] streamvault-thumbnails
```

### 14.6 Verificar Thunderbird — checklist

```
□ Thunderbird instalado en la máquina del usuario
□ Cuenta configurada con IMAP → imap.streamvault.local:143
□ Usuario: usuario@streamvault.local
□ Contraseña correcta en /etc/dovecot/passwd
□ Buzón creado en /var/mail/streamvault/{usuario}/
□ Entrada en /etc/postfix/vmailbox con postmap ejecutado
□ Postfix recargado después del cambio
□ Email de prueba enviado desde telnet o desde la plataforma
□ Email aparece en Thunderbird → Bandeja de entrada
```

---

*PRD v1.0 — VM-3 Network Services — StreamVault — Equipo Betha — 2025*
