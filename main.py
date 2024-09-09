import logging
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.future import select
from sqlalchemy.orm import sessionmaker
from sqlalchemy import Column, Integer, String, JSON
from pydantic import BaseModel
import asyncpg
from typing import Optional
import os

# Configuración básica de logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("api_errors.log"),  # Guarda los logs en un archivo
        logging.StreamHandler()  # También imprime los logs en la consola
    ]
)

logger = logging.getLogger(__name__)

DATABASE_URL = "postgresql+asyncpg://postgres:1234@148.241.200.8/transporte"

# Configuración de la base de datos
engine = create_async_engine(DATABASE_URL, echo=True)
SessionLocal = sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)
Base = declarative_base()

# Definición del modelo
class Conductor(Base):
    __tablename__ = "rideMarcador_pg"
    __table_args__ = {"schema": "prueba_transporte"}
    id = Column(Integer, primary_key=True, index=True)
    driver_location = Column(JSON)
    idconductor = Column(String, index=True)
    imagenmarcador = Column(String, nullable=True)
    nombreConductor = Column(String)
    fotoconductor = Column(String, nullable=True)
    numUrban = Column(String)
    Ruta = Column(String)

# Modelo Pydantic para recibir los datos de actualización (con valores opcionales)
class ConductorUpdate(BaseModel):
    driver_location: Optional[dict] = None  # Acepta un dict en lugar de string para el JSON
    idconductor: Optional[str] = None
    imagenmarcador: Optional[str] = None
    nombreConductor: Optional[str] = None
    fotoconductor: Optional[str] = None
    numUrban: Optional[str] = None
    Ruta: Optional[str] = None

# Creación de la aplicación FastAPI
app = FastAPI()

# Middleware para manejar CORS (opcional, según tus necesidades)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependencia para obtener la sesión de la base de datos
async def get_db():
    async with SessionLocal() as session:
        yield session

# Ruta para obtener todos los datos de la tabla
@app.get("/conductores/")
async def read_conductores(skip: int = 0, limit: int = 10, db: AsyncSession = Depends(get_db)):
    try:
        result = await db.execute(select(Conductor).offset(skip).limit(limit))
        conductores = result.scalars().all()
        return conductores
    except Exception as e:
        logger.error(f"Error al obtener conductores: {e}")
        raise HTTPException(status_code=500, detail="Error al obtener los conductores")

# Ruta para actualizar un conductor existente basado en idconductor
@app.put("/conductores/{idconductor}")
async def update_conductor(idconductor: str, conductor_update: ConductorUpdate, db: AsyncSession = Depends(get_db)):
    try:
        # Obtener el conductor por idconductor
        result = await db.execute(select(Conductor).filter(Conductor.idconductor == idconductor))
        conductor = result.scalars().first()

        if not conductor:
            raise HTTPException(status_code=404, detail="Conductor no encontrado")

        # Actualizar solo los campos que están presentes en la solicitud
        if conductor_update.driver_location is not None:
            conductor.driver_location = conductor_update.driver_location
        if conductor_update.idconductor is not None:
            conductor.idconductor = conductor_update.idconductor
        if conductor_update.imagenmarcador is not None:
            conductor.imagenmarcador = conductor_update.imagenmarcador
        if conductor_update.nombreConductor is not None:
            conductor.nombreConductor = conductor_update.nombreConductor
        if conductor_update.fotoconductor is not None:
            conductor.fotoconductor = conductor_update.fotoconductor
        if conductor_update.numUrban is not None:
            conductor.numUrban = conductor_update.numUrban
        if conductor_update.Ruta is not None:
            conductor.Ruta = conductor_update.Ruta

        # Guardar los cambios
        await db.commit()

        return {"msg": "Conductor actualizado con éxito", "conductor": conductor}

    except Exception as e:
        logger.error(f"Error al actualizar el conductor {idconductor}: {e}")
        raise HTTPException(status_code=500, detail="Error al actualizar el conductor")

# Inicia los logs en el arranque de la aplicación
logger.info("La API de FastAPI ha iniciado con éxito.")
