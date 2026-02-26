import os
import uuid

from google import genai
from google.genai import types

from app.config import get_settings

settings = get_settings()
client = genai.Client(api_key=settings.GEMINI_API_KEY)


async def generate_bot_avatar(prompt: str) -> str:
    """Generate a bot avatar image using Imagen 4 via the google.genai SDK."""
    response = client.models.generate_images(
        model="imagen-4.0-fast-generate-001",
        prompt=f"A profile image: {prompt}.",
        config=types.GenerateImagesConfig(
            number_of_images=1,
        ),
    )

    if response.generated_images:
        os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
        filename = f"avatar_{uuid.uuid4().hex}.png"
        filepath = os.path.join(settings.UPLOAD_DIR, filename)
        response.generated_images[0].image.save(filepath)
        return f"/uploads/{filename}"

    return ""
