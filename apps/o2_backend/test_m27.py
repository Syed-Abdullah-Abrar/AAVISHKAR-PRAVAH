print("START")
import os, asyncio
from dotenv import load_dotenv
from openai import AsyncOpenAI
print("IMPORT DONE")
load_dotenv()
MINIMAX_API_KEY = os.getenv("MINIMAX_API_KEY")
print("KEY LEN:", len(MINIMAX_API_KEY) if MINIMAX_API_KEY else 0)

async def test():
    print("IN TEST")
    client = AsyncOpenAI(api_key=MINIMAX_API_KEY, base_url="https://api.minimaxi.chat/v1")
    try:
        response = await client.chat.completions.create(
            model="minimax-m2.7",
            messages=[{"role": "user", "content": "Hello"}],
            timeout=10
        )
        print("SUCCESS:", response.choices[0].message.content)
    except Exception as e:
        print("ERROR:", str(e))
    print("DONE TEST")

print("RUNNING ASYNCIO")
asyncio.run(test())
print("EXITING")
