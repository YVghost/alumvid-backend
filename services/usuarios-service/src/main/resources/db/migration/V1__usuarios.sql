CREATE SCHEMA IF NOT EXISTS usuarios;

CREATE TABLE IF NOT EXISTS usuarios.app_user (
    id UUID PRIMARY KEY,
    identification VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(150),
    telefono VARCHAR(30),
    full_name VARCHAR(120) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    roles VARCHAR(100) NOT NULL,
    master BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS one_master ON usuarios.app_user(master) WHERE master = TRUE;
CREATE INDEX IF NOT EXISTS idx_usuarios_email ON usuarios.app_user(email);

CREATE TABLE IF NOT EXISTS usuarios.auth_session (
    token_hash VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES usuarios.app_user(id),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX IF NOT EXISTS auth_session_user_idx ON usuarios.auth_session(user_id);

CREATE TABLE IF NOT EXISTS usuarios.audit_event (
    id UUID PRIMARY KEY,
    actor_id UUID REFERENCES usuarios.app_user(id),
    target_id UUID REFERENCES usuarios.app_user(id),
    action VARCHAR(50) NOT NULL,
    detail VARCHAR(500) NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
