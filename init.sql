-- =========================================================================================
-- PROYECTO DE TITULACION: ALUMVID - PLATAFORMA DE GESTION INTEGRAL, INVENTARIO Y LOGISTICA
-- SCRIPT DE INICIALIZACION DDL Y POSTGIS: init.sql
-- =========================================================================================

-- Habilitar extension espacial PostGIS para computo de geocercas y metricas cartograficas
CREATE EXTENSION IF NOT EXISTS postgis;

-- Creacion de esquemas por microservicio para arquitectura desacoplada
CREATE SCHEMA IF NOT EXISTS usuarios;
CREATE SCHEMA IF NOT EXISTS inventario;
CREATE SCHEMA IF NOT EXISTS logistica;

-- Tabla de logistica: choferes, pedidos, rutas, despachos dentro del esquema logistica
CREATE TABLE IF NOT EXISTS logistica.choferes (
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

CREATE TABLE IF NOT EXISTS logistica.pedidos (
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

CREATE INDEX IF NOT EXISTS idx_pedidos_coordenada_destino ON logistica.pedidos USING GIST (coordenada_destino);

CREATE TABLE IF NOT EXISTS logistica.rutas (
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
    CONSTRAINT fk_rutas_chofer FOREIGN KEY (chofer_id) REFERENCES logistica.choferes(id),
    CONSTRAINT rutas_estado_check CHECK (estado IN ('PENDIENTE', 'EN_CURSO', 'COMPLETADA', 'CANCELADA'))
);

CREATE TABLE IF NOT EXISTS logistica.despachos (
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
    CONSTRAINT fk_despachos_ruta FOREIGN KEY (ruta_id) REFERENCES logistica.rutas(id),
    CONSTRAINT fk_despachos_chofer FOREIGN KEY (chofer_id) REFERENCES logistica.choferes(id),
    CONSTRAINT fk_despachos_pedido FOREIGN KEY (pedido_id) REFERENCES logistica.pedidos(id),
    CONSTRAINT despachos_estado_check CHECK (estado IN ('PENDIENTE', 'EN_CURSO', 'ENTREGADO', 'CANCELADA'))
);

CREATE INDEX IF NOT EXISTS idx_despachos_coordenada_entrega ON logistica.despachos USING GIST (coordenada_entrega);
