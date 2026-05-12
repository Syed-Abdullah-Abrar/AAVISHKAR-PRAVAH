import os
import sys
import asyncio
from dotenv import load_dotenv
load_dotenv()
MINIMAX_API_KEY = os.getenv("MINIMAX_API_KEY")
print("KEY:", MINIMAX_API_KEY[:5] if MINIMAX_API_KEY else None)
from openai import AsyncOpenAI
async def test():
    try:
        client = AsyncOpenAI(api_key=MINIMAX_API_KEY, base_url="https://api.minimaxi.chat/v1")
        response = await client.chat.completions.create(
            model="minimax-text-01", # Let's try minimax-text-01 or abab6.5s-chat
            messages=[{"role": "user", "content": "Hello"}]
        )
        print("SUCCESS:", response.choices[0].message.content)
    except Exception as e:
        print("ERROR:", str(e))
asyncio.run(test())
