CREATE TABLE usuarios.app_user (
 id UUID PRIMARY KEY,
 identification VARCHAR(30) NOT NULL UNIQUE,
 full_name VARCHAR(120) NOT NULL,
 password_hash VARCHAR(100) NOT NULL,
 roles VARCHAR(100) NOT NULL,
 master BOOLEAN NOT NULL DEFAULT FALSE,
 active BOOLEAN NOT NULL DEFAULT TRUE,
 must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX one_master ON usuarios.app_user(master) WHERE master = TRUE;
CREATE TABLE usuarios.auth_session (
 token_hash VARCHAR(64) PRIMARY KEY,
 user_id UUID NOT NULL REFERENCES usuarios.app_user(id),
 expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX session_user ON usuarios.auth_session(user_id);
CREATE TABLE usuarios.audit_event (
 id UUID PRIMARY KEY,
 actor_id UUID REFERENCES usuarios.app_user(id),
 target_id UUID REFERENCES usuarios.app_user(id),
 action VARCHAR(50) NOT NULL,
 detail VARCHAR(500) NOT NULL,
 occurred_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
