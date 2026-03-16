"""
Session handler for AgroCam gateway.
Manages follow-up consultation sessions after image analysis.
"""

import time
import logging

logger = logging.getLogger(__name__)

# Active sessions: keyed by session_id
sessions = {}

# Limits
MAX_MESSAGES = 5
SESSION_TIMEOUT = 600  # 10 minutes


def create_session(sender_id, image_id, image_base64, context, analysis_result):
    """
    Create a new consultation session after a successful image analysis.
    Returns the session_id.

    Args:
        sender_id: Mesh node ID of the user
        image_id: The image ID that was analyzed
        image_base64: Base64-encoded image data for follow-up analysis
        context: The structured context dict (from handle_context)
        analysis_result: The text result from Claude Vision
    """
    from handlers.image import generate_session_id

    session_id = generate_session_id()

    sessions[session_id] = {
        'sender_id': sender_id,
        'image_id': image_id,
        'image_base64': image_base64,
        'context': context,
        'analysis_result': analysis_result,
        'messages': [],
        'message_count': 0,
        'created_at': time.time(),
        'last_activity': time.time(),
    }

    logger.info(f"Session {session_id} created for sender {sender_id}, image {image_id}")
    return session_id


def handle_session_message(sender_id, msg):
    """
    Handle a follow-up question: SES_xxxx|pregunta

    Validates session, calls Claude with full history (image + context + conversation),
    fragments and sends response.
    """
    try:
        # Parse: SES_xxxx|pregunta
        # First 4 chars after "SES_" are session ID, then | then question
        prefix = msg[4:]  # Remove "SES_"
        pipe_idx = prefix.index('|')
        session_id = prefix[:pipe_idx]
        question = prefix[pipe_idx + 1:]

        if not question.strip():
            logger.warning(f"Empty question from {sender_id} for session {session_id}")
            return

        ses = sessions.get(session_id)
        if ses is None:
            logger.warning(f"Session {session_id} not found for {sender_id}")
            _send_session_end(sender_id, session_id, "Sesion no encontrada o expirada")
            return

        # Validate sender
        if ses['sender_id'] != sender_id:
            logger.warning(f"Session {session_id} belongs to {ses['sender_id']}, not {sender_id}")
            return

        # Check timeout
        if time.time() - ses['last_activity'] > SESSION_TIMEOUT:
            logger.info(f"Session {session_id} timed out")
            _send_session_end(sender_id, session_id, "Sesion expirada (10 min)")
            del sessions[session_id]
            return

        # Check message limit
        if ses['message_count'] >= MAX_MESSAGES:
            logger.info(f"Session {session_id} reached message limit")
            _send_session_end(sender_id, session_id, "Limite de preguntas alcanzado (5/5)")
            del sessions[session_id]
            return

        # Record question
        ses['messages'].append({'role': 'user', 'text': question, 'timestamp': time.time()})
        ses['message_count'] += 1
        ses['last_activity'] = time.time()

        # Build follow-up prompt with full history
        prompt = _build_followup_prompt(ses, question)

        # Call Claude API with image
        response = _call_claude_with_session(ses, prompt)

        if response:
            # Record response
            ses['messages'].append({'role': 'assistant', 'text': response, 'timestamp': time.time()})

            # Fragment and send response
            _send_session_result(sender_id, session_id, response)
        else:
            _send_session_result(sender_id, session_id, "Error al procesar la consulta")

    except (ValueError, IndexError) as e:
        logger.error(f"Error parsing session message from {sender_id}: {e}")


def handle_session_end(sender_id, msg):
    """
    Handle SES_END|session_id from the app.
    Clean up the session.
    """
    try:
        parts = msg.split('|')
        if len(parts) < 2:
            return

        session_id = parts[1]
        ses = sessions.get(session_id)

        if ses and ses['sender_id'] == sender_id:
            del sessions[session_id]
            logger.info(f"Session {session_id} ended by user {sender_id}")
        else:
            logger.warning(f"Session {session_id} not found or wrong sender for end request")

    except Exception as e:
        logger.error(f"Error handling session end: {e}")


def cleanup_expired_sessions():
    """Remove sessions that have exceeded the timeout. Called periodically."""
    now = time.time()
    expired = [
        sid for sid, ses in sessions.items()
        if now - ses['last_activity'] > SESSION_TIMEOUT
    ]

    for sid in expired:
        ses = sessions[sid]
        sender_id = ses['sender_id']
        logger.info(f"Cleaning up expired session {sid} for {sender_id}")
        _send_session_end(sender_id, sid, "Sesion expirada")
        del sessions[sid]

    if expired:
        logger.info(f"Cleaned up {len(expired)} expired sessions")


def _build_followup_prompt(ses, new_question):
    """
    Build prompt for follow-up question including full conversation history.
    """
    ctx = ses.get('context', {})
    context_str = ""
    if ctx:
        context_str = (
            f"Contexto del cultivo: {ctx.get('categoria', '?')} ({ctx.get('detalle', '?')}), "
            f"ambiente: {ctx.get('ambiente', '?')}, etapa: {ctx.get('etapa', '?')}, "
            f"problema reportado: {ctx.get('problema', '?')}, "
            f"altitud: {ctx.get('altitud', '?')}, clima: {ctx.get('clima', '?')}.\n\n"
        )

    history_str = ""
    if ses['messages'][:-1]:  # Exclude the just-added question
        history_str = "Historial de la conversacion:\n"
        for msg in ses['messages'][:-1]:
            role = "Usuario" if msg['role'] == 'user' else "Agronomo"
            history_str += f"- {role}: {msg['text']}\n"
        history_str += "\n"

    prompt = (
        f"Eres un agronomo experto continuando una consulta. "
        f"{context_str}"
        f"Diagnostico inicial de la imagen:\n{ses['analysis_result']}\n\n"
        f"{history_str}"
        f"Nueva pregunta del usuario: {new_question}\n\n"
        f"Responde DIRECTAMENTE a la pregunta. Se breve y especifico. Maximo 2 parrafos."
    )

    return prompt


def _call_claude_with_session(ses, prompt):
    """
    Call Claude API with the image and follow-up prompt.

    This is a placeholder - integrate with your actual Claude API call.
    The image should be included in the API call for context.
    """
    # TODO: Implement actual Claude API call
    # Example:
    # response = anthropic_client.messages.create(
    #     model="claude-sonnet-4-20250514",
    #     max_tokens=500,
    #     messages=[{
    #         "role": "user",
    #         "content": [
    #             {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": ses['image_base64']}},
    #             {"type": "text", "text": prompt}
    #         ]
    #     }]
    # )
    # return response.content[0].text

    logger.warning("_call_claude_with_session: Claude API not yet integrated")
    return None


def _send_session_result(sender_id, session_id, text):
    """
    Fragment and send session result back via mesh.
    Format: SES_RESULT|sesId|part/total|texto

    This is a placeholder - integrate with your mesh send function.
    """
    max_text_per_part = 180
    parts = []
    for i in range(0, len(text), max_text_per_part):
        parts.append(text[i:i + max_text_per_part])

    if not parts:
        parts = [text]

    total = len(parts)
    for idx, part in enumerate(parts):
        msg = f"SES_RESULT|{session_id}|{idx + 1}/{total}|{part}"
        _send_to_mesh(sender_id, msg)

    logger.info(f"Sent session result ({total} parts) for {session_id} to {sender_id}")


def _send_session_end(sender_id, session_id, reason=""):
    """
    Send SES_END to the app to signal session termination.
    """
    msg = f"SES_END|{session_id}"
    if reason:
        msg += f"|{reason}"
    _send_to_mesh(sender_id, msg)
    logger.info(f"Sent SES_END for {session_id} to {sender_id}: {reason}")


def _send_to_mesh(sender_id, message):
    """
    Send a message back via mesh to the specified node.

    This is a placeholder - integrate with your actual Meshtastic send function.
    """
    # TODO: Implement actual mesh send
    # Example: meshtastic_interface.sendText(message, destinationId=sender_id)
    logger.info(f"[MESH TX -> {sender_id}] {message[:80]}")
