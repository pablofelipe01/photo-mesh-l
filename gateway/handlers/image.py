"""
Image handler for AgroCam gateway.
Handles context messages (CTX|...) and builds analysis prompts with structured context.
"""

import time
import random
import string
import logging

logger = logging.getLogger(__name__)

# Per-sender context storage
user_context = {}

# Display maps for prompt building
CATEGORIA_MAP = {
    'hortalizas': 'Hortalizas',
    'frutales': 'Frutales',
    'granos': 'Granos',
    'flores': 'Flores',
    'hierbas': 'Hierbas',
    'pastos': 'Pastos',
    'tuberculos': 'Tuberculos',
    'leguminosas': 'Leguminosas',
    'industriales': 'Industriales',
    'otro': 'Otro',
}

AMBIENTE_MAP = {
    'exterior': 'exterior (campo abierto)',
    'invernadero': 'invernadero',
    'jardin': 'jardin domestico',
    'interior': 'interior',
    'hidroponico': 'sistema hidroponico',
}

PROBLEMA_MAP = {
    'manchas_hojas': 'manchas en las hojas',
    'hojas_secas': 'hojas secas o marchitas',
    'plagas': 'posibles plagas o insectos',
    'hongos': 'posible infeccion por hongos',
    'marchitamiento': 'marchitamiento general',
    'frutos_danados': 'frutos danados',
    'raiz_danada': 'problemas en la raiz',
    'crecimiento_anormal': 'crecimiento anormal',
    'evaluacion_general': 'evaluacion general del estado',
}

ETAPA_MAP = {
    'germinacion': 'germinacion',
    'vegetativo': 'crecimiento vegetativo',
    'floracion': 'floracion',
    'fructificacion': 'fructificacion',
    'cosecha': 'cosecha',
    'no_se': 'etapa no especificada',
}

CLIMA_MAP = {
    'tropical_humedo': 'tropical humedo',
    'tropical_seco': 'tropical seco',
    'templado': 'templado',
    'frio': 'frio',
    'arido': 'arido',
}


def handle_context(sender_id, message):
    """
    Parse CTX| message and store structured context for sender.
    Format: CTX|categoria|detalle|ambiente|problema|etapa|altitud|clima
    """
    try:
        parts = message.split('|')
        if len(parts) < 8:
            logger.warning(f"CTX message too short from {sender_id}: {message}")
            return False

        ctx = {
            'categoria': parts[1],
            'detalle': parts[2],
            'ambiente': parts[3],
            'problema': parts[4],
            'etapa': parts[5],
            'altitud': parts[6],
            'clima': parts[7],
            'timestamp': time.time(),
        }

        user_context[sender_id] = ctx
        logger.info(f"Context stored for {sender_id}: {ctx['categoria']}/{ctx['detalle']}")
        return True

    except Exception as e:
        logger.error(f"Error parsing CTX from {sender_id}: {e}")
        return False


def build_analysis_prompt(sender_id, tipo):
    """
    Build the Claude Vision analysis prompt.
    Uses structured context if available, falls back to tipo-based generic prompt.
    """
    ctx = user_context.get(sender_id)

    if ctx and (time.time() - ctx.get('timestamp', 0)) < 300:  # 5 min validity
        categoria = CATEGORIA_MAP.get(ctx['categoria'], ctx['categoria'])
        detalle = ctx['detalle']
        ambiente = AMBIENTE_MAP.get(ctx['ambiente'], ctx['ambiente'])
        problema = PROBLEMA_MAP.get(ctx['problema'], ctx['problema'])
        etapa = ETAPA_MAP.get(ctx['etapa'], ctx['etapa'])
        altitud = ctx['altitud']
        clima = CLIMA_MAP.get(ctx['clima'], ctx['clima'])

        prompt = (
            f"Eres un agronomo experto. El usuario tiene: {categoria} ({detalle}), "
            f"en {ambiente}, etapa {etapa}, reporta {problema}. "
            f"Altitud: {altitud}, Clima: {clima}. "
            f"Analiza la imagen y responde DIRECTAMENTE:\n"
            f"1. Que se observa (diagnostico especifico)\n"
            f"2. Causa probable\n"
            f"3. Accion recomendada\n"
            f"Se breve y directo. Maximo 3 parrafos."
        )

        # Clean up used context
        del user_context[sender_id]
        return prompt

    # Fallback: generic prompt based on tipo
    tipo_prompts = {
        'Plaga': (
            "Eres un agronomo experto en fitopatologia. "
            "Analiza esta imagen buscando plagas, insectos o enfermedades. "
            "Responde DIRECTAMENTE:\n"
            "1. Que se observa\n2. Causa probable\n3. Accion recomendada\n"
            "Se breve. Maximo 3 parrafos."
        ),
        'Suelo': (
            "Eres un agronomo experto en suelos. "
            "Analiza esta imagen del suelo o sustrato. "
            "Responde DIRECTAMENTE:\n"
            "1. Que se observa\n2. Posible problema\n3. Recomendacion\n"
            "Se breve. Maximo 3 parrafos."
        ),
        'Cultivo': (
            "Eres un agronomo experto. "
            "Evalua el estado general de este cultivo. "
            "Responde DIRECTAMENTE:\n"
            "1. Que se observa\n2. Estado del cultivo\n3. Recomendaciones\n"
            "Se breve. Maximo 3 parrafos."
        ),
        'General': (
            "Eres un agronomo experto. "
            "Analiza esta imagen agricola. "
            "Responde DIRECTAMENTE:\n"
            "1. Que se observa\n2. Evaluacion\n3. Recomendaciones\n"
            "Se breve. Maximo 3 parrafos."
        ),
    }

    return tipo_prompts.get(tipo, tipo_prompts['General'])


def generate_session_id():
    """Generate a random 4-character session ID."""
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
