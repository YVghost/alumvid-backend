-- =========================================================================================
-- PROYECTO DE TITULACION: GLASSFLOW - ARQUITECTURA DE MICROSERVICIOS Y LOGISTICA GEOESPACIAL
-- SCRIPT DE INICIALIZACION DDL Y DATOS BASE: init.sql
-- =========================================================================================

-- -----------------------------------------------------------------------------------------
-- 1. BASE DE DATOS: glassflow_auth_db (MICROSERVICIO DE AUTENTICACION Y RBAC)
-- -----------------------------------------------------------------------------------------
\connect glassflow_auth_db;

CREATE TABLE IF NOT EXISTS public.usuarios (
    id UUID NOT NULL,
    email VARCHAR(150) NOT NULL,
    password VARCHAR(255) NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    rol VARCHAR(30) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP(6) WITHOUT TIME ZONE,
    updated_at TIMESTAMP(6) WITHOUT TIME ZONE,
    CONSTRAINT usuarios_pkey PRIMARY KEY (id),
    CONSTRAINT uk_usuarios_email UNIQUE (email),
    CONSTRAINT usuarios_rol_check CHECK (rol IN ('ROLE_ADMIN', 'ROLE_CHOFER', 'ROLE_OPERARIO'))
);

-- Insercion del unico usuario administrador inicial del sistema
-- Credenciales: admin@glassflow.com / GlassFlowAdmin2026! (BCrypt strength 12)
INSERT INTO public.usuarios (id, email, password, nombre, telefono, rol, activo, created_at, updated_at)
VALUES (
    'd95e831c-7de6-4e75-9e3f-2074a9b97044',
    'admin@glassflow.com',
    '$2a$12$Rd/X6s3Y1t7VtBqg9l3RSOsM9OwssuwzJRZNhliGEnkO6KvJpSCtC',
    'Administrador de Operaciones',
    '+593999999999',
    'ROLE_ADMIN',
    true,
    NOW(),
    NOW()
)
ON CONFLICT (email) DO NOTHING;

-- -----------------------------------------------------------------------------------------
-- 2. BASE DE DATOS: glassflow_logistica_db (MICROSERVICIO DE LOGISTICA Y POSTGIS)
-- -----------------------------------------------------------------------------------------
\connect glassflow_logistica_db;

-- Habilitar extension espacial PostGIS para computo de geocercas y metricas cartograficas
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS public.choferes (
    id UUID NOT NULL,
    email VARCHAR(150) NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    estado_disponibilidad VARCHAR(30) NOT NULL DEFAULT 'DISPONIBLE',
    created_at TIMESTAMP(6) WITHOUT TIME ZONE,
    updated_at TIMESTAMP(6) WITHOUT TIME ZONE,
    CONSTRAINT choferes_pkey PRIMARY KEY (id),
    CONSTRAINT uk_choferes_email UNIQUE (email),
    CONSTRAINT choferes_estado_disponibilidad_check CHECK (estado_disponibilidad IN ('DISPONIBLE', 'EN_RUTA', 'INACTIVO'))
);

CREATE TABLE IF NOT EXISTS public.pedidos (
    id UUID NOT NULL,
    cliente VARCHAR(150) NOT NULL,
    direccion_texto VARCHAR(255) NOT NULL,
    coordenada_destino geometry(Point, 4326) NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE',
    fecha_solicitud TIMESTAMP(6) WITHOUT TIME ZONE,
    updated_at TIMESTAMP(6) WITHOUT TIME ZONE,
    CONSTRAINT pedidos_pkey PRIMARY KEY (id),
    CONSTRAINT pedidos_estado_check CHECK (estado IN ('PENDIENTE', 'EN_RUTA', 'ENTREGADO', 'CANCELADO'))
);

CREATE INDEX IF NOT EXISTS idx_pedidos_coordenada_destino ON public.pedidos USING GIST (coordenada_destino);

CREATE TABLE IF NOT EXISTS public.rutas (
    id UUID NOT NULL,
    codigo_ruta VARCHAR(50) NOT NULL,
    chofer_id UUID,
    estado VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE',
    fecha_creacion TIMESTAMP(6) WITHOUT TIME ZONE NOT NULL,
    fecha_inicio TIMESTAMP(6) WITHOUT TIME ZONE,
    fecha_fin TIMESTAMP(6) WITHOUT TIME ZONE,
    comentarios TEXT,
    created_at TIMESTAMP(6) WITHOUT TIME ZONE,
    updated_at TIMESTAMP(6) WITHOUT TIME ZONE,
    CONSTRAINT rutas_pkey PRIMARY KEY (id),
    CONSTRAINT uk_rutas_codigo_ruta UNIQUE (codigo_ruta),
    CONSTRAINT fk_rutas_chofer FOREIGN KEY (chofer_id) REFERENCES public.choferes(id),
    CONSTRAINT rutas_estado_check CHECK (estado IN ('PENDIENTE', 'EN_CURSO', 'COMPLETADA', 'CANCELADA'))
);

CREATE TABLE IF NOT EXISTS public.despachos (
    id UUID NOT NULL,
    ruta_id UUID,
    orden_parada INTEGER,
    chofer_id UUID,
    pedido_id UUID NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'PENDIENTE',
    fecha_asignacion TIMESTAMP(6) WITHOUT TIME ZONE NOT NULL,
    fecha_inicio_ruta TIMESTAMP(6) WITHOUT TIME ZONE,
    fecha_entrega TIMESTAMP(6) WITHOUT TIME ZONE,
    coordenada_entrega geometry(Point, 4326),
    desviacion_metros DOUBLE PRECISION,
    alerta_desviacion BOOLEAN,
    foto_pod_url TEXT,
    firma_url TEXT,
    comentarios TEXT,
    created_at TIMESTAMP(6) WITHOUT TIME ZONE,
    updated_at TIMESTAMP(6) WITHOUT TIME ZONE,
    CONSTRAINT despachos_pkey PRIMARY KEY (id),
    CONSTRAINT fk_despachos_ruta FOREIGN KEY (ruta_id) REFERENCES public.rutas(id),
    CONSTRAINT fk_despachos_chofer FOREIGN KEY (chofer_id) REFERENCES public.choferes(id),
    CONSTRAINT fk_despachos_pedido FOREIGN KEY (pedido_id) REFERENCES public.pedidos(id),
    CONSTRAINT despachos_estado_check CHECK (estado IN ('PENDIENTE', 'EN_CURSO', 'ENTREGADO', 'CANCELADA'))
);

CREATE INDEX IF NOT EXISTS idx_despachos_coordenada_entrega ON public.despachos USING GIST (coordenada_entrega);
