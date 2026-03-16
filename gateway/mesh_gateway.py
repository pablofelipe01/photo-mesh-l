"""
AgroCam Mesh Gateway - Main entry point.
Runs on Raspberry Pi, receives images via Meshtastic mesh,
analyzes with Claude Vision, and sends results back.

This file handles message routing. Actual logic is in handlers/.
"""

import time
import logging
import threading

from handlers import image
from handlers import session

logger = logging.getLogger(__name__)

# Periodic cleanup interval (seconds)
CLEANUP_INTERVAL = 60


def handle_incoming_message(from_num, text):
    """
    Route incoming mesh messages to the appropriate handler based on prefix.
    """
    if not text:
        return

    # Context message (structured form data, sent before image)
    if text.startswith('CTX|'):
        image.handle_context(from_num, text)
        return

    # Session end
    if text.startswith('SES_END|'):
        session.handle_session_end(from_num, text)
        return

    # Session question (SES_xxxx|pregunta)
    if text.startswith('SES_'):
        session.handle_session_message(from_num, text)
        return

    # Image protocol messages (existing, unchanged)
    if text.startswith('IMG_START|'):
        _handle_img_start(from_num, text)
        return

    if text.startswith('IMG|'):
        _handle_img_chunk(from_num, text)
        return

    if text.startswith('IMG_END|'):
        _handle_img_end(from_num, text)
        return

    if text.startswith('IMG_RESULT_ACK|'):
        _handle_img_result_ack(from_num, text)
        return

    # Normal text message - log and ignore
    logger.info(f"Text from {from_num}: {text[:80]}")


def _handle_img_start(from_num, text):
    """Handle IMG_START - placeholder, implement with existing logic."""
    logger.info(f"IMG_START from {from_num}: {text[:60]}")
    # TODO: Integrate with existing image reception logic


def _handle_img_chunk(from_num, text):
    """Handle IMG chunk - placeholder, implement with existing logic."""
    pass


def _handle_img_end(from_num, text):
    """Handle IMG_END - placeholder, implement with existing logic."""
    logger.info(f"IMG_END from {from_num}: {text[:60]}")
    # TODO: After image assembled, call image.build_analysis_prompt(from_num, tipo)
    # Then call Claude Vision API
    # Then send result back
    # Then create session: session.create_session(from_num, image_id, image_b64, ctx, result)


def _handle_img_result_ack(from_num, text):
    """Handle IMG_RESULT_ACK - placeholder, implement with existing logic."""
    logger.info(f"IMG_RESULT_ACK from {from_num}: {text[:60]}")


def start_cleanup_timer():
    """Start periodic cleanup of expired sessions."""
    def _cleanup_loop():
        while True:
            time.sleep(CLEANUP_INTERVAL)
            try:
                session.cleanup_expired_sessions()
            except Exception as e:
                logger.error(f"Session cleanup error: {e}")

    t = threading.Thread(target=_cleanup_loop, daemon=True)
    t.start()
    logger.info("Session cleanup timer started")


# Call this at gateway startup
# start_cleanup_timer()
