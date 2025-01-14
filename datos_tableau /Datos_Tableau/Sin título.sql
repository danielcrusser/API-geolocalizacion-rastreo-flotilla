
-----VERSION FINAL COMPONENTES DE ACTUALIZACION DE RUTAS Y REGISTRO DE RUTAS--------------------


select * from vista_Seguimiento_rutas order by hora_cdmx desc;

SELECT * FROM prueba_transporte."rideMarcador_pg";
select * from prueba_transporte."driver_history" order by updated_at desc where idconductor = '1' and "Ruta" = 'PRUEBA';
select * from prueba_transporte.viajes where idconductor = '1';
select * from prueba_transporte.activity_logs WHERE idconductor = '1';
alter table prueba_transporte."rideMarcador_pg" add column fotoconductor varchar;}}
SELECT * FROM prueba_transporte.chofer_id;


CREATE TABLE IF NOT EXISTS prueba_transporte.driver_history
(
    id integer NOT NULL DEFAULT nextval('prueba_transporte.driver_history_id_seq'::regclass),
    original_id integer NOT NULL,
    driver_location jsonb,
    idconductor character varying COLLATE pg_catalog."default",
    "nombreConductor" character varying COLLATE pg_catalog."default",
    "numUrban" character varying COLLATE pg_catalog."default",
    updated_at timestamp with time zone DEFAULT now(),
    "Ruta" character varying(10) COLLATE pg_catalog."default",
    viaje_id integer,
    CONSTRAINT driver_history_pkey PRIMARY KEY (id),
    CONSTRAINT driver_history_viaje_id_fkey FOREIGN KEY (viaje_id)
        REFERENCES prueba_transporte.viajes (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

---simple...
CREATE TABLE IF NOT EXISTS prueba_transporte.driver_history
(
    id SERIAL PRIMARY KEY,
    original_id INTEGER NOT NULL,
    driver_location JSONB,
    idconductor VARCHAR(7),
    nombreConductor VARCHAR(50),
    numUrban VARCHAR(5),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    Ruta VARCHAR(10),
    viaje_id INTEGER,
    CONSTRAINT driver_history_viaje_id_fkey FOREIGN KEY (viaje_id)
        REFERENCES prueba_transporte.viajes (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);


ALTER TABLE prueba_transporte.driver_history drop column lista;

--tabla para gestionar viajes...

CREATE TABLE prueba_transporte.viajes (
    id SERIAL PRIMARY KEY,
    idconductor INT NOT NULL,
    inicio TIMESTAMP WITH TIME ZONE NOT NULL,
    fin TIMESTAMP WITH TIME ZONE,
	"Ruta" VARCHAR(8),
	"nombreConductor" VARCHAR(50),
    estado VARCHAR(20) DEFAULT 'en_progreso' -- Puede ser 'en_progreso' o 'finalizado'
	
);
----AGREGAR RUTA Y CONDUCTOR A VIAJES
ALTER TABLE prueba_transporte.viajes
ADD COLUMN "Ruta" VARCHAR(8),
ADD COLUMN "nombreConductor" VARCHAR(50);


--PRUEBA MANUAL---ejecutar...y ver resultados
UPDATE prueba_transporte."rideMarcador_pg" SET driver_location = 
'{"latitude": 19.352320, "longitude": -99.273532}' WHERE idconductor = '6'; --prueba manual correcta


--trigger actualizado:
CREATE OR REPLACE TRIGGER transportes_update
AFTER UPDATE ON prueba_transporte."rideMarcador_pg"
FOR EACH ROW
WHEN (NEW.driver_location IS DISTINCT FROM OLD.driver_location)
EXECUTE FUNCTION prueba_transporte.log_driver_updates();

ALTER TABLE prueba_transporte.driver_history
ADD COLUMN viaje_id INT REFERENCES prueba_transporte.viajes(id);

---LOGS-------------------


CREATE TABLE prueba_transporte.activity_logs (
    id SERIAL PRIMARY KEY,
	idconductor INTEGER,
    action_type TEXT,  -- 'error' o 'correcto'
    action_description TEXT,
    log_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE prueba_transporte.chofer_id (
	id SERIAL PRIMARY KEY,
	nombre_apellido VARCHAR,
	foto BYTEA,
	status VARCHAR,
	fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);



INSERT INTO prueba_transporte.chofer_id ( nombre_apellido,
	foto,
	status
	) VALUES ('Emilio Maza Alvarez', 'null', 'activo');


----corregido solo registrando errores...
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    BEGIN
        -- Verificar si driver_location contiene los campos necesarios
        IF NEW.driver_location ? 'latitude' AND NEW.driver_location ? 'longitude' THEN
            -- Extraer latitud y longitud del JSONB
            latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
            longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;
        ELSE
            RAISE EXCEPTION 'driver_location no contiene los campos latitude o longitude';
        END IF;

        -- Calcular la distancia desde el punto central (estacionamiento)
        distancia := ST_Distance(
            ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
            ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
        );

        -- Convertir el idconductor a entero
        idconductor_int := NEW.idconductor::INT;

        -- Si la camioneta sale del radio (inicio de viaje)
        IF distancia > 50 THEN
            -- Buscar si hay un viaje en progreso
            SELECT id INTO viaje_actual
            FROM prueba_transporte.viajes
            WHERE idconductor = idconductor_int AND estado = 'en_progreso'
            LIMIT 1;

            -- Si no hay viaje en progreso, iniciar uno
            IF NOT FOUND THEN
                INSERT INTO prueba_transporte.viajes (idconductor, inicio, "Ruta", "nombreConductor", estado)
                VALUES (idconductor_int, NOW(), NEW."Ruta", NEW."nombreConductor", 'en_progreso')
                RETURNING id INTO viaje_actual;
            END IF;

            -- Registrar la coordenada en la tabla de historial
            INSERT INTO prueba_transporte.driver_history (
                original_id,
                driver_location,
                idconductor,
                "nombreConductor",
                "numUrban",
                "Ruta",
                updated_at,
                viaje_id
            )
            VALUES (
                NEW.id,
                NEW.driver_location,
                idconductor_int,
                NEW."nombreConductor",
                NEW."numUrban",
                NEW."Ruta",
                NOW(),
                viaje_actual
            );
        END IF;

        -- Si la camioneta regresa al radio (fin del viaje)
        IF distancia <= 50 THEN
            -- Finalizar el viaje actual
            UPDATE prueba_transporte.viajes
            SET fin = NOW(), estado = 'finalizado'
            WHERE idconductor = idconductor_int AND estado = 'en_progreso';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar el error en la tabla de logs
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('error', SQLERRM, idconductor_int);

            -- Lanzar el error para que se propague
            RAISE;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-------------V 3 -------------------
select * from vista_Seguimiento_rutas order by hora_cdmx desc;

SELECT * FROM prueba_transporte."rideMarcador_pg";
select * from prueba_transporte."driver_history" where idconductor = '7' and "Ruta" = 'RPRUE';
select * from prueba_transporte.viajes;

alter table prueba_transporte."rideMarcador_pg" add column fotoconductor varchar;}}



--tabla para gestionar viajes...

CREATE o replace TABLE prueba_transporte.viajes (
    id SERIAL PRIMARY KEY,
    idconductor INT NOT NULL,
    inicio TIMESTAMP NOT NULL,
    fin TIMESTAMP,
    estado VARCHAR(20) DEFAULT 'en_progreso' -- Puede ser 'en_progreso' o 'finalizado'
);
-----alteracion de tabla para poner con zona horaria
ALTER TABLE prueba_transporte.viajes
ALTER COLUMN inicio TYPE TIMESTAMP WITH TIME ZONE,
ALTER COLUMN fin TYPE TIMESTAMP WITH TIME ZONE;



--PRUEBA MANUAL---ejecutar...y ver resultados
UPDATE prueba_transporte."rideMarcador_pg" SET driver_location = 
'{"latitude": 19.347103, "longitude": -99.283231}' WHERE idconductor = '10'; --prueba manual correcta


--funcion actualizada:
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
BEGIN
    -- Extraer latitud y longitud del JSONB
    latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
    longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;

    -- Depuración: coordenadas extraídas
    RAISE NOTICE 'Latitud: %, Longitud: %', latitud, longitud;

    -- Calcular la distancia desde el punto central (estacionamiento)
    distancia := ST_Distance(
        ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
        ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
    );

    -- Depuración: distancia calculada
    RAISE NOTICE 'Distancia calculada: % metros', distancia;

    -- Si la camioneta sale del radio (inicio de viaje)
    IF distancia > 50 THEN
        RAISE NOTICE 'Camioneta fuera del radio, iniciando o continuando viaje';

        -- Buscar si hay un viaje en progreso
        SELECT id INTO viaje_actual
        FROM prueba_transporte.viajes
        WHERE idconductor = NEW.idconductor AND estado = 'en_progreso'
        LIMIT 1;

        -- Si no hay viaje en progreso, iniciar uno
        IF NOT FOUND THEN
            INSERT INTO prueba_transporte.viajes (idconductor, inicio, estado)
            VALUES (NEW.idconductor, NOW(), 'en_progreso')
            RETURNING id INTO viaje_actual;

            RAISE NOTICE 'Nuevo viaje iniciado con ID: %', viaje_actual;
        END IF;

        -- Registrar la coordenada en la tabla de historial
        INSERT INTO prueba_transporte.driver_history (
            original_id,
            lista,
            driver_location,
            idconductor,
            "nombreConductor",
            "numUrban",
            "Ruta",
            updated_at,
            viaje_id
        )
        VALUES (
            NEW.id,
            NEW.lista,
            NEW.driver_location,
            NEW.idconductor,
            NEW."nombreConductor",
            NEW."numUrban",
            NEW."Ruta",
            NOW(),
            viaje_actual
        );

        RAISE NOTICE 'Coordenada registrada para viaje ID: %', viaje_actual;
    END IF;

    -- Si la camioneta regresa al radio (fin del viaje)
    IF distancia <= 50 THEN
        RAISE NOTICE 'Camioneta regresó al radio, finalizando viaje';

        -- Finalizar el viaje actual
        UPDATE prueba_transporte.viajes
        SET fin = NOW(), estado = 'finalizado'
        WHERE idconductor = NEW.idconductor AND estado = 'en_progreso';

        RAISE NOTICE 'Viaje finalizado para conductor: %', NEW.idconductor;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--trigger actualizado:
CREATE OR REPLACE TRIGGER transportes_update
AFTER UPDATE ON prueba_transporte."rideMarcador_pg"
FOR EACH ROW
WHEN (NEW.driver_location IS DISTINCT FROM OLD.driver_location)
EXECUTE FUNCTION prueba_transporte.log_driver_updates();

sudo tail -f /var/log/postgresql/postgresql-<version>-main.log
---cambio de varchar a enetero idconductor de ridemarcador
ALTER TABLE prueba_transporte."rideMarcador_pg"
ALTER COLUMN idconductor TYPE VARCHAR USING idconductor::VARCHAR;

ALTER TABLE prueba_transporte.driver_history
ADD COLUMN viaje_id INT REFERENCES prueba_transporte.viajes(id);

-----PRUEBA CAST COMPLETA FUNCIONAL
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    -- Extraer latitud y longitud del JSONB
    latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
    longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;

    -- Depuración: coordenadas extraídas
    RAISE NOTICE 'Latitud: %, Longitud: %', latitud, longitud;

    -- Calcular la distancia desde el punto central (estacionamiento)
    distancia := ST_Distance(
        ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
        ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
    );

    -- Depuración: distancia calculada
    RAISE NOTICE 'Distancia calculada: % metros', distancia;

    -- Convertir el idconductor a entero
    idconductor_int := NEW.idconductor::INT;

    -- Si la camioneta sale del radio (inicio de viaje)
    IF distancia > 50 THEN
        RAISE NOTICE 'Camioneta fuera del radio, iniciando o continuando viaje';

        -- Buscar si hay un viaje en progreso
        SELECT id INTO viaje_actual
        FROM prueba_transporte.viajes
        WHERE idconductor = idconductor_int AND estado = 'en_progreso'
        LIMIT 1;

        -- Si no hay viaje en progreso, iniciar uno
        IF NOT FOUND THEN
            INSERT INTO prueba_transporte.viajes (idconductor, inicio, estado)
            VALUES (idconductor_int, NOW(), 'en_progreso')
            RETURNING id INTO viaje_actual;

            RAISE NOTICE 'Nuevo viaje iniciado con ID: %', viaje_actual;
        END IF;

        -- Registrar la coordenada en la tabla de historial
        INSERT INTO prueba_transporte.driver_history (
            original_id,
            lista,
            driver_location,
            idconductor,
            "nombreConductor",
            "numUrban",
            "Ruta",
            updated_at,
            viaje_id
        )
        VALUES (
            NEW.id,
            NEW.lista,
            NEW.driver_location,
            idconductor_int,
            NEW."nombreConductor",
            NEW."numUrban",
            NEW."Ruta",
            NOW(),
            viaje_actual
        );

        RAISE NOTICE 'Coordenada registrada para viaje ID: %', viaje_actual;
    END IF;

    -- Si la camioneta regresa al radio (fin del viaje)
    IF distancia <= 50 THEN
        RAISE NOTICE 'Camioneta regresó al radio, finalizando viaje';

        -- Finalizar el viaje actual
        UPDATE prueba_transporte.viajes
        SET fin = NOW(), estado = 'finalizado'
        WHERE idconductor = idconductor_int AND estado = 'en_progreso';

        RAISE NOTICE 'Viaje finalizado para conductor: %', idconductor_int;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


select * from vista_Seguimiento_rutas order by hora_cdmx desc;

SELECT * FROM prueba_transporte."rideMarcador_pg";
select * from prueba_transporte."driver_history" where idconductor = '1' and "Ruta" = 'PRUEBA';
select * from prueba_transporte.viajes where idconductor = '1';
select * from prueba_transporte.activity_logs WHERE idconductor = '1';
alter table prueba_transporte."rideMarcador_pg" add column fotoconductor varchar;}}
SELECT * FROM prueba_transporte.chofer_id;


ALTER TABLE prueba_transporte.driver_history drop column lista;

--tabla para gestionar viajes...

CREATE TABLE prueba_transporte.viajes (
    id SERIAL PRIMARY KEY,
    idconductor INT NOT NULL,
    inicio TIMESTAMP WITH TIME ZONE NOT NULL,
    fin TIMESTAMP WITH TIME ZONE,
	"Ruta" VARCHAR(8),
	"nombreConductor" VARCHAR(50),
    estado VARCHAR(20) DEFAULT 'en_progreso' -- Puede ser 'en_progreso' o 'finalizado'
	
);
----AGREGAR RUTA Y CONDUCTOR A VIAJES
ALTER TABLE prueba_transporte.viajes
ADD COLUMN "Ruta" VARCHAR(8),
ADD COLUMN "nombreConductor" VARCHAR(50);


--PRUEBA MANUAL---ejecutar...y ver resultados
UPDATE prueba_transporte."rideMarcador_pg" SET driver_location = 
'{"latitude": 19.352320, "longitude": -99.273532}' WHERE idconductor = '6'; --prueba manual correcta


--trigger actualizado:
CREATE OR REPLACE TRIGGER transportes_update
AFTER UPDATE ON prueba_transporte."rideMarcador_pg"
FOR EACH ROW
WHEN (NEW.driver_location IS DISTINCT FROM OLD.driver_location)
EXECUTE FUNCTION prueba_transporte.log_driver_updates();

ALTER TABLE prueba_transporte.driver_history
ADD COLUMN viaje_id INT REFERENCES prueba_transporte.viajes(id);

---LOGS-------------------


CREATE TABLE prueba_transporte.activity_logs (
    id SERIAL PRIMARY KEY,
	idconductor INTEGER,
    action_type TEXT,  -- 'error' o 'correcto'
    action_description TEXT,
    log_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE prueba_transporte.chofer_id (
	id SERIAL PRIMARY KEY,
	nombre_apellido TEXT,
	foto VARCHAR,
	status VARCHAR,
	fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);



INSERT INTO prueba_transporte.chofer_id ( nombre_apellido,
	foto,
	status
	) VALUES ('Emilio Maza Alvarez', 'null', 'activo');

---funcion actualizada con registro de logs...
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    BEGIN
        -- Verificar si driver_location contiene los campos necesarios
        IF NEW.driver_location ? 'latitude' AND NEW.driver_location ? 'longitude' THEN
            -- Extraer latitud y longitud del JSONB
            latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
            longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;
        ELSE
            RAISE EXCEPTION 'driver_location no contiene los campos latitude o longitude';
        END IF;

        -- Calcular la distancia desde el punto central (estacionamiento)
        distancia := ST_Distance(
            ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
            ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
        );

        -- Convertir el idconductor a entero
        idconductor_int := NEW.idconductor::INT;

        -- Si la camioneta sale del radio (inicio de viaje)
        IF distancia > 50 THEN
            -- Buscar si hay un viaje en progreso
            SELECT id INTO viaje_actual
            FROM prueba_transporte.viajes
            WHERE idconductor = idconductor_int AND estado = 'en_progreso'
            LIMIT 1;

            -- Si no hay viaje en progreso, iniciar uno
            IF NOT FOUND THEN
                INSERT INTO prueba_transporte.viajes (idconductor, inicio, estado)
                VALUES (idconductor_int, NOW(), 'en_progreso')
                RETURNING id INTO viaje_actual;

                -- Registrar inserción correcta
                INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
                VALUES ('correcto', 'Nuevo viaje iniciado con ID: ' || viaje_actual, idconductor_int);
            END IF;

            -- Registrar la coordenada en la tabla de historial
            INSERT INTO prueba_transporte.driver_history (
                original_id,
                driver_location,
                idconductor,
                "nombreConductor",
                "numUrban",
                "Ruta",
                updated_at,
                viaje_id
            )
            VALUES (
                NEW.id,
                NEW.driver_location,
                idconductor_int,
                NEW."nombreConductor",
                NEW."numUrban",
                NEW."Ruta",
                NOW(),
                viaje_actual
            );

            -- Registrar inserción correcta
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('correcto', 'Coord registrada de viaje ID: ' || viaje_actual, idconductor_int);
        END IF;

        -- Si la camioneta regresa al radio (fin del viaje)
        IF distancia <= 50 THEN
            -- Finalizar el viaje actual
            UPDATE prueba_transporte.viajes
            SET fin = NOW(), estado = 'finalizado'
            WHERE idconductor = idconductor_int AND estado = 'en_progreso';

            -- Registrar inserción correcta
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('correcto', 'Viaje finalizado para conductor: ' || idconductor_int, idconductor_int);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar el error en la tabla de logs
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('error', SQLERRM, idconductor_int);

            -- Lanzar el error para que se propague
            RAISE;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

----corregido solo registrando errores...
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    BEGIN
        -- Verificar si driver_location contiene los campos necesarios
        IF NEW.driver_location ? 'latitude' AND NEW.driver_location ? 'longitude' THEN
            -- Extraer latitud y longitud del JSONB
            latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
            longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;
        ELSE
            RAISE EXCEPTION 'driver_location no contiene los campos latitude o longitude';
        END IF;

        -- Calcular la distancia desde el punto central (estacionamiento)
        distancia := ST_Distance(
            ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
            ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
        );

        -- Convertir el idconductor a entero
        idconductor_int := NEW.idconductor::INT;

        -- Si la camioneta sale del radio (inicio de viaje)
        IF distancia > 50 THEN
            -- Buscar si hay un viaje en progreso
            SELECT id INTO viaje_actual
            FROM prueba_transporte.viajes
            WHERE idconductor = idconductor_int AND estado = 'en_progreso'
            LIMIT 1;

            -- Si no hay viaje en progreso, iniciar uno
            IF NOT FOUND THEN
                INSERT INTO prueba_transporte.viajes (idconductor, inicio, "Ruta", "nombreConductor", estado)
                VALUES (idconductor_int, NOW(), NEW."Ruta", NEW."nombreConductor", 'en_progreso')
                RETURNING id INTO viaje_actual;
            END IF;

            -- Registrar la coordenada en la tabla de historial
            INSERT INTO prueba_transporte.driver_history (
                original_id,
                driver_location,
                idconductor,
                "nombreConductor",
                "numUrban",
                "Ruta",
                updated_at,
                viaje_id
            )
            VALUES (
                NEW.id,
                NEW.driver_location,
                idconductor_int,
                NEW."nombreConductor",
                NEW."numUrban",
                NEW."Ruta",
                NOW(),
                viaje_actual
            );
        END IF;

        -- Si la camioneta regresa al radio (fin del viaje)
        IF distancia <= 50 THEN
            -- Finalizar el viaje actual
            UPDATE prueba_transporte.viajes
            SET fin = NOW(), estado = 'finalizado'
            WHERE idconductor = idconductor_int AND estado = 'en_progreso';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar el error en la tabla de logs
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('error', SQLERRM, idconductor_int);

            -- Lanzar el error para que se propague
            RAISE;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-----con vista----viajes in real time----

select * from vista_Seguimiento_rutas order by hora_cdmx desc;

SELECT * FROM prueba_transporte."rideMarcador_pg";
select * from prueba_transporte."driver_history" order by updated_at desc and idconductor = '1' and "Ruta" = 'PRUEBA';
select * from prueba_transporte.viajes where estado = 'en_progreso' and "Ruta" = 'R5';
select * from prueba_transporte.activity_logs WHERE idconductor = '1';
alter table prueba_transporte."rideMarcador_pg" add column fotoconductor varchar;}}
SELECT * FROM prueba_transporte.chofer_id;

ALTER TABLE prueba_transporte.chofer_id
ALTER COLUMN foto TYPE TEXT;

---

CREATE TABLE IF NOT EXISTS prueba_transporte.driver_history
(
    id integer NOT NULL DEFAULT nextval('prueba_transporte.driver_history_id_seq'::regclass),
    original_id integer NOT NULL,
    driver_location jsonb,
    idconductor character varying COLLATE pg_catalog."default",
    "nombreConductor" character varying COLLATE pg_catalog."default",
    "numUrban" character varying COLLATE pg_catalog."default",
    updated_at timestamp with time zone DEFAULT now(),
    "Ruta" character varying(10) COLLATE pg_catalog."default",
    viaje_id integer,
    CONSTRAINT driver_history_pkey PRIMARY KEY (id),
    CONSTRAINT driver_history_viaje_id_fkey FOREIGN KEY (viaje_id)
        REFERENCES prueba_transporte.viajes (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

---simple...
CREATE TABLE IF NOT EXISTS prueba_transporte.driver_history
(
    id SERIAL PRIMARY KEY,
    original_id INTEGER NOT NULL,
    driver_location JSONB,
    idconductor VARCHAR(7),
    nombreConductor VARCHAR(50),
    numUrban VARCHAR(5),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    Ruta VARCHAR(10),
    viaje_id INTEGER,
    CONSTRAINT driver_history_viaje_id_fkey FOREIGN KEY (viaje_id)
        REFERENCES prueba_transporte.viajes (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);


ALTER TABLE prueba_transporte.driver_history drop column lista;

--tabla para gestionar viajes...

CREATE TABLE prueba_transporte.viajes (
    id SERIAL PRIMARY KEY,
    idconductor INT NOT NULL,
    inicio TIMESTAMP WITH TIME ZONE NOT NULL,
    fin TIMESTAMP WITH TIME ZONE,
	"Ruta" VARCHAR(8),
	"nombreConductor" VARCHAR(50),
    estado VARCHAR(20) DEFAULT 'en_progreso' -- Puede ser 'en_progreso' o 'finalizado'
	
);
----AGREGAR RUTA Y CONDUCTOR A VIAJES
ALTER TABLE prueba_transporte.viajes
ADD COLUMN "Ruta" VARCHAR(8),
ADD COLUMN "nombreConductor" VARCHAR(50);


--PRUEBA MANUAL---ejecutar...y ver resultados
UPDATE prueba_transporte."rideMarcador_pg" SET driver_location = 
'{"latitude": 19.347234, "longitude": -99.283180}' WHERE idconductor = '6'; --prueba manual correcta


--trigger actualizado:
CREATE OR REPLACE TRIGGER transportes_update
AFTER UPDATE ON prueba_transporte."rideMarcador_pg"
FOR EACH ROW
WHEN (NEW.driver_location IS DISTINCT FROM OLD.driver_location)
EXECUTE FUNCTION prueba_transporte.log_driver_updates();

ALTER TABLE prueba_transporte.driver_history
ADD COLUMN viaje_id INT REFERENCES prueba_transporte.viajes(id);

---LOGS-------------------


CREATE TABLE prueba_transporte.activity_logs (
    id SERIAL PRIMARY KEY,
	idconductor INTEGER,
    action_type TEXT,  -- 'error' o 'correcto'
    action_description TEXT,
    log_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE prueba_transporte.chofer_id (
	id SERIAL PRIMARY KEY,
	nombre_apellido VARCHAR(255),
	foto VARCHAR(255),
	status BOOLEAN DEFAULT true,
	fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Cambiar el campo "status" a boolean
ALTER TABLE prueba_transporte.chofer_id
ALTER COLUMN status TYPE BOOLEAN USING (status = 'Activo');

-- Opcional: Establecer un valor predeterminado
ALTER TABLE prueba_transporte.chofer_id
ALTER COLUMN status SET DEFAULT false;

-- Opcional: Hacer que no permita nulos
ALTER TABLE prueba_transporte.chofer_id
ALTER COLUMN status SET NOT NULL;

INSERT INTO prueba_transporte.chofer_id ( nombre_apellido,
	foto,
	status
	) VALUES ('Emilio Maza Alvarez', 'null', 'activo');


----corregido solo registrando errores...
CREATE OR REPLACE FUNCTION prueba_transporte.log_driver_updates()
RETURNS TRIGGER AS $$
DECLARE
    distancia DOUBLE PRECISION;
    viaje_actual INT;
    latitud DOUBLE PRECISION;
    longitud DOUBLE PRECISION;
    idconductor_int INT;
BEGIN
    BEGIN
        -- Verificar si driver_location contiene los campos necesarios
        IF NEW.driver_location ? 'latitude' AND NEW.driver_location ? 'longitude' THEN
            -- Extraer latitud y longitud del JSONB
            latitud := (NEW.driver_location->>'latitude')::DOUBLE PRECISION;
            longitud := (NEW.driver_location->>'longitude')::DOUBLE PRECISION;
        ELSE
            RAISE EXCEPTION 'driver_location no contiene los campos latitude o longitude';
        END IF;

        -- Calcular la distancia desde el punto central (estacionamiento)
        distancia := ST_Distance(
            ST_SetSRID(ST_MakePoint(longitud, latitud), 4326)::geography,
            ST_SetSRID(ST_MakePoint(-99.283190, 19.347192), 4326)::geography
        );

        -- Convertir el idconductor a entero
        idconductor_int := NEW.idconductor::INT;

        -- Si la camioneta sale del radio (inicio de viaje)
        IF distancia > 50 THEN
            -- Buscar si hay un viaje en progreso
            SELECT id INTO viaje_actual
            FROM prueba_transporte.viajes
            WHERE idconductor = idconductor_int AND estado = 'en_progreso'
            LIMIT 1;

            -- Si no hay viaje en progreso, iniciar uno
            IF NOT FOUND THEN
                INSERT INTO prueba_transporte.viajes (idconductor, inicio, "Ruta", "nombreConductor", estado)
                VALUES (idconductor_int, NOW(), NEW."Ruta", NEW."nombreConductor", 'en_progreso')
                RETURNING id INTO viaje_actual;
            END IF;

            -- Registrar la coordenada en la tabla de historial
            INSERT INTO prueba_transporte.driver_history (
                original_id,
                driver_location,
                idconductor,
                "nombreConductor",
                "numUrban",
                "Ruta",
                updated_at,
                viaje_id
            )
            VALUES (
                NEW.id,
                NEW.driver_location,
                idconductor_int,
                NEW."nombreConductor",
                NEW."numUrban",
                NEW."Ruta",
                NOW(),
                viaje_actual
            );
        END IF;

        -- Si la camioneta regresa al radio (fin del viaje)
        IF distancia <= 50 THEN
            -- Finalizar el viaje actual
            UPDATE prueba_transporte.viajes
            SET fin = NOW(), estado = 'finalizado'
            WHERE idconductor = idconductor_int AND estado = 'en_progreso';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar el error en la tabla de logs
            INSERT INTO prueba_transporte.activity_logs (action_type, action_description, idconductor)
            VALUES ('error', SQLERRM, idconductor_int);

            -- Lanzar el error para que se propague
            RAISE;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

select * from prueba_transporte.viajes_real_time_view;
--VISTA FINAL DATA EN TIEMPO REAL
create view viajes_real_time_view as
SELECT 
    r.id AS id_rideMarcador,
    r.idconductor,
    r.driver_location,
    r."nombreConductor",
    r."numUrban",
    r."Ruta",
    r.imagenmarcador,
    r.fotoconductor,
    COALESCE(v.estado, 'sin_ruta') AS estado
FROM 
    prueba_transporte."rideMarcador_pg" r
LEFT JOIN 
    prueba_transporte.viajes v
ON 
    r.idconductor = CAST(v.idconductor AS VARCHAR) AND v.estado = 'en_progreso';

